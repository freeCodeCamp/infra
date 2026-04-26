# Sprint 2026-04-26 — STATUS

Updated: 2026-04-27 (T33 closed; T31 in-flight) · Branch: `feat/k3s-universe` · Ahead of origin: 7+

**🆕 Multi-session true-parallel mode active.** This session
(`~/DEV/fCC/infra`) is **governor-only** — owns sprint-doc
consolidation. Per-T workers fire from separate Claude Code
sessions / terminals.

Canonical session-roll output. Overwritten each `roll the session`. Read this **before** PLAN.md or DECISIONS.md.

## Shipped (committed, not pushed)

infra (`feat/k3s-universe`):

- `8da379e5` — `docs(sprint/2026-04-21): D016 proxy plane pivot`
- `cdf30bbb` — `docs(sprints): close 2026-04-21, open 2026-04-26`
- `3f525004` — `docs(sprints): close T30 (D016 ADR)`
- `a80c1f64` — `docs(sprints): rename T31 svc to artemis`
- `<incoming>` — `docs(sprints): close T33 (platform.yaml v2)`

universe-cli (`feat/proxy-pivot` — NEW off `main`, not pushed):

- `8788648` — `feat(lib): add platform.yaml v2 schema + parser`
- `5d7b6ef` — `docs(platform-yaml): add v2 schema reference + migration`

Universe (`main`):

- `e2a9356` — `feat(decisions): D016 deploy proxy plane`
- `310c7e1` — `docs(decisions): D016 amend artemis + JWT scope`

Carried forward from `../archive/2026-04-21/` (still committed not pushed):

- All Phase 0 foundation commits (`e95f260` through `4c5e38b`)
- Wave A.1 — Caddy D35 + canonical builder + namespace flip (`d6360c7f` through `3a8d9933`)
- G1.1 + G1.1.smoke (`6ee679bf` + `phase4-20260426-080726`)
- T11 artifact at `windmill@010d577` + Bug C+D fixes (boneyard pending — incoming windmill commit)

## Open

| Dispatch                                                                      | Repo                                                                  | State                                                   |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------- |
| **T30** — D016 ADR draft + amend                                              | `~/DEV/fCC-U/Universe`                                                | **done** (`Universe@310c7e1`)                           |
| **T31** — artemis svc (Go, scaffold + endpoints + tests)                      | `~/DEV/fCC-U/artemis` (NEW greenfield repo)                           | pending — **fire-ready**                                |
| **T32** — universe-cli v0.4 rewrite (login/deploy/promote/rollback/ls/whoami) | `~/DEV/fCC-U/universe-cli` branch `feat/proxy-pivot` (NEW off `main`) | pending — partial-parallel with T31                     |
| **T33** — `platform.yaml` v2 schema + validator + doc                         | universe-cli `feat/proxy-pivot`                                       | **done** (`universe-cli@5d7b6ef`)                       |
| **T34** — Caddy reverse proxy + DNS prep + smoke retarget                     | infra `feat/k3s-universe`                                             | pending (blocks on T31 image tag)                       |
| **T22** — Cleanup cron flow (windmill, 7d retention)                          | `~/DEV/fCC-U/windmill` branch `main`                                  | pending — code-parallel with T31 (live verify post-T31) |

**Concurrency plan:**

- T33 ✅ closed. T31 in-flight. 2 lanes still fire-ready: T22 (windmill cleanup), T32 (universe-cli v0.4 — can layer on T33 schema now).
- T32 unblocked for scaffold + identity chain + schema consumption; HTTP client coupling waits on T31 contract.
- T34 last — needs artemis image published.

## Operator-owned actions (post session ship)

- Create CF DNS A record `uploads.freecode.camp` → gxy-management public IP (CF proxied; SSL Full Strict via existing `*.freecode.camp` cert)
- Create GitHub OAuth App in `freeCodeCamp` org settings:
  - Name: `Universe CLI`
  - Homepage: `https://uploads.freecode.camp`
  - Device flow: enabled
  - Capture `client_id` for CLI default + artemis `GH_CLIENT_ID` env
