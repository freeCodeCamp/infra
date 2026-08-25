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
1. Runs `just integration` — the Go E2E suite

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

- `just integration` exits 0
- Setup log: `[setup] healthz green at <ARTEMIS_URL>` and `[setup] captured baseline: site=test deployId=<id>`
- Final test line: `OK — full deploy flow green for site=test deployId=<id>`
- Teardown log: `[teardown] restored prod alias: site=test deployId=<id>`

## Durable-exec substrate check

Run this in addition to the E2E suite after either stage of the durable-exec bootstrap (runbook 02 §Staged durable-exec bootstrap). The E2E suite above exercises only the deploy/serve plane; these checks cover the bundled Postgres + Hatchet worker that the suite does not touch. Skip entirely on a deploy-only (`postgres.enabled: false`) deployment.

gxy-management has been at stage 2 since 2026-06-06 (currently `v1.2.2`) — expect the full worker + relay lines below on every run. The stage-1 column in the table is retained for a fresh galaxy bootstrap or DR rebuild.

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
  | grep -E 'postgres\.connected|gc\.wired|worker\.starting|outbox\.relay\.started'
```

| Stage                  | Expect present                                         | Expect absent                               |
| ---------------------- | ------------------------------------------------------ | ------------------------------------------- |
| 1 (HATCHET_ADDR unset) | `postgres.connected`, `gc.wired` | `worker.starting`, `outbox.relay.started` |
| 2 (HATCHET_ADDR set)   | all four lines                                         | —                                           |

### 3. Readiness probe (degraded semantics)

`/readyz` probes Valkey + R2 + Postgres. It is NOT exposed past the Gateway path that auth-gates `/api/*`, so probe it in-cluster.

The artemis image is distroless — no `sh`, no `wget`, no `curl` — so `kubectl exec ... wget` fails with `executable file not found in $PATH`. Reach the port through the API server's pod proxy instead:

```sh
POD=$(kubectl -n artemis get pods -l app.kubernetes.io/component=deploy-proxy \
        -o jsonpath='{.items[0].metadata.name}')
kubectl -n artemis get --raw "/api/v1/namespaces/artemis/pods/$POD:8080/proxy/readyz"
```

Expected:

- `{"ready":true}` — all three upstreams healthy.
- `{"ready":true,"degraded":true}` — Postgres **or**, from artemis 1.10.0, R2 unreachable while Valkey is up. HTTP stays `200` and the pod stays in rotation. Deploys that need the degraded upstream fail per request with their own `502`; serving is unaffected because Caddy reads R2 directly. Investigate the named upstream.
- HTTP `503` — Valkey down. That is the only hard fault left.

The R2 case changed in 1.10.0. Before it, an R2 fault answered `503` and took the pod out of the Service; because all three replicas share one bucket they failed together, so a slow-R2 window emptied the endpoint set entirely. That was Sentry `ARTEMIS-B`.

### 4. CronJobs present (durable-exec profile)

```sh
kubectl -n artemis get cronjob
```

Expect two chart-managed CronJobs:

| Name                | Schedule       | Gate                  |
| ------------------- | -------------- | --------------------- |
| `artemis-backup`    | `0 2 * * *`    | `backup.enabled`      |
| `artemis-oom-watch` | `*/15 * * * *` | `oomWatch.enabled`    |

Full backup verify + restore drill is runbook 08; this check only confirms the chart rendered them. A missing CronJob on a `backup.enabled` deployment means the overlay did not flip `backup.enabled: true`.

Any third CronJob in this namespace is drift. The hand-applied `pool-baseline` sampler was retired on 2026-08-24; see [`../architecture/rfc-pg-oom-alerting.md`](../architecture/rfc-pg-oom-alerting.md).

### 4a. OOM watcher is alive

```sh
kubectl -n artemis get cronjob artemis-oom-watch -o jsonpath='{.status.lastSuccessfulTime}{"\n"}'
kubectl -n artemis get cm artemis-oom-watch-state -o jsonpath='{.data.state\.json}'
```

`lastSuccessfulTime` must track `lastScheduleTime` within one period. The state ConfigMap must hold `restarts`, `last_log_marker` and `last_run`; empty `data` means the job has never completed a run.

The watcher exists because a cgroup OOM kill of a PostgreSQL *backend* leaves the postmaster alive, so `restartCount` never moves and Kubernetes emits no event. It posts a Sentry check-in on slug `artemis-oom-watch` every run. The first check-in of each run carries `monitor_config`, so Sentry creates the monitor object itself. Alert routing is still a console step. Confirm the monitor exists after the first run; without it a dead watcher is as silent as the fault it watches. Design: [`../architecture/rfc-pg-oom-alerting.md`](../architecture/rfc-pg-oom-alerting.md).

### 5. Site lifecycle — delete, hold, undelete (artemis 1.10.0+)

Nothing in `just verify-artemis` exercises this, and it is the release's headline behaviour change. Run it by hand once per release, on a throwaway slug.

**Only after the §6 rollout gate in runbook 02 passes** — every pod on one image digest. During a mixed-version roll the two versions disagree about what a delete means, and a 1.9.1 pod destroys a reservation a 1.10.0 pod created.

```sh
BASE=https://uploads.freecode.camp
SLUG=postdeploy-$(date +%Y%m%d-%H%M%S)
AUTH="Authorization: Bearer $GH_TOKEN"     # a staff-team GitHub token

