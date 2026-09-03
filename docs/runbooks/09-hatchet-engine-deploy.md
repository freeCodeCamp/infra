# 09 — Hatchet engine deploy (artemis stage-2)

Stands up the Hatchet durable-execution engine for artemis (ADR-020, artemis design 0001). Engine-only footprint: no api, no dashboard. Everything lands in the **artemis namespace**, sharing the bundled Postgres `hatchet` tenant created by the artemis chart.

All facts below were verified against hatchet v0.91.2 source (re-derived from v0.88.6 on 2026-09-03; every cited line held except `runV1Config` 535→537 and its `Healthcheck` read 561→563) (`pkg/config/server/server.go`, `cmd/hatchet-engine/engine/run.go`, `cmd/hatchet-admin/cli/k8s.go`, upstream `docker-compose.release.yml`).

## Invariants

| invariant                                                             | why                                                                                                                                                    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Engine image tag == artemis `go.mod` hatchet version (v0.91.2)        | monorepo lockstep: one git tag builds engine images and the Go SDK                                                                                     |
| `SERVER_GRPC_PORT=7077` everywhere                                    | binary default is **7070**; platform contract (artemis netpol, `HATCHET_ADDR`, upstream release compose) is 7077                                       |
| `SERVER_SERVICES="all health"`                                        | `all` routes to `runV1Config`, where `/live` + `/ready` start from `Runtime.Healthcheck` (`SERVER_HEALTHCHECK`, default true), NOT from this list. `health` is inert on v0.88.6; kept so a downgrade to the V0 path, where `HasService()` exact-match does require it, still starts the probes |
| `SERVER_MSGQUEUE_KIND=postgres`                                       | binary default is rabbitmq; postgres is the supported single-store mode (`oneof=rabbitmq postgres`)                                                    |
| keyset secret (`hatchet-config`) is generated once, never overwritten | regenerating keysets invalidates every issued worker token                                                                                             |
| `helm -n artemis` (via `.deploy-flags.sh`)                            | the `release` recipe hardcodes `-n {{ app }}`; the hook's later `-n artemis` wins (pflag last-value-wins), avoiding a spurious `hatchet` namespace     |

## A. One-time secret (operator)

DATABASE_URL carries `HATCHET_DB_PASSWORD` (same value as in `management/artemis.env.enc`):

```
# infra-secrets/k3s/gxy-management/hatchet.values.yaml.enc (sops)
secretEnv:
  DATABASE_URL: "postgres://hatchet:<HATCHET_DB_PASSWORD>@artemis-postgresql.artemis.svc.cluster.local:5432/hatchet?sslmode=disable"
```

## B. Release

Any chart change re-fires all four bootstrap hook Jobs on `helm upgrade` (`helm.sh/hook: pre-install,pre-upgrade` in `bootstrap-jobs.yaml` — quickstart, migrate, seed, plus the post-upgrade create-worker-token). All are idempotent by design (see the header comment in `bootstrap-jobs.yaml`); the keyset secret is generate-once and survives re-runs. Expect the upgrade to take a few minutes while the hooks complete; `helm upgrade --dry-run` first if unsure.

If a previous release attempt FAILED (e.g. revision 1 on 2026-06-06 — hook-ordering bug, fixed since), clean up first; a failed pre-install means zero regular manifests were applied, so uninstall is side-effect-free:

```
helm -n artemis uninstall hatchet
kubectl -n artemis delete jobs -l app.kubernetes.io/instance=hatchet
```

Then:

```
just release gxy-management hatchet
```

Release outside 02:55–04:05 UTC. The old ticker deactivates on shutdown and the new one claims
the crons on its next 15 s poll; a missed minute is not backfilled, so a release that straddles
03:00 or 04:00 skips that night's run.

Hook order (all idempotent):

1. `hatchet-quickstart` (pre, -10) — `hatchet-admin k8s quickstart` generates cookie secrets + 3 encryption keysets into Secret `hatchet-config` (only fills missing keys).
1. `hatchet-migrate` (pre, -5) — schema migrations on the hatchet DB. The v0.88.6 → v0.91.2 bump applies four (`v1_0_116` to `v1_0_119`, `cmd/hatchet-migrate/migrate/migrations`, 201 → 205 files).
1. `hatchet-seed` (pre, -4) — creates the default tenant `707d0855-80ab-4e1f-a156-f1c4546cbf52` if absent.
1. engine Deployment rolls out.
1. `hatchet-worker-token` (post, +5) — mints `HATCHET_CLIENT_TOKEN` into Secret `hatchet-client-config` (100y expiry; broadcast address claim = `hatchet-engine.artemis.svc.cluster.local:7077`).

## C. Verification gates (run each; stop on first failure)

