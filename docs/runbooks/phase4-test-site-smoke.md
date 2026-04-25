# Phase 4 Test-Site Smoke Runbook

Exit criterion for [`docs/architecture/rfc-gxy-cassiopeia.md`](../architecture/rfc-gxy-cassiopeia.md) §6.6.

End-to-end validation that the R2 → Caddy(`r2_alias`) → Cloudflare chain
serves a test deploy on `test.freecode.camp` + `test.preview.freecode.camp`.
Uses `aws-cli` directly against R2 with admin S3 keys
sops-decrypted on demand from `infra-secrets/windmill/.env.enc`. No
persistent per-cluster R2 ops cred. No rclone.

Single bucket: `universe-static-apps-01`. Per-site isolation = prefix
scoping (`<site>/...`), NOT per-bucket. Smoke writes only under
`test.freecode.camp/` prefix; trap purges that prefix on every exit.

## Prerequisites

- gxy-cassiopeia cluster Ready (Phase 3 complete)
- Caddy Helm chart deployed with `r2_alias` + `caddy.fs.r2` modules
- R2 bucket `universe-static-apps-01` exists (verify: G-dispatch G1.0a
  acceptance probe lists it)
- Operator-added temp DNS in Cloudflare (recovery audit 2026-04-25
  confirmed both records resolve via CF anycast):
  - `test.freecode.camp` A → one gxy-cassiopeia node IP, **proxy ON**
  - `test.preview.freecode.camp` A → same IP, **proxy ON**
- Local tooling: `aws` (aws-cli v2), `curl`, `sops`, `age`. (rclone +
  direnv-loaded R2 keys NO LONGER required per D-amend 2026-04-25.)
- Per [DECISIONS.md D35](../sprints/2026-04-21/DECISIONS.md): preview
  hostname is **dot-scheme** (`<site>.preview.freecode.camp`), not
  dash-scheme.
- Operator-bootstrap gates G1.0a + G1.1 closed (otherwise admin S3
  keys + `R2_BUCKET` env not available — script fails at exit code 2).

## Required environment

Two source paths, depending on what operator pre-exports.

### Operator inputs (must be exported in calling shell)

| Var                      | Source                                              | Notes                                                           |
| ------------------------ | --------------------------------------------------- | --------------------------------------------------------------- |
| `R2_BUCKET`              | `k3s/gxy-cassiopeia/.envrc` (plain export per G1.1) | `= universe-static-apps-01`                                     |
| `GXY_CASSIOPEIA_NODE_IP` | inline export                                       | from `doctl compute droplet list --tag-name gxy-cassiopeia-k3s` |

### Admin source (sops-decrypted on demand by the script)

| Var                        | Source                            | Notes                                                          |
| -------------------------- | --------------------------------- | -------------------------------------------------------------- |
| `CF_ACCOUNT_ID`            | `infra-secrets/windmill/.env.enc` | seeded by G1.0a; live value `ad45585c4383c97ec7023d61b8aef8c8` |
| `R2_OPS_ACCESS_KEY_ID`     | `infra-secrets/windmill/.env.enc` | seeded by G1.0a; admin S3 key (full-bucket scope)              |
| `R2_OPS_SECRET_ACCESS_KEY` | `infra-secrets/windmill/.env.enc` | seeded by G1.0a                                                |

The script reads them via `sops -d --input-type dotenv` of
`$ADMIN_ENV_FILE` (default `$SECRETS_DIR/windmill/.env.enc`, falling back
to `$HOME/DEV/fCC/infra-secrets/windmill/.env.enc`). Operator can
pre-export any of the three to skip the decrypt (CI / non-interactive).

D33 ×2 invariant: admin cred home is `windmill/.env.enc`, NOT
`global/.env.enc` (that path direnv-loads into operator shell on every
`cd infra/`, leaks admin cred into every shell).

## Steps

1. `cd /Users/mrugesh/DEV/fCC/infra/k3s/gxy-cassiopeia` (loads direnv;
   `R2_BUCKET` exports here per G1.1).
2. `export GXY_CASSIOPEIA_NODE_IP=<ip>` —
   `doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format Name,PublicIPv4`.