# 1. register + publish
curl -fsS -X POST "$BASE/api/site/register" -H "$AUTH" \
  -H 'content-type: application/json' -d "{\"slug\":\"$SLUG\",\"teams\":[\"staff\"]}"
#    deploy through the CLI, which is what staff use:
#    universe static deploy --site "$SLUG" --promote
curl -fsS -o /dev/null -w '%{http_code}\n' "https://$SLUG.freecode.camp/"     # expect 200

# 2. delete — this is the behaviour under test
curl -fsS -X DELETE "$BASE/api/site/$SLUG" -H "$AUTH" -w ' <- %{http_code}\n'  # expect 204

# 3. the site must go dark. Allow the 15s serve cache.
sleep 20
curl -s -o /dev/null -w '%{http_code}\n' "https://$SLUG.freecode.camp/"        # expect 404

# 4. the name must be held, not free
curl -s -X POST "$BASE/api/site/register" -H "$AUTH" \
  -H 'content-type: application/json' -d "{\"slug\":\"$SLUG\",\"teams\":[\"staff\"]}" \
  -w ' <- %{http_code}\n'                                                      # expect 409 site_reserved

# 5. undelete returns the name. No CLI verb for this yet — curl only.
curl -fsS -X POST "$BASE/api/site/$SLUG/undelete" -H "$AUTH"                    # expect 200 + prevProduction/prevPreview
```

**Save the step-5 response.** `prevProduction` and `prevPreview` are the alias pointers captured at delete time, they are returned exactly once, and the server forgets them in the same statement that returns them.

Undelete restores the **name**, not the published site. Step 6 is a republish:

```sh
# universe static deploy --site "$SLUG" --promote
sleep 20
curl -fsS -o /dev/null -w '%{http_code}\n' "https://$SLUG.freecode.camp/"      # expect 200
```

Then confirm the audit trail recorded both halves:

```sh
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -tAc \
  "SELECT action, outcome FROM audit_log WHERE site LIKE '$SLUG%' ORDER BY occurred_at;"
```

Expect `site.register/success`, `site.delete/success`, `site.undelete/success` and the deploy rows. A `site.delete` with `outcome=failure` carries a `detail.stage` naming how far it got — `unpublish` or `reserve`.

Finally, delete the throwaway slug and let the nightly sweep reclaim it, or leave it held; either is fine, it is a scratch name.

**If step 3 still returns 200 after 20s**, the delete did not unpublish. Stop and check `SELECT slug, state, reserved_until FROM sites WHERE slug = '$SLUG';` before touching anything else — a deregistered-but-serving site is the exact defect this release exists to remove.

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
| Stage-2 release but no `worker.starting` log     | `env.HATCHET_ADDR` empty or Hatchet engine unreachable             | Check `HATCHET_ADDR` in `values.production.yaml`; verify engine Service gRPC port = `hatchet.grpcPort` |
| `gc.wired` absent on a `postgres.enabled` deploy | image pinned to pre-durable-exec `0.8.0`                           | RELEASE-CUT CHECKLIST item 2 in runbook 02 — bump image off `0.8.0`                                    |

## Related

- `internal/integration/doc.go` — full env-var contract
- `just integration-help` (run inside artemis repo) — same as above, terse
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
