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

## Decisions (operator, 2026-08-23)

1. **Sentry project:** the existing artemis project. The DSN is already in
   `artemis-env-secret`, so no new secret and no sops round-trip. Events
   carry a `component=platform-db` tag so Sentry rules can route them
   apart from application errors.
2. **Detection latency:** 15 minutes, with a 20-minute log lookback.
3. **Scope:** any container in the `artemis` namespace, not Postgres
   alone.

## Scope change: what "any container" costs

Widening to the whole namespace looked expensive and is not, because the
invisible failure mode does not exist for most containers.

A cgroup OOM kill is only survivable-and-silent when the container runs
more than one process. The kernel picks the largest process in the
cgroup; if that is not PID 1, the container keeps running and Kubernetes
reports nothing. Postgres has a postmaster plus one backend per
connection, so it can lose a child and stay up — that is exactly the 43
kills nobody saw. A single-process container cannot fail this way: kill
its only process and the container restarts, which the API reports.

Probed 2026-08-23 across the namespace:

| Container | Processes | Shell | Detection signal |
| --------- | --------- | ----- | ---------------- |
| `artemis` x3 | single Go binary | **none** (distroless) | API `lastState.terminated.reason` |
| `hatchet-engine` | single Go binary | yes | API `lastState.terminated.reason` |
| `postgresql` | postmaster + N backends | yes | log markers |

The three artemis containers have no shell, so no exec-based probe could
ever have read their cgroups. It does not matter: they cannot fail
silently, so the API signal is complete for them.

## Two signals, both plain API reads

1. **All containers** — GET pods, compare `restartCount` and
   `lastState.terminated.reason == OOMKilled` against the previous run.
   Catches every single-process container.
2. **Postgres only** — GET `pods/log`, match
   `terminated by signal 9` and `database system was not properly shut
   down`. Catches the multi-process case, and the `DETAIL:` line names
   the query that was running.

Both are HTTPS GETs against the kube-apiserver with a namespaced
ServiceAccount token. **No `pods/exec`, no hostPath, no privileged
sidecar, no node access** — which keeps the job inside the namespace's
restricted Pod Security Standard.

State between runs lives in a ConfigMap the job updates, so the RBAC is
`get`/`list` on `pods`, `get` on `pods/log`, and `get`/`update` on that
one ConfigMap.

## Pool-cap baseline job (retired 2026-08-24)

A hand-applied `pool-baseline` CronJob sampled `pg_stat_activity` every
30s across the 03:50-04:25 UTC window. It was deliberately kept out of
the Helm chart: any chart version bump rewrites the ConfigMap labels,
which changes `checksum/config-env` and rolls the artemis pods — too
much disturbance for a throwaway probe.

It ran once, answered the question below, and was deleted from the
cluster and the repo on 2026-08-24.

### Result (2026-08-24)

The single run covered 03:50-04:25Z and returned 70 samples on the
`hatchet` database: min 18, max 26, mean 21.8. The value 26 appeared in
one sample. `artemis` peaked at 4 and `postgres` at 1.

The sampler reads `pg_stat_activity` server-side, so it cannot separate
the engine's main pool from its DDL pool — both dial the same
`DATABASE_URL` (`pkg/config/loader/loader.go:115` and `:296`). The
measured 26 therefore covers main plus DDL together, and the main-pool
peak is at most 26.

Chosen cap: `DATABASE_MAX_CONNS=40`, in chart `hatchet-0.4.0`. That
lowers the engine's server-side ceiling from 55 (upstream `MaxConns` 50
plus a DDL pool of 5) to 45, while leaving at least 14 connections of
headroom above the observed peak.

The same commit sets `livenessProbe.failureThreshold: 6`. `/live` runs
its health query on the capped main pool
(`internal/services/health/health.go:42-51` calling
`pkg/repository/health.go:24-32`), and `pgxpool` blocks rather than
errors when a pool is exhausted, so without the explicit threshold three
10-second probe failures would restart the engine after roughly 30
seconds of saturation. Six gives 60 seconds.

## Scope boundary

This RFC covers detection only. The memory sizing change is separate and
already shipped in chart `artemis-0.6.0`. Bounding the hatchet engine
connection pool was tracked as artemis #45; the measurement it waited on
landed on 2026-08-24 and the cap is recorded above. 7 of the 37 kills
fell in the 04:00-04:02 window, against 2 in the 03:00-03:14 window, so
`drift-detect` is the heavier of the two nightly workloads.