- Trigger first GHCR image build for artemis (CI workflow lands in T31; first build via `gh workflow run`)
- Helm install: `just helm-upgrade gxy-management artemis` (T34)
- Smoke run: T34 retargeted script (E2E proxy upload)
- npm publish `@freecodecamp/universe-cli@0.4.0` after smoke green
- Push 5 repos: infra (`feat/k3s-universe`), Universe (`main`), windmill (`main`), universe-cli (`feat/proxy-pivot`), artemis (`main`, NEW remote)

## Boneyard (kept as archaeology, do not invoke)

- windmill: `f/static/provision_site_r2_credentials.{ts,test.ts,resource-type.yaml}` (boneyard headers incoming) + Resources `u/admin/cf_r2_provisioner` (proxy reuses) + `u/admin/woodpecker_admin` (retired)
- universe-cli: branch `feat/woodpecker-pivot` (4 commits ahead of `main`, never merged)
- T21 Woodpecker template — demoted to optional reference (archived at `../archive/2026-04-21/dispatches/archive/`)

## Other state

- Cluster gxy-management: GREEN. Will host artemis per T34 lean (Option A confirmed pending operator).
- Cluster gxy-launchbase: GREEN. Demoted from critical path post-pivot.
- Cluster gxy-cassiopeia: GREEN. Caddy 3/3 on `caddy-s3:sha-712c6e3@sha256:e024af67…` D35 dot-scheme. Adds `uploads.freecode.camp` upstream rule (→ artemis svc) via T34.
- Cluster gxy-static: Live, retiring at #26 cutover (post-MVP).
- CF account: `ad45585c4383c97ec7023d61b8aef8c8`.
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. Origin certs `*.freecodecamp.net`, `*.freecode.camp`, `*.preview.freecode.camp` ACM-issued + CF-activated.
- R2 bucket: `universe-static-apps-01` (single bucket, prefix-scoped). Layout unchanged by pivot.
- Tools verified: sops, age, doctl, wmill, direnv, aws-cli v2, **Go 1.26.2 (`/opt/homebrew/bin/go`)** for T31.
- Artemis local repo: `~/DEV/fCC-U/artemis/` initialized as empty git repo (no files yet; first commit lands per T31).

## Multi-session resume prompts

Each worker session pastes its block in a fresh Claude Code terminal. Governor (this session) keeps the global resume at the bottom for continuity.

### T31 worker — artemis Go svc

▎ Resume Sprint 2026-04-26 / T31. Repo: `~/DEV/fCC-U/artemis` (greenfield;
empty git repo). Spec: `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`
(ADR-016 + 2 dated amendments — read in full incl. Amendments). Dispatch:
`~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T31-artemis-service.md`.
Goal: Go microservice scaffold + endpoints + tests per dispatch §Files,
§API surface, §Acceptance. Toolchain: Go 1.26.2 darwin/arm64
(`/opt/homebrew/bin/go`); chi router; AWS SDK Go v2 for R2; testify;
HS256 deploy-session JWT. Module: `github.com/freeCodeCamp/artemis`.
Hostname: `uploads.freecode.camp` (UNCHANGED — repo renamed but public
host stays). TDD: red→green→refactor. Closure: flip dispatch Status
header `pending → done` in same commit; one commit allowed since
greenfield init. Do NOT edit `STATUS.md` / `PLAN.md` / `HANDOFF.md` /
`DECISIONS.md` — governor session reconciles. First move:
`cd ~/DEV/fCC-U/artemis && go mod init github.com/freeCodeCamp/artemis`.

### T33 worker — universe-cli platform.yaml v2 schema

