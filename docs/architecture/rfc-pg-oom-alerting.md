# RFC — Alerting for silent Postgres backend OOM kills

**Status:** proposed. **Cluster:** `gxy-management`. **Namespace:** `artemis`.
**Trigger:** incident 2026-08-23, found while shipping the hatchet PDB.

## Problem

The cgroup OOM killer has terminated PostgreSQL backend processes 37 times
since 2026-06-20 on `artemis-postgresql-0`. Each kill forces a full crash
recovery of the instance that carries both the `artemis` and the `hatchet`
tenant databases. Recovery takes about one second. No alert has ever fired.

Nothing fires because the postmaster is never the victim:

| Signal                          | Live value             | Fires? |
| ------------------------------- | ---------------------- | ------ |
| `memory.events` `oom_kill`      | 37                     | no exporter reads it |
| `memory.events` `oom_group_kill`| 0                      | never a pod-level kill |
| pod `restartCount`              | 1, from 2026-06        | unchanged by the kills |
| Kubernetes `OOMKilling` event   | none                   | not emitted for child processes |

A pod-level alert would report this database as healthy through all 37
events. That is the defect this RFC addresses. Raising the memory limit
reduces the rate; it does not restore visibility.

## What exists today

`gxy-management` runs no Prometheus, no Alertmanager, no Grafana, and no
`ServiceMonitor` or `PrometheusRule` CRDs. `metrics-server` is deployed but
the Metrics API does not answer (`kubectl top nodes` returns
`Metrics API not available`).

The one alerting channel in service is Sentry. artemis holds a `SENTRY_DSN`
and reports cron check-ins for the `tombstone-purge` and `drift-detect`
monitors (`docs/runbooks/12-node-drain-maintenance.md:74`).

## Signals evaluated

Two obvious SQL signals were tested against the live instance and both
fail. Do not reach for them again:

- `pg_postmaster_start_time()` returns `2026-06-06 03:40:18+00`. The
  postmaster survives crash recovery, so this value does not move.
- `pg_stat_database.stats_reset` is `NULL` for both tenant databases. It
  did not record the 2026-08-23T04:41:38Z recovery.

Two signals do work:

1. **cgroup counter.** `/sys/fs/cgroup/memory.events` `oom_kill` is
   monotonic per container. An increase means a kill. Precise and cheap,
   but the file is readable only from inside the postgres container's own
   cgroup, so a sidecar or node-level exporter is required.
2. **PostgreSQL log.** The postmaster writes
   `server process (PID n) was terminated by signal 9: Killed`, then
   `database system was not properly shut down; automatic recovery in
   progress`. Both lines reach the container log and are readable through
   the Kubernetes `pods/log` API. The `DETAIL:` line names the query that
   was running, which is the diagnostic the cgroup counter cannot give.

## Proposal

A CronJob in the `artemis` namespace that reads the postgres container log
through the Kubernetes API, matches the two markers since its last run, and
raises a Sentry event carrying the matched lines and the `DETAIL:` query.

- **Signal:** log markers, not the cgroup counter. Log access needs only a
  namespaced `Role` granting `get` on `pods/log`. The cgroup counter needs
  either a privileged sidecar or a hostPath mount, and the namespace
  enforces the restricted Pod Security Standard.
- **Channel:** Sentry, reusing the existing artemis DSN. This adds no new
  platform component.
- **Schedule:** every 15 minutes, with a 20-minute log lookback so a
  missed run does not drop an event.
- **Deduplication:** Sentry fingerprint on the marker, so a burst of
  backend kills inside one recovery raises one issue, not twenty.

### Why not Prometheus

Standing up Prometheus, node-exporter and Alertmanager to watch one counter
adds a permanent platform component, its own storage, and its own failure
modes to a three-node control plane that has none today. If the platform
later needs metrics for other reasons, move this alert to a
`container_memory_failcnt` rule and delete the CronJob.

## Open questions for the operator

1. Should the alert route to the existing artemis Sentry project, or to a
   separate infra project? Sharing the project means the DSN is already in
   the namespace; separating it keeps application errors and platform
   faults apart.
2. Is a 15-minute detection latency acceptable? A tighter loop is cheap but
   raises the log-read rate against the API server.
3. Does the same alert belong on `valkey`, which carries a PDB and the same
   class of single-replica exposure?

## Scope boundary

This RFC covers detection only. The memory sizing change is separate and
already shipped in chart `artemis-0.6.0`. Bounding the hatchet engine
connection pool is tracked as artemis #45 and needs a measurement at
04:00 UTC before a cap is chosen — 7 of the 37 kills fall in the
04:00-04:02 window, against 2 in the 03:00-03:14 window, so `drift-detect`
is the heavier of the two nightly workloads.
