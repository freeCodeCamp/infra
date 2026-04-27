# Artemis Post-Deploy Check

End-to-end verification that a deployed artemis instance is healthy and
serves the full deploy lifecycle. Run after every artemis chart upgrade
or any change that touches the deploy/serve chain (artemis chart,
caddy-s3 chart, R2 bucket policy, sites.yaml).

Source of truth for the test bodies lives in the artemis repo at
`internal/integration/` (build-tagged Go suite). This runbook covers
how to wire and trigger the suite from the infra repo.

## When to run

- Immediately after `just deploy gxy-management artemis`
- After caddy-s3 chart bump on `gxy-cassiopeia`
- After any `sites.yaml` PR merge (validates the new site authorizes correctly)
- After secrets rotation (R2 keys, JWT signing key, GH OAuth)
- Before promoting a real customer site to production (smoke first)

## Prerequisites

| Requirement                   | Verify                                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| Local artemis repo checkout   | `ls $HOME/DEV/fCC/artemis/Makefile`                                                              |
| Go toolchain (≥ 1.24)         | `go version`                                                                                     |
| GitHub CLI authenticated      | `gh auth status` (any GH account; team must match site)                                          |
| Caller's team in `sites.yaml` | `gh api /user/teams --jq '.[].slug'` — at least one entry must appear under `sites.<SITE>.teams` |
| Artemis reachable             | `curl -fsS https://uploads.freecode.camp/healthz`                                                |
| Test site authorized          | `config/sites.yaml` in `freeCodeCamp/artemis` lists `test:` with at least one team you belong to |

## Run

```sh
cd /Users/mrugesh/DEV/fCC/infra
just artemis-postdeploy-check
```

That's it. The recipe:

1. Curls `${ARTEMIS_URL}/healthz` (default `https://uploads.freecode.camp`)
2. Resolves a GH token via `${GH_TOKEN}` or `gh auth token`
3. Shells into `${ARTEMIS_REPO}` (default `$HOME/DEV/fCC/artemis`)
4. Runs `make integration` — the Go E2E suite

Expected wall time: 2–5 minutes (production-alias SLO is 2 min per D38).

## Override env

| Variable       | Default                         | Purpose                          |
| -------------- | ------------------------------- | -------------------------------- |
| `ARTEMIS_URL`  | `https://uploads.freecode.camp` | Live deployment to probe         |
| `ARTEMIS_REPO` | `$HOME/DEV/fCC/artemis`         | Local artemis checkout           |
| `GH_TOKEN`     | `gh auth token`                 | GH bearer authorized for `SITE`  |
| `SITE`         | `test`                          | Site key in `sites.yaml`         |
| `ROOT_DOMAIN`  | `freecode.camp`                 | Public root domain               |
| `PROD_SLO`     | `2m`                            | Production-alias serve SLO (D38) |
| `PREVIEW_SLO`  | `90s`                           | Preview-alias serve SLO          |

Example targeting a staging artemis:

```sh
ARTEMIS_URL=https://uploads.staging.freecode.camp \
  SITE=test ROOT_DOMAIN=staging.freecode.camp \
  just artemis-postdeploy-check
```

## What the suite covers

Tests defined in `artemis/internal/integration/proxy_e2e_test.go`:

| Test                 | Asserts                                                                                                          |
| -------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `TestHealthZ`        | `GET /healthz` → 200 `{ok:true}`                                                                                 |
| `TestWhoAmI`         | `GET /api/whoami` returns login + `authorizedSites` containing `SITE`                                            |
| `TestAuthRejections` | Bad token → 401/403, missing token → 401, unknown site → 403, no `site` → 400                                    |
| `TestDeployFlow`     | Full happy path: init → upload → finalize(preview) → curl preview → promote → curl prod (D38 SLO) → list deploys |
| `TestRollback`       | Production alias rewires to a prior deploy id; restore-to-head best-effort                                       |

## Pass criteria

- `make integration` exits 0
- Final line: `OK — full deploy flow green for site=test deployId=<id>`

## Failure paths

| Symptom                                | Diagnose                                                          | Mitigate                                                                                             |
| -------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `healthz unreachable`                  | DNS / CF / artemis pod down                                       | `kubectl -n artemis get pods,svc,httproute`; CF dashboard A-record; `kubectl logs`                   |
| `whoami: site not in authorized list`  | Caller's GH teams have no overlap with `sites.test.teams`         | `gh api /user/teams --jq '.[].slug'`; cross-check `freeCodeCamp/artemis` `config/sites.yaml`         |
| `bad token: status=200`                | Auth middleware not enforcing                                     | Inspect `RequireGitHubBearer` chain; check chart `httproute.yaml` is in front of pod                 |
| `init: 422 verify_failed`              | sites.yaml on cluster differs from repo (ConfigMap drift)         | `kubectl -n artemis get cm artemis-sites -o yaml`; `just deploy gxy-management artemis` to reconcile |
| `finalize preview: 502 r2_put_failed`  | R2 endpoint or admin key wrong; bucket policy lacks PutObject     | Decrypt `infra-secrets/management/artemis.env.enc`; re-validate against R2 dashboard                 |
| `preview: marker not seen` (timeout)   | Caddy `r2_alias` cache TTL too long, or alias key format mismatch | `kubectl -n caddy logs -l app=caddy --tail=200`; check `ALIAS_PREVIEW_KEY_FORMAT`                    |
| `production: marker not seen` in 2 min | CF edge cache holding old content; alias path mismatch            | Check `cf-cache-status` header; CF cache purge tool                                                  |
| `rollback: deployId mismatch`          | Target deploy prefix swept by cleanup cron (T22, 7-day retention) | Pick a more recent `deployId` from `/deploys`; or rerun TestDeployFlow twice                         |

## Related

- `internal/integration/doc.go` — full env-var contract
- `make integration-help` (run inside artemis repo) — same as above, terse
- ADR-016 (`Universe/decisions/016-deploy-proxy.md`) — design rationale, SLOs (Q6, D38)
- `config/sites.yaml` (`freeCodeCamp/artemis`) — authoritative team→site map

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
