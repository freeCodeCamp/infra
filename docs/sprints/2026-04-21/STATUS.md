# Sprint 2026-04-21 — STATUS

Updated: 2026-04-25 · Branch: `feat/k3s-universe` · Ahead of origin: 12

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

## Open

- **G1.0 — Operator bootstrap (manual ClickOps).** First gate before any
  Wave A worker fires. Mint CF Account-owned API Token (perm
  `Account → R2 Storage → Edit`), seed
  `infra-secrets/windmill/.env.enc` with `CF_R2_ADMIN_API_TOKEN` +
  `CF_ACCOUNT_ID`, smoke-curl, register Windmill Resource
  `u/admin/cf_r2_provisioner`. Steps in
  [`dispatches/T11-windmill-flow.md` §Operator bootstrap](dispatches/T11-windmill-flow.md).

After bootstrap:

- Wave A.1 (infra) → T15 smoke runbook + script.
- Wave A.2 (universe-cli) → T16 woodpecker client → T17 config schema.
- Wave A.3 (windmill) → T11 per-site R2 secret provisioning flow.

All 9 sub-tasks `pending` per dispatch-doc Status headers.

## Other state

- Cluster gxy-management: GREEN post-rename. Windmill restored from S3
  dump 2026-04-22. UI smoke 200.
- Cluster gxy-launchbase: Woodpecker live. `https://woodpecker.freecodecamp.net` 200, `x-woodpecker-version: 3.13.0`.
- Cluster gxy-cassiopeia: Caddy live with `r2_alias` + `caddy.fs.r2`. Caddy modules T01–T05 shipped 2026-04-18.
- Cluster gxy-static: Live, retiring at #26 cutover.
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. Origin certs `*.freecodecamp.net`, `*.freecode.camp`, `*.preview.freecode.camp` all ACM-issued + CF-activated.
- R2 bucket: `universe-static-apps-01`.
- Tools verified: sops, age, doctl, wmill (via `bunx` from windmill repo), direnv loaded in 3 repos.
- Worker driver scripts: `~/.claude/plugins/cache/superpowers-marketplace/claude-session-driver/1.0.1/scripts/`.

## Resume prompt — paste in fresh session

▎ Resume Sprint 2026-04-21 Wave A pre-launch per docs/sprints/2026-04-21/PLAN.md.
Tree on feat/k3s-universe, ahead of origin by 12, last shipped S11
(sprint doc consolidation: STATUS+PLAN+DECISIONS + GUIDELINES protocol).
Sprint goal: Universe static-apps MVP — staff push → site live on
<site>.freecode.camp via Woodpecker → R2 → Caddy(r2_alias) on
gxy-cassiopeia + preview siblings on <site>.preview.freecode.camp.
Final blocker: G1.0 operator bootstrap (manual ClickOps) NOT YET
EXECUTED. Steps in dispatches/T11-windmill-flow.md §Operator bootstrap
— mint CF Account-owned API Token, seed infra-secrets/windmill/.env.enc
with CF_R2_ADMIN_API_TOKEN + CF_ACCOUNT_ID, smoke-curl, register
Windmill Resource u/admin/cf_r2_provisioner. After bootstrap, dispatch
Wave A staggered: A.1 infra T15 → observe → A.2 universe-cli T16+T17
→ observe → A.3 windmill T11. Locked decisions in DECISIONS.md (Q1–Q8

- D33×2/D40 amendments). Per-task covenant: TDD discipline, one
  commit per task, type(scope): subject title only, worker flips
  dispatch Status pending → in-progress → done in same closure commit,
  no push / no PR / no publish — operator pushes at sprint close.
