# Sprint 2026-04-21 — STATUS

Updated: 2026-04-26 (G1.0a + G1.0b closed) · Branch: `feat/k3s-universe` · Ahead of origin: 17 + recovery + G1.0a + G1.0b

**⚠ RECOVERY ACTIVE.** Pre-flight on T15 smoke surfaced 5 unmet
operator-env prereqs + 3 false-completion claims in G1.0. See:

- `reports/T15-smoke-preflight-2026-04-25.md`
- `reports/sprint-state-audit-2026-04-25.md`

Recovery picked: full Phase 1–5 with **smoke refactored to admin
Bearer + on-demand sops decrypt** (option 2; rclone + per-cluster R2
ops cred dropped). G1.0a + G1.0b closed 2026-04-26. Wave A.3 admin
deps now both green; T11 implementation pending. Wave B still blocked
on G1.1 ladder + T11.

Canonical session-roll output. Overwritten each `roll the session`. Read
this **before** PLAN.md or DECISIONS.md — those are stable references,
this is the live cursor.

## Shipped (committed, not pushed)

Phase 0 — Foundation:

- P0 — Docs foundation (GUIDELINES + field-notes + flight-manuals split) — `e95f260`
- P0 — Sprint seed (HANDOFF + README) — `6bfaf6d`
- P0 — TODO-park deferment list — `87fcdff`
- P0 — Cluster audit — `25d33df`
- P0 — Rename runbook + execution (gxy-mgmt → gxy-management) — `8914d69` + reprovision
- P0 — RFC secrets-layout + Phase 2b/3/5 + windmill backup hardening — `30f2205` `3465a9d` `779ab28` `cef8c8a` `827bc7e`
- P0 — Naming refactor (gxy-mgmt → gxy-management refs) — `9d49cda`
- P0 — Dogfood gaps (gxy-management flight-manual + field-notes) — `97b9c14`
- P0 — QA brainstorm Q1–Q8 locked — `39d49b5`
- P0 — MASTER dispatch plan + #24 dispatch block + RFC D33–D39 amendments — `6f3c84c` `3376e86` `4c5e38b`

