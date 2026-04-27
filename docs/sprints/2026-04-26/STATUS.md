# Sprint 2026-04-26 — STATUS

Updated: 2026-04-27 (G2 unblocked — T32 addendum landed, default GH OAuth client_id baked into universe-cli; G1 still GREEN) · Branch: `feat/k3s-universe` · Ahead of origin: 35+

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
- `7465ce41` — `docs(sprint): close T31 — artemis@861e4c4`
- `a6e8abcc` — `docs(sprints): close T33 (platform.yaml v2)`
- `8bb867c4` — `docs(sprints): reconcile T31 PLAN+STATUS+HANDOFF`
- `a967cf24` — `docs(sprints): close T22 cleanup cron (windmill)`
- `22140aed` — `docs(sprints): pivot CLI surface to static ns`
- `a7bfbc4c` — `docs(sprints): T34 sops dotenv decrypt incant`
- `b1f1f3e4` — `docs(sprints): close T32 — universe-cli@24d6fa1`
- `e99da31b` — `docs(todo-park): R2 lifecycle GC for artemis orphans`
- `4ff9e2cc` — `docs(sprints): reconcile T32 PLAN+STATUS+HANDOFF`
- `964c8d22` — `docs(todo-park): oxfmt wiring on universe-cli`
- `0bbaca02` — `docs(sprints): T32 addendum bake gh client_id`
- `5e42cc80` — `docs(sprints): T34 sites.yaml + audit trail`
- `c9dd8817` — `docs(sprints): T34 sites.yaml ADR realign`
- `fdf74dc6` — `docs(todo-park): artemis sites slim + embedded KV`
- `<incoming>` — `docs(sprints): seed artemis sites.yaml — T34 precondition`
- `<incoming>` — `docs(sprints): close T32 addendum — cli@0a3f1ce`

universe-cli (`feat/proxy-pivot` — NEW off `main`, not pushed):

- `8788648` — `feat(lib): add platform.yaml v2 schema + parser`
- `5d7b6ef` — `docs(platform-yaml): add v2 schema reference + migration`
- `24d6fa1` — T32 closure (CLI v0.4 rewrite — login/static deploy/promote/rollback/ls/whoami)
- `0a3f1ce` — `feat(login): bake default GH OAuth client_id` _(T32 addendum — G2 gate cleared; package bumped to `0.4.0-alpha.2`)_

artemis (`main` — greenfield, NEW remote, not pushed):

