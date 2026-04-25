# Phase 4 Test-Site Smoke Runbook

Exit criterion for [`docs/architecture/rfc-gxy-cassiopeia.md`](../architecture/rfc-gxy-cassiopeia.md) §6.6.

End-to-end validation that the R2 → Caddy(`r2_alias`) → Cloudflare chain
serves a test deploy on `test.freecode.camp` + `test.preview.freecode.camp`.
Uses `rclone` directly (this is infra's own gate — universe-cli depends
on Woodpecker which depends on this validation passing).

## Prerequisites

- gxy-cassiopeia cluster Ready (Phase 3 complete)
- Caddy Helm chart deployed with `r2_alias` + `caddy.fs.r2` modules
- R2 bucket `universe-static-apps-01` exists with rw access key (Task 12)
- Operator-added temp DNS in Cloudflare:
  - `test.freecode.camp` A → one gxy-cassiopeia node IP, **proxy ON**
  - `test.preview.freecode.camp` A → same IP, **proxy ON**
- Local tooling: `rclone`, `curl`, `direnv`, `sops`, `age`
- Per [DECISIONS.md D35](../sprints/2026-04-21/DECISIONS.md): preview hostname is **dot-scheme** (`<site>.preview.freecode.camp`), not dash-scheme

## Required environment

The script reads seven variables. All but `GXY_CASSIOPEIA_NODE_IP` are
loaded by direnv from `k3s/gxy-cassiopeia/.envrc`:

| Var                                           | Source                                                    |
| --------------------------------------------- | --------------------------------------------------------- |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | `infra-secrets/k3s/gxy-cassiopeia/.env.enc` (R2 rw)       |
| `R2_ENDPOINT`                                 | `infra-secrets/k3s/gxy-cassiopeia/.env.enc`               |
| `R2_BUCKET`                                   | `k3s/gxy-cassiopeia/.envrc` (= `universe-static-apps-01`) |
| `CF_API_TOKEN` / `CF_ZONE_ID`                 | `infra-secrets/global/.env.enc`                           |
| `GXY_CASSIOPEIA_NODE_IP`                      | exported by operator from `doctl compute droplet list`    |

## Steps

1. `cd /Users/mrugesh/DEV/fCC/infra/k3s/gxy-cassiopeia` (loads direnv).
2. `export GXY_CASSIOPEIA_NODE_IP=<ip>` —
   `doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format Name,PublicIPv4`.
3. `cd /Users/mrugesh/DEV/fCC/infra && just phase4-smoke`
   (or `bash scripts/phase4-test-site-smoke.sh` from repo root).
4. Expected: exit `0`, last line `OK: phase 4 smoke passed — phase4-<ts>`.
5. Operator removes the two temp DNS records via Cloudflare UI.

## Acceptance

- Exit code `0`.
- R2 prefix `universe-static-apps-01/test.freecode.camp/` empty after run
  (both on success and on aborted runs — trap purges).
- `cf-cache-status` header is `DYNAMIC` on the smoke probe (Caddy is
  serving live R2 reads, not CF cache).

## What the script does

| Step | Action                                                                        |
| ---- | ----------------------------------------------------------------------------- |
| 1    | Generate test HTML payload with unique deploy ID `phase4-<ts>`                |
| 2    | `rclone copy` payload to `<bucket>/<site>/deploys/<id>/`                      |
| 3    | Write `<bucket>/<site>/production` alias = deploy ID                          |
| 4    | Curl origin via `Host: test.freecode.camp` — poll 30s × 2 green hits (Q6 SLO) |
| 5    | Curl preview hostname — expect `404` (no preview alias yet)                   |
| 6    | Write `<bucket>/<site>/preview` alias, sleep 20s, verify 200                  |
| 7    | `rclone purge` the test prefix                                                |
| 8    | `rclone lsf` confirms zero objects remain                                     |

The trap re-runs `rclone purge` on any non-zero exit so partial failures
do not leak R2 state.

## Failure paths

| Symptom                                                 | Diagnose                                                                | Mitigate                                                                         |
| ------------------------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Step 2 `rclone copy` non-zero                           | Bucket policy / key scope wrong                                         | `rclone ls r2:universe-static-apps-01/`; rotate rw key per `r2-bucket-verify`    |
| Step 4 origin never serves deploy ID                    | Caddy `r2_alias` not reading `production` blob OR alias cache TTL > 60s | `kubectl -n caddy logs -l app.kubernetes.io/name=caddy`; check `r2_alias` config |
| Step 5 preview returns 200 (false positive)             | `preview` blob already exists in bucket from a prior aborted run        | Manually `rclone delete r2:.../test.freecode.camp/preview` and re-run            |
| Step 6 preview never serves deploy ID after alias write | Cache too aggressive at CF or Caddy                                     | Check `cf-cache-status`; raise sleep to 60s                                      |
| Step 8 prefix not empty after purge                     | New objects landed during smoke run (concurrent test?)                  | Manual `rclone purge`; investigate whether another smoke ran concurrently        |

## Rollback

- This script writes ONLY to the `test.freecode.camp` prefix and never
  touches production aliases. The trap purges the prefix on every exit
  path.
- If the script is killed with `SIGKILL` (trap does not run), manually:
  `rclone purge r2:universe-static-apps-01/test.freecode.camp/`.
- Do NOT modify production DNS or Caddy config in response to a smoke
  failure; investigate first.

## When this gate passes

Phase 4 exit ✅. Wave A.1 closes; A.2 (universe-cli T16/T17) unblocks.
Update [`docs/sprints/2026-04-21/PLAN.md`](../sprints/2026-04-21/PLAN.md)
T15 row to `[x] done` in the closing commit.