Sprint scaffolding (since operator's last push):

- S1 — HANDOFF refresh + windmill-T11 dispatch — `ee7c08a`
- S2 — RFC D33 amend + D40 supersede D34 — `16df7fe`
- S3 — HANDOFF Wave A staggered plan — `e2bdc95`
- S4 — RFC D33 second amend (windmill/.env.enc, not global) — `f2c3767`
- S5 — T11 dispatch realigned to windmill/.env.enc — `f06ca87`
- S6 — RFC bucket name alignment (universe-static-apps-01) — `c33518d`
- S7 — T11 dispatch CF token form drift fix — `584ada3`
- S8 — r2-bucket-verify SC2015 fix — `a60fe10`
- S9 — gitignore /.cocoindex_code/ — `d43d1e4`
- S10 — Filesystem-driven dispatches (drop bead tracking) — `ae82d8e`
- S11 — Sprint doc consolidation: STATUS+PLAN+DECISIONS structure + GUIDELINES Sprint protocol — `3befa74`
- T15 — Phase 4 smoke runbook + script + `just phase4-smoke` / `phase4-smoke-test` recipes (Wave A.1 _artifact_ closed; live-run deferred) — `1e3b439`
- S12 — T15 closing commit ref backfill — `3f31a5c`
- T16-T20 dispatch closures (universe-cli closure docs in infra repo) — `96b5b52`
- S13 — sprint-doc roll: A.2 follow-up + slop strip — `73d4d19`
- G1.0a — `windmill/.env.enc` complete (4 vars) + Resource `u/admin/cf_r2_provisioner` + resource type `c_cf_r2_provisioner` live on platform workspace; infra-secrets commit `7d8edcb`; sprint-doc closure this commit
- G1.0b — Woodpecker admin PAT (`WOODPECKER_ADMIN_TOKEN`) added to `windmill/.env.enc` + `.env.sample` doc block; Resource `u/admin/woodpecker_admin` + resource type `c_woodpecker_admin` live on platform workspace; live probe HTTP 200 (login `freeCodeCamp-bot`, admin: true); infra-secrets commit `749ee09`; sprint-doc closure this commit

universe-cli `feat/woodpecker-pivot` (cross-repo, awaiting operator push):

- T16 + T17 — Woodpecker client + config schema strict-mode — `a7dd58e`
- T18 + T19 + T20 — deploy/promote/rollback Woodpecker rewrite + S3/rclone strip — `f6971cf`
- D35 fixture realignment — `89ab897`
- v0.4.0-beta.1 release prep + CHANGELOG — `03c5f19`
- A.2 follow-up: orphan errors + exit-codes strip (audit cleanup) — `4f54012`
- D37 domain pattern + `production_branch` covenant — `0113c9c`

## Open

- **G1.0 — Operator bootstrap.** ✅ **Both halves closed (2026-04-26):
  G1.0a CF + G1.0b Woodpecker.** Live state:
  - ✅ CF Account-owned API token: `CF_R2_ADMIN_API_TOKEN` in
    `infra-secrets/windmill/.env.enc`. Verified live (R2 admin perms,
    lists bucket `universe-static-apps-01`).
  - ✅ `CF_ACCOUNT_ID=ad45585c4383c97ec7023d61b8aef8c8` in same file.
  - ✅ Windmill Resource `u/admin/cf_r2_provisioner` live on platform
    workspace, shape `{cfApiToken, cfAccountId}`. Resource type
    `c_cf_r2_provisioner` created same run.
  - ✅ R2 ops S3 admin keys `R2_OPS_ACCESS_KEY_ID` +
    `R2_OPS_SECRET_ACCESS_KEY` (name `universe-static-apps-01-ops-rw`,
    R2 Object Read & Write, bucket-scoped, no TTL) in same file.
    Consumed on-demand by smoke + cleanup cron via sops decrypt.
  - ✅ Woodpecker admin PAT `WOODPECKER_ADMIN_TOKEN` in same file
    (admin scope, `freeCodeCamp-bot`, no TTL).
  - ✅ Windmill Resource `u/admin/woodpecker_admin` live on platform
    workspace, shape `{baseUrl, token}`. Resource type
    `c_woodpecker_admin` created same run. `baseUrl` =
    `https://woodpecker.freecodecamp.net/api`.

Wave A staggered — recovery state:

- Wave A.1 (infra) → **T15 artifact** closed. **Live run blocked** on
  G1.1 (cassiopeia env patch) — G1.0a now ✓. Smoke script refactored
  to admin-Bearer + on-demand sops (rclone + per-cluster cred dropped
  per D-amend 2026-04-25).
- Wave A.2 (universe-cli) → T16-T20 ✅ done. v0.4.0-beta.1 ready behind
  operator publish trigger.
- Wave A.3 (windmill) → **T11 admin deps unblocked** (G1.0a + G1.0b
  both ✓ — CF Resource `{cfApiToken, cfAccountId}` + Woodpecker
  Resource `{baseUrl, token}` live on platform workspace). T11 flow
  implementation still pending.

New recovery dispatches (Phase 3 of recovery):

- **G1.0a** — ✅ done 2026-04-26 (`windmill/.env.enc` 4-var complete + `u/admin/cf_r2_provisioner` + type `c_cf_r2_provisioner` live)
- **G1.0b** — ✅ done 2026-04-26 (`WOODPECKER_ADMIN_TOKEN` in `windmill/.env.enc` + Resource `u/admin/woodpecker_admin` + type `c_woodpecker_admin` live; admin scope verified)
- **G1.1** — pending — gxy-cassiopeia `.envrc` `R2_BUCKET` export + kubeconfig pull
- **G1.1.smoke** — pending — operator runs `just phase4-smoke` (depends G1.0a ✓ + G1.1)

Wave B (post-T11 observe-✓): T21 (infra `.woodpecker/deploy.yaml`), T22 (windmill cleanup cron). Both pending.

T15 artifact done. T16-T20 done. G1.0a + G1.0b ✅. G1.1/smoke + T11 + T21-T22 pending.

## Other state

- Cluster gxy-management: GREEN post-rename. Windmill restored from S3
  dump 2026-04-22. UI smoke 200.
- Cluster gxy-launchbase: Woodpecker live. `https://woodpecker.freecodecamp.net` 200, `x-woodpecker-version: 3.13.0`. API base `/api` (verified live 2026-04-25 — NOT `/api/v1`).
- Cluster gxy-cassiopeia: Caddy live (3 nodes, all `404 server=Caddy` for `Host: test.freecode.camp` pre-smoke). Modules T01–T05 shipped 2026-04-18. Node IPs: `165.227.149.249` `46.101.179.141` `188.166.165.62`.
- Cluster gxy-static: Live, retiring at #26 cutover.
- CF account: `ad45585c4383c97ec7023d61b8aef8c8` (`freeCodeCamp`). Verified via live API.
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. Origin certs `*.freecodecamp.net`, `*.freecode.camp`, `*.preview.freecode.camp` all ACM-issued + CF-activated.
- DNS: `test.freecode.camp` + `test.preview.freecode.camp` resolve via CF anycast (records already in place).
- R2 bucket: `universe-static-apps-01` (created 2026-04-20). **Single bucket — per-site = prefix scoping.** No per-site buckets.
- Tools verified: sops, age, doctl, wmill (via `bunx` from windmill repo), direnv loaded in 3 repos. **`aws` (aws-cli v2)** required for new smoke design — operator must install if absent.
- Worker driver scripts: `~/.claude/plugins/cache/superpowers-marketplace/claude-session-driver/1.0.1/scripts/`.

## Resume prompt — paste in fresh session

▎ Resume Sprint 2026-04-21 RECOVERY per
docs/sprints/2026-04-21/reports/sprint-state-audit-2026-04-25.md.
Tree on feat/k3s-universe, ahead of origin by 17 + recovery + G1.0a +
G1.0b. **G1.0a + G1.0b both closed 2026-04-26.**
`windmill/.env.enc` carries 5 vars (CF_R2_ADMIN_API_TOKEN,
CF_ACCOUNT_ID, R2_OPS_ACCESS_KEY_ID, R2_OPS_SECRET_ACCESS_KEY,
WOODPECKER_ADMIN_TOKEN). Platform workspace has resource types
c_cf_r2_provisioner + c_woodpecker_admin and resources
u/admin/cf_r2_provisioner ({cfApiToken, cfAccountId}) +
u/admin/woodpecker_admin ({baseUrl, token}) live. Wave A.1 T15
artifact closed; live run still blocked on G1.1. Wave A.2 T16-T20
done (universe-cli v0.4.0-beta.1 ready). Wave A.3 T11 admin deps both
✓; T11 implementation pending. Wave B (T21 + T22) blocked on T11.
Single R2 bucket `universe-static-apps-01`; per-site = prefix scoping
NOT per-bucket. CF account ad45585c4383c97ec7023d61b8aef8c8.
Woodpecker API base `/api` (NOT `/api/v1`). Pending dispatches:
G1.1-cassiopeia-env.md, G1.1-smoke-live-run.md. Per-task covenant:
TDD discipline, one commit per task, type(scope): subject title only,
worker flips dispatch Status pending → in-progress → done in same
closure commit, no push / no PR / no publish — operator pushes at
sprint close.