```
export KUBECONFIG=...   # via direnv in k3s/gxy-management

# 1. release bookkeeping in artemis, not a stray namespace
helm -n artemis list | grep hatchet

# 2. jobs green
kubectl -n artemis get jobs -l app.kubernetes.io/instance=hatchet

# 3. BOTH engine replicas up, ready, and on DIFFERENT nodes.
#    Two distinct nodes is the whole point of the required anti-affinity;
#    a second Running pod on the same node means the affinity block did
#    not render and the values file is lying to you.
kubectl -n artemis get pods -l app.kubernetes.io/component=engine -o wide
kubectl -n artemis get pods -l app.kubernetes.io/component=engine \
  -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l   # must be 2

# 4. listening on 7077 (NOT 7070) + health, on EVERY pod.
#    `logs deploy/` and `port-forward deploy/` each pick ONE pod, so at
#    two replicas they leave the other unchecked. Loop by pod name.
for p in $(kubectl -n artemis get pods -l app.kubernetes.io/component=engine -o name); do
  echo "== $p"
  kubectl -n artemis logs "$p" | grep -i "grpc\|listen" | head -3
  kubectl -n artemis port-forward "$p" 18733:8733 >/dev/null 2>&1 &
  sleep 2; curl -sf http://127.0.0.1:18733/live && curl -sf http://127.0.0.1:18733/ready; echo
  kill $! 2>/dev/null
done

# 5. token minted
kubectl -n artemis get secret hatchet-client-config -o jsonpath='{.data.HATCHET_CLIENT_TOKEN}' | head -c 16
```

### 6. The double-fire gate — run this the MORNING AFTER, not at release time

Two replicas both run every service (`SERVER_SERVICES="all"`). A cron schedule has one owner
while that ticker heartbeats within 10 s (`ticker.sql:120`; heartbeat every 5 s, refresh every
15 s). A ticker that misses two heartbeats hands its schedules over with up to 15 s of dual
ownership, and a fire carries no dedup key. The controllers and scheduler are held by the tenant
partitioner. If either mechanism fails, the nightly crons fire twice — and `tombstone-purge`
performs destructive R2 deletes. Nothing at release time proves this; only a night does.

Baseline measured 2026-08-31, before the two-replica change: a day with no deploys is **exactly
two** runs, `tombstone-purge` at 03:00 UTC and `drift-detect` at 04:00 UTC, one fire each.

```sh
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d hatchet -tAc \
  "SELECT date_trunc('hour', r.inserted_at), w.name, count(*)
   FROM v1_runs_olap r JOIN \"Workflow\" w ON w.id = r.workflow_id
   WHERE r.inserted_at > now() - interval '2 days'
     AND w.name IN ('tombstone-purge', 'drift-detect')
   GROUP BY 1, 2 ORDER BY 1"
```

Every row must read `1`: one `tombstone-purge` in the 03:00 bucket and one `drift-detect` in the
04:00 bucket per day. A `2` on either row means that cron double-fired: roll the engine back to one
replica immediately (section E) and check the `tombstone-purge` audit rows in the `artemis` database
for duplicate deletes before doing anything else. `gc-site` is excluded on purpose; its event-driven
runs vary with deploys and would hide a double fire in a daily total.

## D. Wire artemis (separate release)

1. Extract the token, add `HATCHET_CLIENT_TOKEN` to `management/artemis.env.enc` + the artemis values overlay (`artemis.values.yaml.enc` → `secretEnv.HATCHET_CLIENT_TOKEN`). sops is operator-only.
1. In artemis `values.production.yaml`:
   - `env.HATCHET_ADDR: "hatchet-engine.artemis.svc.cluster.local:7077"`
   - `env.HATCHET_CLIENT_TLS_STRATEGY: "none"` — the Go SDK defaults to TLS (`pkg/config/shared` default "tls") and reads this from pod env; artemis itself does not parse it. Requires the configmap passthrough added with stage-2.
1. `just release gxy-management artemis` — boot gate: logs show `worker.starting` + `outbox.relay.started`, no Sentry boot fatals (T32), startupProbe passes.

## E. Rollback

- artemis side: unset `HATCHET_ADDR` → worker + relay gate off at next boot; deploys/registry unaffected (stage-1 posture).
- engine side, immediate: `kubectl -n artemis scale deploy hatchet-engine --replicas=1` takes effect at once. Persist it with the line below, or the next `just release` restores two.
- engine side, replica count only: `helm -n artemis upgrade hatchet <chart> --reuse-values --set engine.replicas=1` returns the single-replica posture without a teardown. Note this re-opens the ADR-022 §Prerequisite gate, so any destructive artemis write path depending on the engine is back to a single point of failure — tell the artemis owner.
- engine side, full: `helm -n artemis uninstall hatchet` removes engine + netpols. Secrets `hatchet-config`/`hatchet-client-config` are cluster-side artifacts created by the jobs (not helm-owned) and survive uninstall — keep them unless keyset rotation is intended. The hook resources (bootstrap SA/Role/RoleBinding, `hatchet-env-secret`) also survive uninstall (helm never garbage-collects hooks) — delete manually for full teardown.
- engine side, after the v0.91.2 bump: prefer scale-to-one on the new image. An image downgrade to v0.88.6 leaves `v1_0_116`–`v1_0_119` applied. 116–118 are additive (an index swap on `v1_runs_olap`, two defaulted columns on `v1_durable_event_log_entry`, the new `tenant_entitlement` table) and the old engine runs against them. 119 replaces `convert_duration_to_interval` with a superset parser that keeps the legacy `d`/`w`/`y` forms; the v0.88.6 engine's nine call sites run against the new body unproven. Reverse the schema with the goose `Down` sections of those four files before an image downgrade.
- GC has been live in gxy-management since the SHIP7 cutover (`CLEANUP_DRY_RUN: "false"`, `CLEANUP_BLAST_CAP: "10"`, `values.production.yaml`) — the worker moves real bytes, capped at 10 tombstoned deploys per run. Rolling back (unset `HATCHET_ADDR`) stops new GC runs immediately but does not undo ones already completed; those stay recoverable under `_trash/` for `CLEANUP_RECOVERY_DAYS` (7d default) before the purge cron hard-deletes.