3. `cd /Users/mrugesh/DEV/fCC/infra && just phase4-smoke`
   (or `bash scripts/phase4-test-site-smoke.sh` from repo root).
4. Expected: exit `0`, last line `OK: phase 4 smoke passed — phase4-<ts>`.
5. Operator removes the two temp DNS records via Cloudflare UI (only if
   they were added specifically for this run — recovery audit found
   them already in place, so probably skip this step).

## Acceptance

- Exit code `0`.
- R2 prefix `universe-static-apps-01/test.freecode.camp/` empty after run
  (both on success and on aborted runs — trap purges).
- `cf-cache-status` header is `DYNAMIC` on the smoke probe (Caddy is
  serving live R2 reads, not CF cache).

## What the script does

| Step | Action                                                                                    |
| ---- | ----------------------------------------------------------------------------------------- |
| 0    | Sops-decrypt admin S3 keys + `CF_ACCOUNT_ID` from `windmill/.env.enc` if not pre-exported |
| 1    | Generate test HTML payload with unique deploy ID `phase4-<ts>`                            |
| 2    | `aws s3 cp ... --recursive` payload to `s3://<bucket>/<site>/deploys/<id>/`               |
| 3    | Write `<bucket>/<site>/production` alias = deploy ID (stdin → object)                     |
| 4    | Curl origin via `Host: test.freecode.camp` — poll 30s × 2 green hits (Q6 SLO)             |
| 5    | Curl preview hostname — expect `404` (no preview alias yet)                               |
| 6    | Write `<bucket>/<site>/preview` alias, sleep 20s, verify 200                              |
| 7    | `aws s3 rm --recursive` the test prefix                                                   |
| 8    | `aws s3 ls --recursive` confirms zero objects remain                                      |

The trap re-runs `aws s3 rm --recursive` on any non-zero exit so partial
failures do not leak R2 state.

## Failure paths

| Symptom                                                 | Diagnose                                                                | Mitigate                                                                                                   |
| ------------------------------------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Exit 2 — admin env not found                            | `windmill/.env.enc` missing OR sops key not loaded                      | Verify path; load age key; rerun G1.0a if seed step skipped                                                |
| Exit 2 — `aws` / `sops` not on PATH                     | tooling missing                                                         | `brew install awscli sops` (macOS); equivalent on Linux                                                    |
| Step 2 `aws s3 cp` non-zero                             | bucket policy / S3 key scope wrong                                      | `aws s3 ls s3://universe-static-apps-01/ --endpoint-url=...`; rotate ops key per G1.0a                     |
| Step 4 origin never serves deploy ID                    | Caddy `r2_alias` not reading `production` blob OR alias cache TTL > 60s | `kubectl --context gxy-cassiopeia -n caddy logs -l app.kubernetes.io/name=caddy`; check `r2_alias` config  |
| Step 5 preview returns 200 (false positive)             | `preview` blob already exists in bucket from a prior aborted run        | Manually `aws s3 rm s3://universe-static-apps-01/test.freecode.camp/preview --endpoint-url=...` and re-run |
| Step 6 preview never serves deploy ID after alias write | Cache too aggressive at CF or Caddy                                     | Check `cf-cache-status`; raise sleep to 60s                                                                |
| Step 8 prefix not empty after `aws s3 rm`               | New objects landed during smoke run (concurrent test?)                  | Manual `aws s3 rm --recursive`; investigate whether another smoke ran concurrently                         |

## Rollback

- This script writes ONLY to the `test.freecode.camp` prefix and never
  touches production aliases. The trap purges the prefix on every exit
  path.
- If the script is killed with `SIGKILL` (trap does not run), manually:
  `aws s3 rm s3://universe-static-apps-01/test.freecode.camp/ --recursive --endpoint-url=https://<acct>.r2.cloudflarestorage.com`.
- Do NOT modify production DNS or Caddy config in response to a smoke
  failure; investigate first.

## When this gate passes

Phase 4 exit ✅. Wave A.1 closes for real (artifact + live run); A.2
already closed; A.3 unblocks once G1.0a + G1.0b also green. Update
[`docs/sprints/2026-04-21/PLAN.md`](../sprints/2026-04-21/PLAN.md)
G1.1.smoke matrix row to `[x] done` in the closing commit.