- `861e4c4` — `feat: initial artemis service scaffold`
- `7d6eed3` — `ci: split into reusable test + manual docker (PH1-B25)` _(landed post-T31; matches GHCR :sha-7d6eed3c... image)_
- `49d2f32` — `feat(config): seed sites.yaml + un-gitignore` _(T34 precondition #5)_

windmill (`main`, not pushed):

- `016a868` — `feat(static): add cleanup cron for R2 deploys (T22)`
- `f8e99b9` — `chore(static): boneyard T11 files + fmt pass`

Universe (`main`):

- `e2a9356` — `feat(decisions): D016 deploy proxy plane`
- `310c7e1` — `docs(decisions): D016 amend artemis + JWT scope`
- `df255b9` — `docs(decisions): D016 amend CLI namespace static`
- `c5a1144` — `docs(spike-plan): add artemis on gxy-management`

Carried forward from `../archive/2026-04-21/` (still committed not pushed):

- All Phase 0 foundation commits (`e95f260` through `4c5e38b`)
- Wave A.1 — Caddy D35 + canonical builder + namespace flip (`d6360c7f` through `3a8d9933`)
- G1.1 + G1.1.smoke (`6ee679bf` + `phase4-20260426-080726`)
- T11 artifact at `windmill@010d577` + Bug C+D fixes (boneyard pending — incoming windmill commit)

## Open

| Dispatch                                                                             | Repo                                                                  | State                                                                                                                 |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **T30** — D016 ADR draft + amend                                                     | `~/DEV/fCC-U/Universe`                                                | **done** (`Universe@310c7e1`)                                                                                         |
| **T31** — artemis svc (Go, scaffold + endpoints + tests)                             | `~/DEV/fCC/artemis` (NEW greenfield repo)                             | **done** (`artemis@861e4c4`)                                                                                          |
| **T32** — universe-cli v0.4 rewrite (login/static deploy/promote/rollback/ls/whoami) | `~/DEV/fCC-U/universe-cli` branch `feat/proxy-pivot` (NEW off `main`) | **done** (`universe-cli@24d6fa1` + addendum `0a3f1ce` — default GH OAuth client_id baked, G2 cleared; oxfmt deferred) |
| **T33** — `platform.yaml` v2 schema + validator + doc                                | universe-cli `feat/proxy-pivot`                                       | **done** (`universe-cli@5d7b6ef`)                                                                                     |
| **T34** — Artemis chart + DNS + phase5 smoke (Path X reframe)                        | infra `feat/k3s-universe`                                             | **done** (`infra@0b8d6238`) — operator-gated: helm-deploy + phase5-smoke (live verify)                                |
| **T22** — Cleanup cron flow (windmill, 7d retention)                                 | `~/DEV/fCC-U/windmill` branch `main`                                  | **done** (`windmill@016a868`) — operator gates pending                                                                |

**Concurrency plan:**

- T30 ✅ + T31 ✅ + T32 ✅ (+ addendum ✅) + T33 ✅ + T22 ✅ + T34 ✅ closed. CLI namespace pivot ✅ landed pre-T32 (`universe static <verb>`).
- **G1 GREEN** (T34 live verify GREEN 2026-04-27 — see HANDOFF).
- **G2 unblocked** — npm publish `@freecodecamp/universe-cli@0.4.0-alpha.2` clear to ship now that default GH OAuth client_id is baked in source.
- T22 live verify (R2 admin Resource + Windmill schedule flip) still operator-gated; gate is windmill-side only, does not block G1/G2 ticks.

## Operator-owned actions (post session ship)

- ~~CF DNS A record `uploads.freecode.camp`~~ — DONE 2026-04-27 (T34 precondition).
- ~~GitHub OAuth App `Universe CLI` (`Iv23liIuGmZRyPd5wUeN`)~~ — DONE 2026-04-27 (T34 precondition).
- ~~CF zone SSL verify (Flexible)~~ — DONE 2026-04-27 (artemis chart drops origin TLS per cassiopeia parity).
- ~~First GHCR image build for artemis~~ — DONE 2026-04-27 (`ghcr.io/freecodecamp/artemis:sha-7d6eed3c…`).
- ~~Helm install + phase5 smoke~~ — DONE 2026-04-27 (G1 GREEN; see HANDOFF).
- T22 live verify — flip Windmill cleanup cron schedule active + verify admin S3 Resource resolves (R2 sweep dry-run first).
- npm publish `@freecodecamp/universe-cli@0.4.0-alpha.2` (G2 — addendum landed; `pnpm publish` from `feat/proxy-pivot` head, OIDC Trusted Publisher).
- Push 5 repos: infra (`feat/k3s-universe`), Universe (`main`), windmill (`main`), universe-cli (`feat/proxy-pivot`), artemis (`main`, NEW remote).

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
- Artemis local repo: `~/DEV/fCC/artemis/` initialized as empty git repo (no files yet; first commit lands per T31).

## Multi-session resume prompts

Each worker session pastes its block in a fresh Claude Code terminal. Governor (this session) keeps the global resume at the bottom for continuity.

### T31 worker — artemis Go svc

▎ Resume Sprint 2026-04-26 / T31. Repo: `~/DEV/fCC/artemis` (greenfield;
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
`cd ~/DEV/fCC/artemis && go mod init github.com/freeCodeCamp/artemis`.

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

### T32 addendum worker — bake `UNIVERSE_GH_CLIENT_ID` default

▎ Resume Sprint 2026-04-26 / T32 addendum. Repo:
`~/DEV/fCC-U/universe-cli` branch `feat/proxy-pivot` (T32 main work
already closed at `24d6fa1`). Dispatch:
`~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T32-cli-v04-rewrite.md`
§Addendum 2026-04-27. Goal: bake default GH OAuth App client_id in
source so npm-published binary works without env var; env override
preserved for fork tenants. Single commit, ~30min. Files:
`src/lib/constants.ts` (NEW or fold), `src/commands/login.ts` (env
?? DEFAULT), `tests/commands/login.test.ts` (env-unset case),
`README.md` (drop "ask platform team" wording), `CHANGELOG.md`
(`0.4.0-alpha.2` entry). Constant value `Iv23liIuGmZRyPd5wUeN`
(verified 2026-04-27 against artemis envelope). Public-grade — fine
to commit. Closure: single commit; T32 dispatch already `done` (no
flip); governor reconciles HANDOFF correction-style entry post-merge.
Blocks G2 (npm publish), not G1 — fire after T34 smoke green or in
parallel.

### T34 worker — Caddy + DNS + smoke retarget

▎ Resume Sprint 2026-04-26 / T34. **UNBLOCKED 2026-04-27.** All 5
operator preconditions GREEN: CF DNS A `uploads.freecode.camp` (CF
proxied), GH OAuth App `Universe CLI` (`Iv23liIuGmZRyPd5wUeN`), artemis
GHCR image (`ghcr.io/freecodecamp/artemis:sha-7d6eed3c58fd25407f52a905bad458c4a70ed277`

- `:main` + `:latest`), sops envelope sealed
  (`infra-secrets/management/artemis.env.enc`, 15/15 vars), sites.yaml
  seed (`artemis@49d2f32` — `config/sites.yaml`). Repo:
  `~/DEV/fCC/infra` branch `feat/k3s-universe`. Spec: dispatch
  `~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T34-caddy-dns-smoke.md`
  (read in full incl. amended §step 5 — sites.yaml source-of-truth is
  artemis repo `config/sites.yaml`, NOT infra repo; chart loads via
  Helm `--set-file` from operator's local artemis checkout). Goal:
  Helm chart for artemis svc (`k3s/gxy-management/apps/artemis/`),
  Caddy reverse-proxy upstream rule on
  `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml`
  (`uploads.freecode.camp` → Tailscale upstream
  `artemis.management.tailscale.fcc:8080`), justfile recipe
  (`just helm-upgrade gxy-management artemis` wrapping `--set-file
sites=$HOME/DEV/fCC/artemis/config/sites.yaml`), runbook
  `docs/runbooks/deploy-artemis-service.md` (NEW), flight-manual
  section `docs/flight-manuals/gxy-management.md` artemis subsection,
  smoke script `scripts/phase5-proxy-smoke.sh` (NEW — replaces
  `phase4-test-site-smoke.sh` direct-S3; new flow: init → upload →
  finalize → preview curl → promote → prod curl per dispatch §Smoke
  retarget). Image pin: prefer immutable SHA tag over `:main` for
  production values. **Mode B coordination:** governor session
  (`~/DEV/fCC/infra` cwd) is **idle** until T34 closes — same repo /
  same tree, no parallel governor edits. Worker has free hand on all
  sprint-doc-cluster-EXCLUDED files (everything in `k3s/`, `ansible/`,
  `justfile`, `scripts/`, `docs/runbooks/`, `docs/flight-manuals/`,
  `docs/architecture/`). Worker MUST NOT edit `STATUS.md` / `PLAN.md` /
  `HANDOFF.md` / `DECISIONS.md` / `audit/*.md` / `dispatches/T*.md`
  EXCEPT for own dispatch Status header flip (`pending → in-progress`
  on start; `→ done` on closure) — governor reconciles
  PLAN matrix + STATUS + HANDOFF in separate infra commit
  post-closure. TDD per dispatch §Acceptance criteria. One commit per
  sub-task close, title-only `cmd-git-rules`. First move: read T34
  dispatch in full + verify image still pinnable
  (`gh api /orgs/freeCodeCamp/packages/container/artemis/versions
--jq '.[] | {tags: .metadata.container.tags}'`).

## Governor resume — paste in fresh session if this session lost

▎ Resume Sprint 2026-04-26 governor (Universe static-apps proxy pillar).
Branch point from `../archive/2026-04-21/` (Wave A.1 ✅). Goal: staff
`universe static deploy` → live site, zero R2 tokens in staff/CI hands. Upload
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
