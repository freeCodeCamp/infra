# Sprint 2026-04-26 — STATUS

Updated: 2026-04-27 (post-`roll the sprint`) · All 6 sub-tasks
**done** · G1 GREEN · G2 unblocked · 5 repos pushed + synced ·
Operator gates remaining: T22 ClickOps + npm publish.

Canonical session-roll output. Overwritten each `roll the sprint`.
Read this **before** PLAN.md or DECISIONS.md.

## Shipped

All sprint commits below are **pushed to origin** (verified
`@{u}...HEAD == 0/0` on every repo).

### infra `feat/k3s-universe` — `65e91e7` HEAD

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

Pre-sprint carryover from `archive/2026-04-21/`: Phase 0 foundation
(`e95f260` → `4c5e38b`), Wave A.1 Caddy D35 + namespace flip
(`d6360c7f` → `3a8d9933`), G1.1 + smoke (`6ee679bf` +
`phase4-20260426-080726`), T11 artifact (`010d577` + Bug C+D fixes
later boneyarded).

### universe-cli `feat/proxy-pivot` — `f448125` HEAD

Branch cut fresh off `main` 2026-04-26. T32 + T33 + T32-addendum
artifacts:

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
- `4f29379` — `chore(release): v0.4.0-alpha.1 + drop AWS deps` _(T32 main close: `24d6fa1`)_
- `24d6fa1` — `docs: rewrite README + CHANGELOG for v0.4 proxy`
- `0a3f1ce` — `feat(login): bake default GH OAuth client_id` _(T32 addendum — G2 cleared)_
- `f448125` — `docs(proxy-client): correct artemis repo path`

### artemis `main` — `49d2f32` HEAD (greenfield repo)

