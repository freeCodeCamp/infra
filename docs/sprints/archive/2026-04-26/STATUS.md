# Sprint 2026-04-26 — STATUS

Updated: 2026-04-27 (post-G2-GA roll) · 8 sub-tasks **done** · G1
GREEN · **G2 GREEN** (`@freecodecamp/universe-cli@0.4.0` on npm) ·
sprint gates **all closed**. Residual = operational ClickOps
(schedule `enabled`/`dry_run` flip), `WMILL_TOKEN` rotate, ADR-016
amendment (Universe team).

Canonical session-roll output. Overwritten each `roll the sprint`.
Read this **before** PLAN.md or DECISIONS.md.

## Sync state (5 repos)

| Repo                       | Branch              | HEAD       | `@{u}...HEAD` (behind/ahead) |
| -------------------------- | ------------------- | ---------- | ---------------------------- |
| `~/DEV/fCC/infra`          | `feat/k3s-universe` | `29c70770` | 0/4 — **needs push**         |
| `~/DEV/fCC-U/windmill`     | `main`              | `48536f3`  | 0/2 — **needs push**         |
| `~/DEV/fCC-U/universe-cli` | `main`              | `45faeca`  | 0/0 ✓                        |
| `~/DEV/fCC/artemis`        | `main`              | `3c3ed0c`  | 0/0 ✓                        |
| `~/DEV/fCC-U/Universe`     | `main`              | `c2f274d`  | 0/0 ✓                        |

## Shipped

### infra `feat/k3s-universe` — `29c70770` HEAD

Sprint commits since `cdf30bb` (sprint open):

- `cdf30bbb` — `docs(sprints): close 2026-04-21, open 2026-04-26`
- `3f525004` — `docs(sprints): close T30 (D016 ADR)`
- `a80c1f64` — `docs(sprints): rename T31 svc to artemis`
- `7465ce41` — `docs(sprint): close T31 — artemis@861e4c4`
- `a6e8abcc` — `docs(sprints): close T33 (platform.yaml v2)`
- `8bb867c4` — `docs(sprints): reconcile T31 PLAN+STATUS+HANDOFF`
- `a967cf24` — `docs(sprints): close T22 cleanup cron (windmill)`
- `22140aed` — `docs(sprints): pivot CLI surface to static ns`
- `96a941f9` — `docs(sprints): reconcile T22 + ns pivot history`
- `b8c59b0b` — `docs(TODO-park): park T-build-residency`
- `b9797bd3` — `docs(sprints): refresh T34 post-rename + lock A`
- `a7bfbc4c` — `docs(sprints): T34 sops dotenv decrypt incant`
- `b1f1f3e4` — `docs(sprints): close T32 — universe-cli@24d6fa1`
- `e99da31b` — `docs(todo-park): R2 lifecycle GC for artemis orphans`
- `4ff9e2cc` — `docs(sprints): reconcile T32 PLAN+STATUS+HANDOFF`
- `964c8d22` — `docs(todo-park): oxfmt wiring on universe-cli`
- `0bbaca02` — `docs(sprints): T32 addendum bake gh client_id`
- `5e42cc80` — `docs(sprints): T34 sites.yaml + audit trail`
- `c9dd8817` — `docs(sprints): T34 sites.yaml ADR realign`
- `fdf74dc6` — `docs(todo-park): artemis sites slim + embedded KV`
- `a1978deb` — `docs(sprints): seed artemis sites.yaml — T34 precondition`
- `f7ebf424` — `docs(sprints): refresh T34 resume prompt`
- `0b8d6238` — `feat(artemis): close T34 — chart + Path X reframe`
- `62dbb4e2` — `docs(sprints): T34 reconcile <incoming> → 0b8d6238`
- `cee53e5d` — `feat(artemis): drop TLS — CF Flexible (cassiopeia parity)`
- `8a1a2375` — `docs(crit): justfile slop discipline + slop sweep park`
- `ab241418` — `docs(claude): force-track + CRIT justfile slop entry`
- `da5a5855` — `fix(justfile): sops --config for mirror-artemis-secrets`
- `b4567c10` — `refactor(justfile): unify deploy verb; drop artemis slop`
- `c291b317` — `docs(claude): consolidate cross-repo guidelines`
- `5f725a09` — `fix(artemis): env keys + secure-headers MW + CNP`
- `813d0171` — `fix(artemis): R2 site key uses FQDN`
- `4e7aea8e` — `docs(crit): T34 live-verify postmortem + G1 tick`
- `fd70e62c` — `feat(scripts): add trim-field-notes maintenance tool`
- `0d445551` — `docs(runbooks): add secrets-decrypt procedure`
- `a33309dc` — `docs(GUIDELINES): chart checklist + slop discipline + sprint vocab`
- `c9068153` — `docs(claude): shrink kernel; move sections to canonical homes`
- `41c7962d` — `docs(sprints): close T32 addendum — cli@0a3f1ce`
- `e843e04e` — `docs(artemis): correct local repo path to fCC/`
- `4f34c456` — `docs(sprints): STATUS reconcile post-drift-audit`
- `65e91e70` — `chore: update CLAUDE`
- `11ba5dc3` — `docs(sprints): roll 2026-04-26 STATUS post-G1`
- `20da6067` — `refactor(smoke): drop sprint scripts add postdeploy`
- `501788b5` — `feat(loadtest): add k6 scenarios for static apps`
- `2a4be9e7` — `docs(runbooks): E2E setup teardown semantics`
- `8cba6131` — `docs(runbooks): renumber + consolidate per Universe`
- `e19f710a` — `docs(sprint): correct r2_admin_s3 path → f/ops`
- `d2e0e3be` — `docs(sprint): close G2 + retire T22 verify gate`
- `a5cd74dd` — `docs(sprint): flip header — G2 GA, all gates closed`
- `29c70770` — `docs(sprint): handoff line trim`

