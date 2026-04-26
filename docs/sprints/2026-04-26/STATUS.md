# Sprint 2026-04-26 — STATUS

Updated: 2026-04-26 (sprint open; pivot docs committed) · Branch: `feat/k3s-universe` · Ahead of origin: 5

**🆕 Sprint open at branch point** from prior sprint (`../archive/2026-04-21/`). Phase 1 sub-deliverables P1.2–P1.6 carry forward green; P1.1 + P1.7 + P1.8 (proxy svc + CLI v0.4 + schema v2) open here as T30–T34 + T22.

Canonical session-roll output. Overwritten each `roll the session`. Read this **before** PLAN.md or DECISIONS.md.

## Shipped (committed, not pushed)

- `8da379e` — `docs(sprint/2026-04-21): D016 proxy plane pivot` (sprint pivot docs landed in prior sprint dir; archived next commit)
- `<incoming>` — `docs(sprints): close 2026-04-21, open 2026-04-26 proxy pillar` (this consolidation commit)

Carried forward from `../archive/2026-04-21/` (still committed not pushed):

- All Phase 0 foundation commits (`e95f260` through `4c5e38b`)
- Wave A.1 — Caddy D35 + canonical builder + namespace flip (`d6360c7f` through `3a8d9933`)
- G1.1 + G1.1.smoke (`6ee679bf` + `phase4-20260426-080726`)
- T11 artifact at `windmill@010d577` + Bug C+D fixes (boneyard pending — incoming windmill commit)

## Open — incoming

Per dispatch order:

| Dispatch                                                                      | Repo                                                                  | State                       |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------- |
| **T30** — D016 ADR draft                                                      | `~/DEV/fCC-U/Universe` (cross-repo, broken ownership)                 | pending — next              |
| **T31** — uploads svc (Go, scaffold + endpoints + tests)                      | `~/DEV/fCC-U/uploads` (NEW greenfield repo)                           | pending                     |
| **T32** — universe-cli v0.4 rewrite (login/deploy/promote/rollback/ls/whoami) | `~/DEV/fCC-U/universe-cli` branch `feat/proxy-pivot` (NEW off `main`) | pending                     |
| **T33** — `platform.yaml` v2 schema + validator + doc                         | universe-cli `feat/proxy-pivot`                                       | pending (parallel with T32) |
| **T34** — Caddy reverse proxy + DNS prep + smoke retarget                     | infra `feat/k3s-universe`                                             | pending (after T31)         |
| **T22** — Cleanup cron flow (windmill, 7d retention)                          | `~/DEV/fCC-U/windmill` branch `main`                                  | pending (post-T31 live)     |

## Operator-owned actions (post session ship)

- Create CF DNS A record `uploads.freecode.camp` → uploads svc galaxy public IP (CF proxied; SSL Full Strict via existing `*.freecode.camp` cert)
- Create GitHub OAuth App in `freeCodeCamp` org settings:
  - Name: `Universe CLI`
  - Homepage: `https://uploads.freecode.camp`
  - Device flow: enabled
  - Capture `client_id` for CLI default + uploads svc `GH_CLIENT_ID` env
- Trigger first GHCR image build for uploads svc (CI workflow lands in T31; first build via `gh workflow run`)
- Helm install: `just helm-upgrade <galaxy> uploads` (T34)
- Smoke run: T34 retargeted script (E2E proxy upload)
- npm publish `@freecodecamp/universe-cli@0.4.0` after smoke green
- Push 4 repos: infra (`feat/k3s-universe`), Universe (`main`), windmill (`main`), universe-cli (`feat/proxy-pivot`), uploads (`main`, NEW remote)

## Boneyard (kept as archaeology, do not invoke)

- windmill: `f/static/provision_site_r2_credentials.{ts,test.ts,resource-type.yaml}` (boneyard headers incoming) + Resources `u/admin/cf_r2_provisioner` (proxy reuses) + `u/admin/woodpecker_admin` (retired)
- universe-cli: branch `feat/woodpecker-pivot` (4 commits ahead of `main`, never merged)
- T21 Woodpecker template — demoted to optional reference (archived at `../archive/2026-04-21/dispatches/archive/`)

## Other state

- Cluster gxy-management: GREEN. Will host uploads svc per T34 lean (Option A confirmed pending operator).
- Cluster gxy-launchbase: GREEN. Demoted from critical path post-pivot.
- Cluster gxy-cassiopeia: GREEN. Caddy 3/3 on `caddy-s3:sha-712c6e3@sha256:e024af67…` D35 dot-scheme. Adds `uploads.freecode.camp` upstream rule via T34.
- Cluster gxy-static: Live, retiring at #26 cutover (post-MVP).
- CF account: `ad45585c4383c97ec7023d61b8aef8c8`.
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. Origin certs `*.freecodecamp.net`, `*.freecode.camp`, `*.preview.freecode.camp` ACM-issued + CF-activated.
- R2 bucket: `universe-static-apps-01` (single bucket, prefix-scoped). Layout unchanged by pivot.
- Tools verified: sops, age, doctl, wmill, direnv, aws-cli v2, **Go 1.26.2 (`/opt/homebrew/bin/go`)** for T31.

## Resume prompt — paste in fresh session

▎ Resume Sprint 2026-04-26 (Universe static-apps proxy pillar). Branch
point opened from archived sprint 2026-04-21 (Wave A.1 ✅ Caddy + R2 +
smoke). Goal: staff `universe deploy` → site live, zero R2 tokens in
staff/CI hands, identity via GitHub team membership. Upload plane = Go
microservice at `uploads.freecode.camp`. Dispatch order: T30 (D016 ADR
in Universe repo, broken ownership) → T31 (Go svc in NEW
`~/DEV/fCC-U/uploads`) → T32 + T33 parallel (universe-cli v0.4 fresh
on `feat/proxy-pivot` off `main`) → T34 (Caddy + DNS + smoke retarget
on infra) → T22 (cleanup cron on windmill, post-T31 live). Tree: infra
on `feat/k3s-universe` ahead of origin by 5; will grow per dispatch.
Authority: broken ownership per operator 2026-04-26 evening; session
governs cross-repo; ADRs append-only. Per-task covenant: TDD,
title-only `type(scope): subject`, operator pushes at sprint close.
First move: open T30, write `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`
per dispatch brief.
