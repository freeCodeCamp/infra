# Artemis Post-Deploy Check

End-to-end verification that a deployed artemis instance is healthy and serves the full deploy lifecycle. Run after every artemis chart upgrade or any change that touches the deploy/serve chain (artemis chart, caddy-s3 chart, R2 bucket policy, sites registry mutations).

Source of truth for the test bodies lives in the artemis repo at `internal/integration/` (build-tagged Go suite). This runbook covers how to wire and trigger the suite from the infra repo.

## When to run

- Immediately after `just release gxy-management artemis`
- After caddy-s3 chart bump on `gxy-cassiopeia`
- After any `universe sites register/update` against a smoke-eligible slug (validates authz wiring)
- After secrets rotation (R2 keys, JWT signing key, GH OAuth)
- Before promoting a real customer site to production (smoke first)
- After either stage of the durable-exec bootstrap (run the §Durable-exec substrate check below in addition to the E2E suite)

## Prerequisites

| Requirement                 | Verify                                                                                            |
| --------------------------- | ------------------------------------------------------------------------------------------------- |
| Local artemis repo checkout | `ls $HOME/DEV/fCC/artemis/Makefile`                                                               |
| Go toolchain (≥ 1.24)       | `go version`                                                                                      |
| GitHub CLI authenticated    | `gh auth status` (any GH account; team must match site)                                           |
| Caller's team in registry   | `gh api /user/teams --jq '.[].slug'` — at least one entry must appear under the slug's teams      |
| Artemis reachable           | `curl -fsS https://uploads.freecode.camp/healthz`                                                 |
| Test site authorized        | `universe sites ls \| grep '^test '` shows `test` registered with at least one team you belong to |

## Run

```sh
cd /Users/mrugesh/DEV/fCC/infra
just verify-artemis
```

That's it. The recipe:

1. Curls `${ARTEMIS_URL}/healthz` (default `https://uploads.freecode.camp`)
1. Resolves a GH token via `${GH_TOKEN}` or `gh auth token`
1. Shells into `${ARTEMIS_REPO}` (default `$HOME/DEV/fCC/artemis`)
1. Runs `make integration` — the Go E2E suite

Expected wall time: 2–5 minutes (production-alias SLO is 2 min per D38).

## Override env

| Variable       | Default                         | Purpose                          |
| -------------- | ------------------------------- | -------------------------------- |
| `ARTEMIS_URL`  | `https://uploads.freecode.camp` | Live deployment to probe         |
| `ARTEMIS_REPO` | `$HOME/DEV/fCC/artemis`         | Local artemis checkout           |
| `GH_TOKEN`     | `gh auth token`                 | GH bearer authorized for `SITE`  |
| `SITE`         | `test`                          | Registered site slug             |
| `ROOT_DOMAIN`  | `freecode.camp`                 | Public root domain               |
| `PROD_SLO`     | `2m`                            | Production-alias serve SLO (D38) |
| `PREVIEW_SLO`  | `90s`                           | Preview-alias serve SLO          |

Example targeting a staging artemis:

```sh
ARTEMIS_URL=https://uploads.staging.freecode.camp \
  SITE=test ROOT_DOMAIN=staging.freecode.camp \
  just verify-artemis
```

## What the suite covers

Tests defined in `artemis/internal/integration/proxy_e2e_test.go`:

| Test                 | Asserts                                                                                                          |
| -------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `TestHealthZ`        | `GET /healthz` → 200 `{ok:true}`                                                                                 |
| `TestWhoAmI`         | `GET /api/whoami` returns login + `authorizedSites` containing `SITE`                                            |
| `TestAuthRejections` | Bad token → 401/403, missing token → 401, unknown site → 403, no `site` → 400                                    |
| `TestDeployFlow`     | Full happy path: init → upload → finalize(preview) → curl preview → promote → curl prod (D38 SLO) → list deploys |
| `TestRollback`       | Production alias rewires to a prior deploy id                                                                    |

## Setup / teardown

Suite-level (`TestMain` in `artemis/internal/integration/setup_teardown_test.go`):