Pre-sprint carryover from `archive/2026-04-21/`: Phase 0 foundation
(`e95f260` → `4c5e38b`), Wave A.1 Caddy D35 + namespace flip
(`d6360c7f` → `3a8d9933`), G1.1 + smoke (`6ee679bf` +
`phase4-20260426-080726`), T11 artifact (`010d577` + Bug C+D fixes
later boneyarded).

### universe-cli `main` — `45faeca` HEAD

`feat/proxy-pivot` merged into `main`; `v0.4.0` GA cut + published
to npm (CI Trusted Publisher OIDC). Sprint commits on `main`:

- `8788648` — `feat(lib): add platform.yaml v2 schema + parser` _(T33)_
- `5d7b6ef` — `docs(platform-yaml): add v2 schema reference + migration` _(T33)_
- `ccc71ab` — `feat(lib): add proxy-client for artemis API`
- `7438612` — `feat(lib): add token-store for device-flow auth`
- `9f304d6` — `feat(lib): add identity priority chain (Q10)`
- `99be630` — `feat(lib): add GitHub OAuth device flow`
- `50b8ced` — `feat(lib): add gitignore-style ignore filter`
- `045aedc` — `feat(commands): add login (device flow)`
- `759ea1a` — `feat(commands): add logout`
- `18b2871` — `feat(commands): add whoami`
- `ff85afe` — `feat(cli): wire login/logout/whoami top-level`
- `99581b0` — `feat(lib): add build runner for platform.yaml`
- `ae9c477` — `fix(lib): tsc clean for whoami + identity`
- `73bf894` — `feat(lib): add upload to proxy plane`
- `f7f3b2b` — `build(husky): add tsc to pre-commit gate`
- `2fe7c22` — `feat(commands): rewrite deploy for artemis proxy`
- `bd02b9e` — `feat(commands): rewrite promote + rollback for proxy`
- `392e88e` — `feat(commands): add ls + wire static ns`
- `1b087ab` — `chore: remove v0.3 R2-direct + storage modules`
- `4f29379` — `chore(release): v0.4.0-alpha.1 + drop AWS deps`
- `24d6fa1` — `docs: rewrite README + CHANGELOG for v0.4 proxy` _(T32 main close)_
- `0a3f1ce` — `feat(login): bake default GH OAuth client_id` _(T32 addendum)_
- `f448125` — `docs(proxy-client): correct artemis repo path`
- `45faeca` — `chore(release): v0.4.0 (proxy-pivot ship)` _(G2 GA — tag `v0.4.0` cut, npm `latest`)_

### artemis `main` — `3c3ed0c` HEAD (greenfield repo)