- `861e4c4` — `feat: initial artemis service scaffold` _(T31 close)_
- `7d6eed3` — `ci: split into reusable test + manual docker (PH1-B25)` _(GHCR image source)_
- `49d2f32` — `feat(config): seed sites.yaml + un-gitignore` _(T34 precondition #5)_

Plus PH1-B18..B24 hardening commits (perf/refactor/fix) committed
before B25 — see `git log artemis/main`.

### windmill `main` — `b511d17` HEAD

- `010d577` — `feat(flows/static): T11 per-site R2 credential provisioning` _(carryover, then boneyard)_
- `aaeab60` — `feat(resource-type): add c_cf_r2_provisioner for T11` _(carryover)_
- `786b257` — `feat(resource-type): add c_woodpecker_admin for T11/G1.0b` _(carryover)_
- `d44783a` — `fix(static/provision_site_r2_credentials): wpAdmin field name + URL drift`
- `e1db0be` — `chore(format): oxfmt canonical pass + skill header injection`
- `c5d9f92` — `fix(static/provision_site_r2_credentials): Bug C+D — UUIDs + SPA-HTML probe`
- `63488b7` — `chore(format): oxfmt canonical pass post-Bug-C+D`
- `016a868` — `feat(static): add cleanup cron for R2 deploys (T22)` _(T22 close)_
- `f8e99b9` — `chore(static): boneyard T11 files + fmt pass`
- `b511d17` — `docs(claude): @import cross-repo refs`

### Universe `main` — `c2f274d` HEAD

- `e2a9356` — `feat(decisions): D016 deploy proxy plane` _(T30 close)_
- `310c7e1` — `docs(decisions): D016 amend artemis + JWT scope`
- `df255b9` — `docs(decisions): D016 amend CLI namespace static`
- `c5a1144` — `docs(spike-plan): add artemis on gxy-management`
- `fce38c9` — `docs(field-notes): RUN-residency clause for pillars`
- `4c12213` — `docs(claude): drop drift-prone status sections`
- `fc6be47` — `docs(field-notes/infra): T34 chart-side postmortem`
- `c2f274d` — `docs(decisions): D016 amend artemis local path`

## Open

| Dispatch                                                | Repo                                          | State                                                                                  |
| ------------------------------------------------------- | --------------------------------------------- | -------------------------------------------------------------------------------------- |
| **T22** — Cleanup cron flow (windmill, 7d retention)    | `~/DEV/fCC-U/windmill` `main`                 | **done** (`windmill@016a868`); operator gate: schedule flip + R2 admin Resource verify |
| **T30** — D016 ADR draft + amends                       | `~/DEV/fCC-U/Universe` `main`                 | **done** (`Universe@e2a9356` + 3 amends; latest `c2f274d`)                             |
| **T31** — artemis svc (Go scaffold + endpoints + tests) | `~/DEV/fCC/artemis` `main`                    | **done** (`artemis@861e4c4`; PH1-B18..B25 hardening on top)                            |
| **T32** — universe-cli v0.4 rewrite + addendum          | `~/DEV/fCC-U/universe-cli` `feat/proxy-pivot` | **done** (`universe-cli@24d6fa1` main + `0a3f1ce` addendum + `f448125` path-doc fix)   |
| **T33** — `platform.yaml` v2 schema + validator + doc   | `~/DEV/fCC-U/universe-cli` `feat/proxy-pivot` | **done** (`universe-cli@5d7b6ef`)                                                      |
| **T34** — Artemis chart + DNS + phase5 smoke            | `~/DEV/fCC/infra` `feat/k3s-universe`         | **done** (`infra@0b8d6238`); G1 GREEN per `4e7aea8e` postmortem                        |

## Operator-owned actions remaining

Sprint-close push: **DONE 2026-04-27 (operator)**. All 5 repos
pushed; every branch tracks origin; ahead/behind = 0/0 verified.

Outstanding:

1. **T22 live verify (windmill ClickOps).** Flip cleanup-cron
   schedule → active. Verify admin S3 Resource resolves. Sweep
   dry-run first against an empty deploy window. Closes the
   windmill-side gate; G1/G2 unaffected.

2. **G2 — npm publish `@freecodecamp/universe-cli@0.4.0-alpha.2`.**
   Branch `feat/proxy-pivot` is pushed; CI Trusted Publisher OIDC
   handles the npm side on tag. Cut release tag, watch CI green,
   verify package on registry.

## Boneyard (kept as archaeology, do not invoke)

- windmill: `f/static/provision_site_r2_credentials.{ts,test.ts,resource-type.yaml}` boneyard headers landed `f8e99b9`; Resources `u/admin/cf_r2_provisioner` (proxy reuses) + `u/admin/woodpecker_admin` (retired).
- universe-cli: branch `feat/woodpecker-pivot` (4 commits ahead of `main`, never merged).
- T21 Woodpecker template — demoted to optional reference (archived at `../archive/2026-04-21/dispatches/archive/`).

## Other state

- Cluster gxy-management: GREEN. Hosts artemis (3 replicas; image `ghcr.io/freecodecamp/artemis:sha-7d6eed3c…@sha256:afb2c…`).
- Cluster gxy-launchbase: GREEN. Demoted from critical path post-pivot.
- Cluster gxy-cassiopeia: GREEN. Caddy 3/3 on `caddy-s3:sha-712c6e3@sha256:e024af67…` D35 dot-scheme. R2-served sites (`<site>.freecode.camp`) flow here; **does not** front the artemis upload endpoint (artemis has its own Gateway on gxy-management at `uploads.freecode.camp`).
- Cluster gxy-static: Live, retiring at #26 cutover (post-MVP).
- CF account: `ad45585c4383c97ec7023d61b8aef8c8`.
- CF zones: `freecodecamp.net` + `freecode.camp` proxied. SSL mode = **Flexible** on `freecode.camp`; CF Edge terminates HTTPS, origin HTTP :80 (artemis chart Gateway + cassiopeia caddy parity).
- R2 bucket: `universe-static-apps-01` (single bucket, prefix-scoped).
- Live drift check (post-audit): runtime infra ↔ chart code = ✅ zero drift on image SHA, all 10 env keys, sites.yaml schema, secrets envelope. Audit ran 2026-04-27.
- Tools verified: sops, age, doctl, wmill, direnv, aws-cli v2, Go 1.26.2.
- Artemis local repo: `~/DEV/fCC/artemis/` (corrected from `fCC-U/` per ADR-016 amendment 2026-04-27).

## Governor resume — paste in fresh session if this session lost

▎ Resume Sprint 2026-04-26 governor (Universe static-apps proxy
pillar). All 6 sub-tasks closed (T22 + T30 + T31 + T32 + T33 + T34).
G1 GREEN (T34 live verify postmortem `infra@4e7aea8e`). G2 unblocked
(T32 addendum `universe-cli@0a3f1ce`). All 5 repos pushed + synced
0/0. Drift audit 2026-04-27 — runtime ↔ chart code zero drift; doc
drift on artemis local path fixed across infra (`e843e04`),
universe-cli (`f448125`), Universe ADR-016 amendment (`c2f274d`).
Outstanding operator gates: T22 windmill ClickOps (cron schedule
flip + R2 admin Resource verify) + G2 npm publish
`@freecodecamp/universe-cli@0.4.0-alpha.2` via OIDC Trusted
Publisher tag-trigger. Sprint is one operator session away from
archival under `docs/sprints/archive/2026-04-26/`. Read order: this
STATUS → PLAN → DECISIONS → HANDOFF.
