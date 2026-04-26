# Sprint 2026-04-21 — STATUS

Updated: 2026-04-26 (Wave A.1 fully closed; G1.1 + T-r2alias-dot-scheme + G1.1.smoke green) · Branch: `feat/k3s-universe` · Ahead of origin: 25 (recovery + Wave A.1 + T-r2alias)

**✅ Wave A.1 GREEN.** RFC §6.6 Phase 4 exit gate cleared.
`phase4-20260426-080726` smoke run passed all 8 steps. Caddy on
cassiopeia rolled to `ghcr.io/freecodecamp/caddy-s3:sha-712c6e3@sha256:e024af67…`.

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
- G1.0a — `windmill/.env.enc` complete (4 vars) + Resource `u/admin/cf_r2_provisioner` + resource type `c_cf_r2_provisioner` live on platform workspace; infra-secrets commit `7d8edcb`; sprint-doc closure `22dd9e21`
- G1.0b — Woodpecker admin PAT (`WOODPECKER_ADMIN_TOKEN`) added to `windmill/.env.enc` + `.env.sample` doc block; Resource `u/admin/woodpecker_admin` + resource type `c_woodpecker_admin` live on platform workspace; live probe HTTP 200; infra-secrets commit `749ee09`; sprint-doc closure `61cc885a`
- T11 — windmill flow `f/static/provision_site_r2_credentials` shipped (windmill@`010d577`) — sprint-doc closure `518c46e`
- G1.1 — `R2_BUCKET=universe-static-apps-01` exported in `k3s/gxy-cassiopeia/.envrc`; cassiopeia kubeconfig sanity-checked (3 nodes Ready); dispatch flipped to done; PLAN matrix `[x] done` — `6ee679bf`
- **T-r2alias-dot-scheme — D35 module fix + GH Actions canonical builder + namespace flip + RFC scrub:**
  - `feat(caddy-s3): r2_alias dot-scheme preview routing per D35` — `d6360c7f` (host.go + tests; option rename `preview_suffix` → `preview_subdomain`; 56/56 module tests green)
  - `chore(caddy): preview_subdomain in chart configmap` — `9c96a9c8`
  - `ci(caddy-s3): GH Actions canonical builder; Woodpecker secondary` — `842a7fd9`
  - `docs(rfc): strip --preview suffix refs per D35` — `eb5ddca1`
  - `chore(caddy-s3): retire freecodecamp-universe namespace; use freecodecamp` — `712c6e34` (cross-org push 403'd on package policy; flipped to same-org)
  - `ci(caddy-s3): workflow_dispatch only; trim verbose comments` — `51de48c1`
  - `chore(caddy): roll cassiopeia to caddy-s3 sha-712c6e3 (D35 dot-scheme)` — `3a8d9933`
- G1.1.smoke — `phase4-20260426-080726` smoke run green; trap purged R2; post-verify empty; RFC §6.6 Phase 4 exit ✅
- Universe `main` (cross-repo): field-note infra entry "build-residency for platform pillars" — `799022b` + `e48c3d7` (caddy-s3 namespace retirement note)

## Open

- **T11 observe-✓.** Operator owes live preview + `wmill sync push` of
  `f/static/provision_site_r2_credentials` against the platform
  workspace. Until then, T11 is "artifact done" not "live verified."
- **Wave B fanout** (post-T11 observe-✓):
  - T21 — `.woodpecker/deploy.yaml` template (infra; consumes T11 secret format)
  - T22 — Cleanup cron flow (windmill; 7d retention; pin aliases)
- **T-build-residency** (new follow-up dispatch, not yet filed) —
  audit all `.woodpecker/*.yaml` pipelines, classify each as platform
  pillar vs tenant, migrate pillar pipelines to GitHub Actions,
  retire secondary Woodpecker pipelines, propose ADR via Universe
  team.
- **Operator deferred cleanup** (post Wave A.1):
  - `gh secret delete GHCR_PUSH_USER -R freeCodeCamp/infra`
  - `gh secret delete GHCR_PUSH_TOKEN -R freeCodeCamp/infra`
  - Revoke PAT `infra-ghcr-push-caddy-s3` at <https://github.com/settings/tokens>
  - Delete stale package `freecodecamp-universe/caddy-s3` after a few days of stable cassiopeia operation

Wave A.2 (universe-cli T16–T20) ✅ done — v0.4.0-beta.1 ready behind operator publish.
Wave A.3 (windmill T11) ✅ artifact done — awaiting operator live preview.

## Other state

- Cluster gxy-management: GREEN. Windmill restored from S3 dump 2026-04-22; UI smoke 200.
- Cluster gxy-launchbase: Woodpecker live. `https://woodpecker.freecodecamp.net` HTTP 200, `x-woodpecker-version: 3.13.0`. API base `/api`.
- Cluster gxy-cassiopeia: GREEN. Caddy 3/3 pods Running on `ghcr.io/freecodecamp/caddy-s3:sha-712c6e3@sha256:e024af67…` (D35 dot-scheme). ConfigMap carries `preview_subdomain "preview"`. Smoke `phase4-20260426-080726` green. Node IPs: `165.227.149.249` `46.101.179.141` `188.166.165.62`.
- Cluster gxy-static: Live, retiring at #26 cutover.
- CF account: `ad45585c4383c97ec7023d61b8aef8c8` (`freeCodeCamp`).
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. Origin certs `*.freecodecamp.net`, `*.freecode.camp`, `*.preview.freecode.camp` ACM-issued + CF-activated.
- DNS: `test.freecode.camp` + `test.preview.freecode.camp` resolve via CF anycast.
- R2 bucket: `universe-static-apps-01` (single bucket — per-site = prefix scoping).
- GHCR canonical builder: GitHub Actions workflow `.github/workflows/docker--caddy-s3.yml` (manual `workflow_dispatch`). Woodpecker pipeline secondary, manual-only.
- Tools verified: sops, age, doctl, wmill, direnv, aws-cli v2.

## Resume prompt — paste in fresh session

▎ Resume Sprint 2026-04-21. Wave A.1 fully closed 2026-04-26 (G1.1 +
T-r2alias-dot-scheme + G1.1.smoke all green;
`phase4-20260426-080726`). Tree on `feat/k3s-universe`, ahead of
origin by 25. Caddy-s3 image
`ghcr.io/freecodecamp/caddy-s3:sha-712c6e3@sha256:e024af67…`
deployed to cassiopeia via D35 dot-scheme module rewrite. Canonical
builder = GitHub Actions (`workflow_dispatch` only; same-org push to
`freecodecamp` org). Open: T11 observe-✓ owed by operator (live
preview + `wmill sync push`); Wave B (T21 + T22) blocks on T11; new
follow-up T-build-residency to be filed (audit Woodpecker pillar
pipelines, ADR proposal). Operator cleanup pending: delete
`GHCR_PUSH_USER` + `GHCR_PUSH_TOKEN` secrets, revoke
`infra-ghcr-push-caddy-s3` PAT, delete stale
`freecodecamp-universe/caddy-s3` package. Per-task covenant: TDD,
title-only `type(scope): subject`, no push by session, operator
pushes at sprint close.