▎ Resume Sprint 2026-04-26 / T33. Repo: `~/DEV/fCC-U/universe-cli`
branch `feat/proxy-pivot` (NEW; cut fresh off `main` — first action).
Spec: ADR-016 + dispatch
`~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T33-platform-yaml-v2.md`.
Goal: `platform.yaml` v2 schema (strip credential paths; build + deploy
config only) + validator + doc. Parallel with T31 — no artemis API
contract dep. Toolchain: Bun + vitest + oxfmt + oxlint + tsup + husky.
TDD: red→green. One commit per sub-task close. Title-only conventional
commit. Do NOT edit sprint docs — governor reconciles. First move:
`cd ~/DEV/fCC-U/universe-cli && git checkout main && git checkout -b feat/proxy-pivot`.

### T22 worker — windmill cleanup cron

▎ Resume Sprint 2026-04-26 / T22. Repo: `~/DEV/fCC-U/windmill` branch
`main`. Spec: ADR-016 §R2 layout + dispatch
`~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T22-cleanup-cron.md`

- D39 (7d retention) + D41 (admin S3 keys). Goal: Windmill flow that
  sweeps unreferenced `<site>/deploys/<id>/` prefixes after 7d retention;
  aliased prefixes pinned. Code can land parallel with T31; live verify
  blocks on T31 deployed. Toolchain: Bun + wmill (`bunx wmill ...` from
  windmill repo cwd; never global). Test: vitest + mocked windmill-client
  locally before any preview/push. Closure: flip dispatch Status header
  in own commit. Do NOT edit sprint docs. First move: read dispatch +
  verify admin S3 Resource available.

### T32 worker — universe-cli v0.4 rewrite

▎ Resume Sprint 2026-04-26 / T32. Repo: `~/DEV/fCC-U/universe-cli`
branch `feat/proxy-pivot` (shared with T33 — coordinate file-by-file
or split sub-branches). Spec: ADR-016 §Authn/authz + dispatch
`~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T32-cli-v04-rewrite.md`.
Goal: CLI v0.4 — `login` (device flow), `deploy`, `promote`, `rollback`,
`ls`, `whoami`. Identity priority chain (Q10): env → GHA OIDC → WP OIDC
→ `gh auth token` → device-flow stored. HTTP client targets artemis
`/api/*`. Partial-parallel with T31 — scaffold + identity chain can
proceed; deploy/promote/rollback HTTP client waits on T31 contract.
Toolchain same as T33. Closure same protocol. First move: read T32
dispatch + ensure `feat/proxy-pivot` branch exists (T33 may have cut
it).

### T34 worker — Caddy + DNS + smoke retarget

▎ Resume Sprint 2026-04-26 / T34. **BLOCKED** until T31 publishes first
GHCR image. Repo: `~/DEV/fCC/infra` branch `feat/k3s-universe`. Spec:
dispatch `~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T34-caddy-dns-smoke.md`.
Note: this lane shares repo with governor session — coordinate via
governor before firing.

## Governor resume — paste in fresh session if this session lost

▎ Resume Sprint 2026-04-26 governor (Universe static-apps proxy pillar).
Branch point from `../archive/2026-04-21/` (Wave A.1 ✅). Goal: staff
`universe deploy` → live site, zero R2 tokens in staff/CI hands. Upload
plane = Go svc `artemis` at host `uploads.freecode.camp` (repo renamed
2026-04-26 evening; hostname unchanged). T30 closed (`Universe@310c7e1`).
T31 + T33 + T22 fire-ready (multi-session true-parallel). T32 partial-
parallel. T34 blocks on T31 image. **Governor scope:** sprint-doc
consolidation only — never edit T-worker repo files. Workers flip own
dispatch Status; governor reconciles PLAN matrix + HANDOFF in separate
infra commits at task close. Tree: infra `feat/k3s-universe` ahead origin
by 6+. Operator pushes at sprint close (5 repos). Authority: broken-
ownership single governing session per operator 2026-04-26 evening; ADRs
append-only via dated amendment block. Per-task covenant: TDD, title-only
`type(scope): subject` ≤50 char. Read order: this STATUS → PLAN → DECISIONS
→ HANDOFF.