| Phase    | Action                                                                                       |
| -------- | -------------------------------------------------------------------------------------------- |
| Setup    | Pre-flight `GET /healthz` — abort with exit 2 if artemis unreachable                         |
| Setup    | Capture baseline production deploy id from `GET /api/site/{site}/deploys` (head entry)       |
| Run      | Execute all tests in the package                                                             |
| Teardown | `POST /api/site/{site}/rollback {"to": baseline}` — restore prod alias to the captured state |

Net effect: the suite leaves the production alias **exactly where it found it**, even after `TestDeployFlow` promotes a new deploy mid-run. The new deploy prefix is left in R2 for cleanup-cron sweep (T22, 7-day retention).

If teardown fails, the run output prints the manual recovery curl:

```
[teardown] WARN: restore prod alias failed: <err>
[teardown]      manual fix: POST /api/site/test/rollback {"to":"<baseline>"}
```

Edge cases:

- **Fresh site (no prior deploys):** baseline capture returns empty; teardown becomes a no-op.
- **`ARTEMIS_URL`/`GH_TOKEN` unset:** `TestMain` skips capture/teardown entirely; individual tests `Skip` themselves.
- **`/healthz` down at setup time:** `TestMain` aborts before any test runs (exit 2) so the operator sees the deployment-side fault immediately rather than five minutes of test-side timeouts.

## Pass criteria

- `make integration` exits 0
- Setup log: `[setup] healthz green at <ARTEMIS_URL>` and `[setup] captured baseline: site=test deployId=<id>`
- Final test line: `OK — full deploy flow green for site=test deployId=<id>`
- Teardown log: `[teardown] restored prod alias: site=test deployId=<id>`

## Durable-exec substrate check

Run this in addition to the E2E suite after either stage of the durable-exec bootstrap (runbook 02 §Staged durable-exec bootstrap). The E2E suite above exercises only the deploy/serve plane; these checks cover the bundled Postgres + Hatchet worker that the suite does not touch. Skip entirely on a deploy-only (`postgres.enabled: false`) deployment.

All commands run against the cluster, not the public surface:

```sh
cd /Users/mrugesh/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
```

### 1. Postgres StatefulSet ready + tenants bootstrapped

```sh
kubectl -n artemis rollout status statefulset/artemis-postgresql --timeout=120s
kubectl -n artemis exec statefulset/artemis-postgresql -- \
  psql -U postgres -c '\l' | grep -E 'artemis|hatchet'
```

Expect the StatefulSet ready and both `artemis` + `hatchet` databases present (bootstrapped by the init ConfigMap, owned by their like-named roles).

### 2. Migrations applied + worker state matches the stage

```sh
kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=20m \
  | grep -E 'postgres: connected, migrations applied|gc: wired|worker: starting|outbox relay: started'
```

| Stage                  | Expect present                                         | Expect absent                               |
| ---------------------- | ------------------------------------------------------ | ------------------------------------------- |
| 1 (HATCHET_ADDR unset) | `postgres: connected, migrations applied`, `gc: wired` | `worker: starting`, `outbox relay: started` |
| 2 (HATCHET_ADDR set)   | all four lines                                         | —                                           |

### 3. Readiness probe (degraded semantics)

`/readyz` probes Valkey + R2 + Postgres. It is NOT exposed past the Gateway path that auth-gates `/api/*`, so probe it in-cluster:

```sh
kubectl -n artemis exec deploy/artemis -- \
  wget -qO- http://localhost:8080/readyz
```

Expected:

- `{"ready":true}` — all three upstreams healthy.
- `{"ready":true,"degraded":true}` — Postgres unreachable but Valkey + R2 up. HTTP stays `200`, pod stays in rotation; deploy/serve unaffected, GC impaired. Investigate the PG StatefulSet.
- HTTP `503` — Valkey or R2 down (a hard fault), NOT Postgres.

### 4. Backup CronJob present (durable-exec profile)

```sh
kubectl -n artemis get cronjob artemis-backup -o wide
```

