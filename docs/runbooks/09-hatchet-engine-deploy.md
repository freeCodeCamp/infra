# 09 — Hatchet engine deploy (artemis stage-2)

Stands up the Hatchet durable-execution engine for artemis (ADR-020, artemis design 0001). Engine-only footprint: no api, no dashboard. Everything lands in the **artemis namespace**, sharing the bundled Postgres `hatchet` tenant created by the artemis chart.

All facts below were verified against hatchet v0.88.6 source (`pkg/config/server/server.go`, `cmd/hatchet-engine/engine/run.go`, `cmd/hatchet-admin/cli/k8s.go`, upstream `docker-compose.release.yml`).

## Invariants

| invariant                                                             | why                                                                                                                                                    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Engine image tag == artemis `go.mod` hatchet version (v0.88.6)        | monorepo lockstep: one git tag builds engine images and the Go SDK                                                                                     |
| `SERVER_GRPC_PORT=7077` everywhere                                    | binary default is **7070**; platform contract (artemis netpol, `HATCHET_ADDR`, upstream release compose) is 7077                                       |
| `SERVER_SERVICES="all health"`                                        | `HasService()` is an exact match — `all` does NOT enable the `/live` + `/ready` health server (`run.go:161`); without `health` the probes kill the pod |
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

If a previous release attempt FAILED (e.g. revision 1 on 2026-06-06 — hook-ordering bug, fixed since), clean up first; a failed pre-install means zero regular manifests were applied, so uninstall is side-effect-free:

```
helm -n artemis uninstall hatchet
kubectl -n artemis delete jobs -l app.kubernetes.io/instance=hatchet
```

Then:

```
just release gxy-management hatchet
```

Hook order (all idempotent):

1. `hatchet-quickstart` (pre, -10) — `hatchet-admin k8s quickstart` generates cookie secrets + 3 encryption keysets into Secret `hatchet-config` (only fills missing keys).
1. `hatchet-migrate` (pre, -5) — schema migrations on the hatchet DB.
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

# 3. engine up + ready (startupProbe budget 120s)
kubectl -n artemis get pods -l app.kubernetes.io/component=engine

# 4. listening on 7077 (NOT 7070) + health
kubectl -n artemis logs deploy/hatchet-engine | grep -i "grpc\|listen" | head
kubectl -n artemis port-forward deploy/hatchet-engine 18733:8733 &
curl -sf http://127.0.0.1:18733/live && curl -sf http://127.0.0.1:18733/ready

# 5. token minted
kubectl -n artemis get secret hatchet-client-config -o jsonpath='{.data.HATCHET_CLIENT_TOKEN}' | head -c 16
```

## D. Wire artemis (separate release)

1. Extract the token, add `HATCHET_CLIENT_TOKEN` to `management/artemis.env.enc` + the artemis values overlay (`artemis.values.yaml.enc` → `secretEnv.HATCHET_CLIENT_TOKEN`). sops is operator-only.
1. In artemis `values.production.yaml`:
   - `env.HATCHET_ADDR: "hatchet-engine.artemis.svc.cluster.local:7077"`
   - `env.HATCHET_CLIENT_TLS_STRATEGY: "none"` — the Go SDK defaults to TLS (`pkg/config/shared` default "tls") and reads this from pod env; artemis itself does not parse it. Requires the configmap passthrough added with stage-2.
1. `just release gxy-management artemis` — boot gate: logs show `worker: starting` + `outbox relay: started`, no Sentry boot fatals (T32), startupProbe passes.

## E. Rollback

- artemis side: unset `HATCHET_ADDR` → worker + relay gate off at next boot; deploys/registry unaffected (stage-1 posture).
- engine side: `helm -n artemis uninstall hatchet` removes engine + netpols. Secrets `hatchet-config`/`hatchet-client-config` are cluster-side artifacts created by the jobs (not helm-owned) and survive uninstall — keep them unless keyset rotation is intended. The hook resources (bootstrap SA/Role/RoleBinding, `hatchet-env-secret`) also survive uninstall (helm never garbage-collects hooks) — delete manually for full teardown.
- Worker processes nothing destructive regardless: `CLEANUP_DRY_RUN` stays `true` until the SHIP7 cutover flip.