- `861e4c4` — `feat: initial artemis service scaffold` _(T31 close)_
- PH1-B18..B24 hardening — perf/refactor/fix (see `git log artemis/main`)
- `7d6eed3` — `ci: split into reusable test + manual docker (PH1-B25)` _(GHCR image source)_
- `49d2f32` — `feat(config): seed sites.yaml + un-gitignore` _(T34 precondition #5)_
- `434da2d` — `feat(test): add E2E integration suite`
- `005f2a4` — `feat(test): add suite setup teardown`
- `3c3ed0c` — `feat(sites): register hello-universe (bots team)`

### windmill `main` — `48536f3` HEAD

- `010d577` — `feat(flows/static): T11 per-site R2 credential provisioning` _(carryover, then boneyard)_
- `aaeab60` — `feat(resource-type): add c_cf_r2_provisioner for T11` _(carryover, deleted T36)_
- `786b257` — `feat(resource-type): add c_woodpecker_admin for T11/G1.0b` _(carryover, deleted T36)_
- `d44783a` — `fix(static/provision_site_r2_credentials): wpAdmin field name + URL drift`
- `e1db0be` — `chore(format): oxfmt canonical pass + skill header injection`
- `c5d9f92` — `fix(static/provision_site_r2_credentials): Bug C+D — UUIDs + SPA-HTML probe`
- `63488b7` — `chore(format): oxfmt canonical pass post-Bug-C+D`
- `016a868` — `feat(static): add cleanup cron for R2 deploys (T22)` _(T22 close)_
- `f8e99b9` — `chore(static): boneyard T11 files + fmt pass`
- `b511d17` — `docs(claude): @import cross-repo refs`
- `b7d96dd` — `docs(secrets): first-create resource flow`
- `8739953` — `feat(admin): add r2_admin_s3 s3 Resource (T35)` _(T35 close — initial `f/admin/`)_
- `53e59b9` — `style(static): oxfmt sweep r2_credentials`
- `c6c22c5` — `chore(static): retire T11 + woodpecker admin (T36)` _(T36 close)_
- `14e87f5` — `chore(static): canonicalize cleanup schedule defaults`
- `342e874` — `chore(static): order schedule fields alphabetically`
- `2e35d72` — `fix: update claude md`
- `7e26390` — `fix(static/cleanup): r2_admin_s3 path → f/ops` _(T35 path-drift fix)_
- `48536f3` — `chore: update lockfile`

### Universe `main` — `c2f274d` HEAD

- `e2a9356` — `feat(decisions): D016 deploy proxy plane` _(T30 close)_
- `310c7e1` — `docs(decisions): D016 amend artemis + JWT scope`
- `df255b9` — `docs(decisions): D016 amend CLI namespace static`
- `c5a1144` — `docs(spike-plan): add artemis on gxy-management`
- `fce38c9` — `docs(field-notes): RUN-residency clause for pillars`
- `4c12213` — `docs(claude): drop drift-prone status sections`
- `fc6be47` — `docs(field-notes/infra): T34 chart-side postmortem`
- `c2f274d` — `docs(decisions): D016 amend artemis local path`

## Dispatches

| Dispatch                                                      | Repo                                  | State                                                                                                                                                                                 |
| ------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T22** — Cleanup cron flow (windmill, 7d retention)          | `~/DEV/fCC-U/windmill` `main`         | **done** (`windmill@016a868`); resource path consumer flipped to `f/ops/r2_admin_s3` in `7e26390`. Schedule live `enabled: false`, `dry_run: true` — flip stays operational ClickOps. |
| **T30** — D016 ADR draft + amends                             | `~/DEV/fCC-U/Universe` `main`         | **done** (`Universe@e2a9356` + 3 amends; latest `c2f274d`)                                                                                                                            |
| **T31** — artemis svc (Go scaffold + endpoints + tests)       | `~/DEV/fCC/artemis` `main`            | **done** (`artemis@861e4c4`; PH1-B18..B25 hardening on top)                                                                                                                           |
| **T32** — universe-cli v0.4 rewrite + addendum                | `~/DEV/fCC-U/universe-cli` `main`     | **done** (`universe-cli@24d6fa1` main + `0a3f1ce` addendum + `f448125` path-doc fix; `45faeca` GA cut)                                                                                |
| **T33** — `platform.yaml` v2 schema + validator + doc         | `~/DEV/fCC-U/universe-cli` `main`     | **done** (`universe-cli@5d7b6ef`)                                                                                                                                                     |
| **T34** — Artemis chart + DNS + phase5 smoke                  | `~/DEV/fCC/infra` `feat/k3s-universe` | **done** (`infra@0b8d6238`); G1 GREEN per `4e7aea8e` postmortem                                                                                                                       |
| **T35** — IaC convert R2 admin Resource (`f/ops/r2_admin_s3`) | `~/DEV/fCC-U/windmill` `main`         | **done** (`windmill@8739953` + path-drift fix `7e26390` renamed `f/admin/` → `f/ops/`); native `s3` Resource live, `just drift` clean.                                                |
| **T36** — Retire T11 carryover + woodpecker admin             | `~/DEV/fCC-U/windmill` `main`         | **done** (`windmill@c6c22c5`); `c_cf_r2_provisioner` + `c_woodpecker_admin` Resources + RTs deleted; `provision_site_r2_credentials` script set deleted.                              |

## Gates

| Gate | State | Evidence                                                                                           |
| ---- | ----- | -------------------------------------------------------------------------------------------------- |
| G1   | GREEN | T34 live-verify postmortem `infra@4e7aea8e`                                                        |
| G2   | GREEN | npm `dist-tags.latest = 0.4.0`; remote tag `v0.4.0` → `universe-cli@45faeca`; `main` 0/0 vs origin |
| G3   | OPEN  | gxy-static teardown — post-MVP, not in 2026-04-26 scope                                            |

## Operator-owned actions remaining

**Sprint-close push (this roll):** infra (4 ahead) + windmill (2 ahead) need `git push`. universe-cli + artemis + Universe already 0/0.

**Sprint scope:** all closed. Residual outside sprint scope:

1. Windmill schedule operational flip — operator ClickOps when ready:
   - `runScriptPreviewAndWaitResult` MCP `dry_run=true` against live
   - `cleanup_old_deploys.schedule.yaml` `enabled: true` (still `dry_run=true`) for one cycle, review report
   - `args.dry_run: false` for live retention sweep
2. `WMILL_TOKEN` rotate — leaked mid-T35 session.
3. ADR-016 amendment owed to Universe team — drop "proxy reuses" claim on `u/admin/cf_r2_provisioner` (lines 209 + 244); artemis owns admin S3 keys via `infra-secrets/management/artemis.env.enc`.
4. Phase 4 sprint archive (`docs/sprints/2026-04-26/` → `archive/`) — gates on G3.

## Boneyard (kept as archaeology, do not invoke)

- windmill: `f/static/provision_site_r2_credentials.{ts,test.ts,resource-type.yaml}` boneyard headers landed `f8e99b9`; full retirement at `c6c22c5` (T36) — script set deleted; Resources `u/admin/cf_r2_provisioner` + `u/admin/woodpecker_admin` deleted (proxy plane via artemis owns admin S3 keys via `infra-secrets/management/artemis.env.enc`); RTs `c_cf_r2_provisioner` + `c_woodpecker_admin` deleted.
- universe-cli: branch `feat/woodpecker-pivot` (4 commits ahead of `main`, never merged); branch `feat/proxy-pivot` merged into `main` at `45faeca`.
- T21 Woodpecker template — demoted to optional reference (archived at `../archive/2026-04-21/dispatches/archive/`).

## Other state

- Cluster gxy-management: GREEN. Hosts artemis (3 replicas; image `ghcr.io/freecodecamp/artemis:sha-7d6eed3c…@sha256:afb2c…`).
- Cluster gxy-launchbase: GREEN. Demoted from critical path post-pivot.
- Cluster gxy-cassiopeia: GREEN. Caddy 3/3 on `caddy-s3:sha-712c6e3@sha256:e024af67…` D35 dot-scheme. R2-served sites (`<site>.freecode.camp`) flow here; **does not** front the artemis upload endpoint (artemis has its own Gateway on gxy-management at `uploads.freecode.camp`).
- Cluster gxy-static: Live, retiring at #26 cutover (post-MVP).
- CF account: `ad45585c4383c97ec7023d61b8aef8c8`.
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. SSL mode = **Flexible** on `freecode.camp`; CF Edge terminates HTTPS, origin HTTP :80 (artemis chart Gateway + cassiopeia caddy parity).
- R2 bucket: `universe-static-apps-01` (single bucket, prefix-scoped). Cleanup cron live (disabled, dry-run): 7d retention + alias pin (production + preview) + recent-3 floor + 1h grace + TOCTOU re-check.
- Live drift check (post-audit): runtime infra ↔ chart code = ✅ zero drift on image SHA, all 10 env keys, sites.yaml schema, secrets envelope. Audit ran 2026-04-27.
- Tools verified: sops, age, doctl, wmill, direnv, aws-cli v2, Go 1.26.2.
- Artemis local repo: `~/DEV/fCC/artemis/` (corrected from `fCC-U/` per ADR-016 amendment 2026-04-27).

## Governor resume — paste in fresh session if this session lost

▎ Resume Sprint 2026-04-26 governor (Universe static-apps proxy
pillar). 8 sub-tasks closed (T22 + T30 + T31 + T32 + T33 + T34 +
T35 + T36). G1 GREEN (T34 live-verify postmortem `infra@4e7aea8e`).
**G2 GREEN — `@freecodecamp/universe-cli@0.4.0` GA on npm** (tag
`v0.4.0` → `universe-cli@45faeca`; alpha.2 skipped). Sprint gates
all closed. T35 closed `windmill@8739953` + path-drift fix
`windmill@7e26390` — native `s3` Resource `f/ops/r2_admin_s3` live;
`just drift` clean. T36 closed `windmill@c6c22c5` — T11 carryover

- woodpecker admin RTs + provisioner script set fully retired.
  **Sprint-close push pending:** infra `feat/k3s-universe` (4 ahead),
  windmill `main` (2 ahead). Residual: schedule operational flip
  (ClickOps), WMILL_TOKEN rotate, ADR-016 amendment (Universe team
  lines 209 + 244), Phase 4 archive (gates on G3 gxy-static
  teardown — post-MVP). Read order: this STATUS → PLAN → DECISIONS
  → HANDOFF.