Expect the nightly CronJob (`schedule: 0 2 * * *`). Full backup verify + restore drill is runbook 08; this check only confirms the chart rendered it. A missing CronJob on a `backup.enabled` deployment means the overlay did not flip `backup.enabled: true`.

## Failure paths

| Symptom                                           | Diagnose                                                           | Mitigate                                                                                               |
| ------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `healthz unreachable`                             | DNS / CF / artemis pod down                                        | `kubectl -n artemis get pods,svc,httproute`; CF dashboard A-record; `kubectl logs`                     |
| `whoami: site not in authorized list`             | Caller's GH teams have no overlap with the slug's registered teams | `gh api /user/teams --jq '.[].slug'`; `universe sites ls \| grep '^test '` to inspect the slug's teams |
| `bad token: status=200`                           | Auth middleware not enforcing                                      | Inspect `RequireGitHubBearer` chain; check chart `httproute.yaml` is in front of pod                   |
| `init: 422 verify_failed`                         | Caller's GH teams stale vs registry teams just-changed             | retry after ≤60 s TTL fallback; `kubectl -n artemis logs … \| grep registry.changed`                   |
| `finalize preview: 502 r2_put_failed`             | R2 endpoint or admin key wrong; bucket policy lacks PutObject      | Decrypt `infra-secrets/management/artemis.env.enc`; re-validate against R2 dashboard                   |
| `preview: marker not seen` (timeout)              | Caddy `r2_alias` cache TTL too long, or alias key format mismatch  | `kubectl -n caddy logs -l app=caddy --tail=200`; check `ALIAS_PREVIEW_KEY_FORMAT`                      |
| `production: marker not seen` in 2 min            | CF edge cache holding old content; alias path mismatch             | Check `cf-cache-status` header; CF cache purge tool                                                    |
| `rollback: deployId mismatch`                     | Target deploy prefix swept by cleanup cron (T22, 7-day retention)  | Pick a more recent `deployId` from `/deploys`; or rerun TestDeployFlow twice                           |
| `/readyz` returns `degraded:true`                 | Postgres unreachable; Valkey + R2 fine                             | `kubectl -n artemis get sts artemis-postgresql`; `kubectl -n artemis logs sts/artemis-postgresql`      |
| Stage-2 release but no `worker: starting` log     | `env.HATCHET_ADDR` empty or Hatchet engine unreachable             | Check `HATCHET_ADDR` in `values.production.yaml`; verify engine Service gRPC port = `hatchet.grpcPort` |
| `gc: wired` absent on a `postgres.enabled` deploy | image pinned to pre-durable-exec `0.8.0`                           | RELEASE-CUT CHECKLIST item 2 in runbook 02 — bump image off `0.8.0`                                    |

## Related

- `internal/integration/doc.go` — full env-var contract
- `make integration-help` (run inside artemis repo) — same as above, terse
- ADR-016 (`Universe/decisions/016-deploy-proxy.md`) — design rationale, SLOs (Q6, D38)
- ADR-020 — durable-execution model (the Postgres + Hatchet substrate this section checks)
- [`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) §Staged durable-exec bootstrap — the deploy procedure this verifies
- [`08-artemis-pg-restore-drill.md`](08-artemis-pg-restore-drill.md) — PG backup restore drill (RPO/RTO floor)
- artemis registry (Valkey-backed; `universe sites ls` to inspect) — authoritative team→site map

## Rollback

This suite is idempotent and safe:

- Writes only under `SITE` (default `test`, staff-only)
- `TestRollback` restores production alias to the most-recent deploy at end of run
- Cleanup cron (T22, 7-day retention) sweeps stale deploy prefixes

If a run leaves production pinned to an unintended deploy:

```sh
GH_TOKEN=$(gh auth token)
curl -sS https://uploads.freecode.camp/api/site/test/deploys \
  -H "Authorization: Bearer $GH_TOKEN" | jq .
# Pick the desired deployId, then:
curl -sS -X POST https://uploads.freecode.camp/api/site/test/rollback \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"to":"<deployId>"}'
```
