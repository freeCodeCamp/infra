# 11 — Artemis PG-outage drill (R7)

**Audience:** Operator **Trigger:** Rehearse invariant R7 — a PG outage pauses new deploys + GC only; every existing site keeps serving from R2.

Proves the artemis HA boundary: the control plane (deploy API + retention-GC) depends on the bundled Postgres, but the **serve plane** (`<site>.freecode.camp` via the Traefik/Caddy `r2_alias` module reading R2 directly) does not. Taking PG down must degrade the control plane gracefully and leave serving untouched.

> **Destructive to the artemis control plane.** The bundled Postgres serves both the artemis and Hatchet tenants. During the drill new deploys and GC are paused. Run in a low-traffic window with operator sign-off. Serving is unaffected, so end users see nothing.

All `kubectl` runs against gxy-management:

```
direnv exec /Users/mrugesh/DEV/fCC/infra kubectl --kubeconfig=k3s/gxy-management/.kubeconfig.yaml -n artemis <cmd>
```

## Preconditions

- artemis healthy: `get pods -l app.kubernetes.io/component=deploy-proxy` → 3/3 Ready, 0 restarts.
- A known live site to probe, e.g. `www.freecode.camp`.
- `just release`-clean tree (no pending chart change mid-drill).

## Baseline (before)

1. `curl -sS -o /dev/null -w '%{http_code}\n' https://uploads.freecode.camp/readyz` → `200` `{"ready":true}`.
1. `curl -sS -o /dev/null -w '%{http_code}\n' https://www.freecode.camp/` → `200` (serve plane).
1. Note the bundled PG workload name: `get statefulset -l app.kubernetes.io/name=postgresql` (e.g. `artemis-postgresql`).

## Induce the outage

Scale the bundled Postgres to zero (reversible; PVC + data retained):

```
kubectl -n artemis scale statefulset artemis-postgresql --replicas=0
kubectl -n artemis rollout status statefulset artemis-postgresql --timeout=60s   # terminating
```

## Assert R7 (during outage)

| #   | Check                             | Expected                                                                                                                             |
| --- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| a   | `curl .../readyz`                 | **`200` `{"ready":true,"degraded":true}`** — PG degraded, NOT hard-down. `503` here is a FAIL (serve plane must not be gated on PG). |
| b   | `curl https://www.freecode.camp/` | **`200`** — existing sites keep serving from R2, independent of artemis PG.                                                          |
| c   | New deploy pauses gracefully      | `universe-cli deploy` (or `POST /api/deploy/init`) fails with a clear upstream error (PG unreachable), **not** a 5xx crash / panic.  |
| d   | Pods stay up                      | `get pods` → still Running, no CrashLoopBackOff; `logs` shows no panic, worker/relay pause quietly.                                  |

If any of a–d fails, STOP and record the deviation — R7 is not holding.

## Restore + verify recovery

```
kubectl -n artemis scale statefulset artemis-postgresql --replicas=1
kubectl -n artemis rollout status statefulset artemis-postgresql --timeout=120s
```

1. `curl .../readyz` → `200 {"ready":true}` (degraded flag gone).
1. New deploy succeeds end-to-end (see runbook 03 postdeploy E2E).
1. GC/worker resume: `logs` shows the outbox relay draining, no backlog panic.

## Record

Stamp the outcome + RPO/RTO observations (outage duration, time-to-ready-after-restore) here and in the durable-exec dossier §S (R7 gate):

- **Last rehearsed:** _(pending — operator to run and stamp)_

## Cross-refs

- Invariant R7 — artemis durable-exec-cutover dossier §V.
- Restore-from-backup (data-loss, not just outage): [08-artemis-pg-restore-drill.md](08-artemis-pg-restore-drill.md).
- Postdeploy E2E used in recovery step: [03-artemis-postdeploy-check.md](03-artemis-postdeploy-check.md).
