# Sprint 2026-04-21 — HANDOFF (history log)

Append-only dated log of what shipped each session. **Not a resume
doc** — see [`STATUS.md`](STATUS.md) for live cursor and resume
prompt. Plan + decisions live in [`PLAN.md`](PLAN.md) +
[`DECISIONS.md`](DECISIONS.md).

Convention:

- One entry per session at top of "Journal".
- Dated `YYYY-MM-DD — <one-line summary>`.
- Body: what shipped, what failed, what blocked, links to commits.
- Never edit past entries — append correction entry referencing the original.

## Journal

### 2026-04-26 — Wave A.1 fully closed: G1.1 + T-r2alias-dot-scheme + G1.1.smoke green

Worker session in `~/DEV/fCC/infra` (branch `feat/k3s-universe`).

**G1.1 (operator-bootstrap).** `R2_BUCKET=universe-static-apps-01`
exported in `k3s/gxy-cassiopeia/.envrc`. Cassiopeia kubeconfig
already in place (no reseed needed); `kubectl get nodes` returned 3
Ready. Closing dispatch flipped to done.

**G1.1.smoke first run RED at step 6.** Preview alias write succeeded
to R2 but Caddy 404'd `test.preview.freecode.camp`. Root cause: D35
(2026-04-22 — preview host scheme `<site>.preview.<root>` dot-scheme
supersedes D5 `<site>--preview.<root>` suffix scheme) was a partial
migration. Caddy `r2alias` Go module + chart configmap stayed on the
pre-D35 suffix scheme. Module parsed `test.preview.freecode.camp` as
a multi-label production site → looked up
`test.preview.freecode.camp/production` (404).

**T-r2alias-dot-scheme.** New dispatch filed for the fix.

- `host.go` `parseSiteAndAlias` rewritten for dot-scheme: detect
  rightmost label of prefix == configured `preview_subdomain` →
  strip to get site labels. New tests: 7-case table + inner-label +
  site-label-named-preview. Module field renamed `PreviewSuffix` →
  `PreviewSubdomain`. Caddyfile option `preview_suffix` →
  `preview_subdomain`. Default `"preview"`. 56/56 module tests green
  (`go test -race`). `go vet` clean. (`d6360c7`)
- Caddy chart configmap aligned: `preview_subdomain "preview"`.
  (`9c96a9c`)
- New canonical builder: `.github/workflows/docker--caddy-s3.yml`
  (`workflow_dispatch` only — manual). Same-org push to
  `ghcr.io/freecodecamp/caddy-s3` via job `GITHUB_TOKEN`. Test gate +
  metadata-action tags + `linux/amd64` platform pin. Woodpecker
  pipeline `.woodpecker/caddy-s3-build.yaml` flagged secondary. Built
  - pushed image: `sha-712c6e341f9b91320a1043683e166d487b7c2725`,
    digest `sha256:e024af67…`. (`842a7fd`, `712c6e3`, `51de48c`)
- Cassiopeia chart rolled to new image:
  `values.production.yaml` tag pinned to
  `sha-712c6e3@sha256:e024af67…`. `just helm-upgrade gxy-cassiopeia
caddy` rolled the deployment; 3/3 caddy pods Running on new image.
  (`3a8d993`)
- RFC `rfc-gxy-cassiopeia.md` scrubbed: 19 stale operational
  `--preview` refs flipped to dot-scheme; D5 row + D35 supersession
  trail + §5.5 alt-considered preserved as historical context.
  (`eb5ddca`)
- Field-note (cross-repo, Universe `main`): build-residency rule for
  Universe platform pillars — pillars must build outside Universe to
  avoid bootstrap chicken-egg. Action item flagged for Universe team:
  ratify ADR. (`799022b` + `e48c3d7`)

**Build-residency boundary set.** Caddy-s3 originally targeted
`ghcr.io/freecodecamp-universe/caddy-s3` namespace; first push
403'd on org-side package permission policy. Operator decided
namespace was not worth per-pillar PAT plumbing; image retired to
`ghcr.io/freecodecamp/caddy-s3`. (Build-residency is about
RUN-residency — not org-residency.) Operator cleanup deferred:
delete `GHCR_PUSH_USER`/`GHCR_PUSH_TOKEN` repo secrets, revoke PAT,
delete stale package on `freecodecamp-universe`.

**G1.1.smoke RE-RUN GREEN.** All 8 steps pass.
`OK: phase 4 smoke passed — phase4-20260426-080726`. Trap purged R2
test prefix; post-verify confirms empty. RFC §6.6 Phase 4 exit gate
✅. Wave A.1 fully closed.

**Open after this:** T11 live preview + `wmill sync push` (operator).
Wave B (T21 + T22) unblocks once T11 observe-✓.

### 2026-04-26 — T11 shipped: Windmill flow `f/static/provision_site_r2_credentials`

Worker session in `~/DEV/fCC-U/windmill` per dispatch
`docs/sprints/2026-04-21/dispatches/T11-windmill-flow.md` (covenant:
one commit per repo, no push, no PR, no publish).

Files committed (windmill@`010d577`):

- `workspaces/platform/f/static/folder.meta.yaml`
- `workspaces/platform/f/static/provision_site_r2_credentials.ts`
  (~400 lines — typed `T11Error` hierarchy: `ValidationError`,
  `ConfigMissingError`, `CFApiError`, `CFTimeoutError`,
  `WoodpeckerApiError`, `WoodpeckerRepoMissingError`,
  `RollbackIncompleteError`. `loadAdminResource<T>()` gates
  `wmill.getResource` with `ResourceService.existsResource` per
  windmill-sgj Bug B / session.md zero-tolerance.)
- `workspaces/platform/f/static/provision_site_r2_credentials.test.ts`
  (55 tests — site validation table, CF mint contract, Woodpecker
  registration, rotation, rollback, return-shape, security,
  error hierarchy)
- `workspaces/platform/f/static/provision_site_r2_credentials.script.yaml`
- `workspaces/platform/f/static/provision_site_r2_credentials.script.lock`
  (regenerated via `bunx wmill generate-metadata` — pinned
  `windmill-client@1.691.0`)

Files committed (infra repo, separate commit):

- `justfile` — added `[group('constellations')] constellation-register
SITE` recipe + `constellation-register-test`. Dispatches via
  `bunx wmill script run f/static/provision_site_r2_credentials -d
'{"site":"<SITE>"}'` from `${WINDMILL_REPO}/workspaces/platform`
  (default `../fCC-U/windmill`).
- `scripts/tests/constellation-register.sh` — static contract test
  (recipe declared, group, usage hint, env override default,
  dispatch path, JSON envelope, fail-fast).
- `docs/sprints/2026-04-21/STATUS.md` — flipped Wave A.3 line +
  resume prompt to T11 shipped.
- `docs/sprints/2026-04-21/HANDOFF.md` — this entry.

Decisions honored:

- **D22** — Woodpecker secret is repo-scoped; calls
  `POST /api/repos/<owner>/<repo>/secrets`, NEVER
  `POST /api/orgs/<org>/secrets`.
- **D33 amended ×2 2026-04-25** — admin cred via Resource
  `u/admin/cf_r2_provisioner` (no env var, no hardcode); seeded by
  G1.0a 2026-04-26.
- **D40 supersedes D34** — flow has NO sops write; Woodpecker is
  sole persistence surface. Acceptance §D, F2/F4–F6, G1/G2, H1
  (`secretPath`), I4/I5, J5/J6 OBSOLETE per dispatch amendment.

Acceptance evidence (covenant-feasible subset):

- A1 vitest 55/55 ✅
- A2 oxfmt --check ✅
- A3 oxlint 0 warnings ✅
- A4 tsc --noEmit 0 errors in `f/static/` (pre-existing baseline
  drift in other folders, untouched)
- B1/B2/B3 site-name table-driven (valid + invalid + ordering)
- C1/C2/C3/C4/C5/C6/C9 CF mint body, path-condition exact
  `<bucket>.path.<site>/*`, token name, expiry, isolation,
  4xx, malformed JSON
- E1/E2/E3/E4/E5/E6/E9/E10 Woodpecker repo-scope, owner/repo
  defaults, two split secrets, events `[push, manual]` (no
  pull_request → I7), images `[]`, Bearer auth, repo-existence
  probe before mint
- F1/F3/F5/F6 rotation paths
- G3/G5 rollback semantics + RollbackIncompleteError
- H1 return shape exact (no `secretAccessKey`, no `secretPath`),
  H2 secretAccessKey never logged, H4 typed errors
- I1/I2/I3/I6 admin tokens via Resource only, exact path-prefix
  fuzz

Skipped per covenant ("no git push, no PR, no publish") —
operator territory:

- K1–K8 live MCP `runScriptPreviewAndWaitResult` against
  `windmill.freecodecamp.net` + smoke probe + cleanup
- `wmill sync push` to live workspace
- `just plan --show-diffs` post-push diff review
- M1 dp-engine bead close (not part of this filesystem-driven
  dispatch model)

Reviewer gate: BLOCK on first pass (C1.6 skill header, C1.7+C2.1
typed wrap of getResource throw, C2.2+C6.2 generate-metadata
receipt, C4.1 just plan). Fixed C1.6/C1.7/C2.1/C2.2/C6.2;
C4.1 documented as covenant-skipped. Re-review CLEAR.

Next: operator runs preview + `wmill sync push` to flip Wave A.3
T11 from artifact-✓ to observe-✓. Then Wave B (T21/T22) unblocks.

### 2026-04-26 — G1.0b closed: Woodpecker admin PAT + woodpecker_admin Resource live

Operator executed dispatch G1.0b in same `~/DEV/fCC-U/windmill` session
that closed G1.0a earlier the same day. Same two-repo split per
dispatch precedent.

Pattern detection step (per operator instruction "figure out HOW we
have handled other sensitive tokens, keys in this repo in the past"):
G1.0a precedent surfaced — `infra-secrets/<app>/.env.enc` (sops+age
encrypted dotenv) is the canonical home for cross-cluster Windmill
platform-app secrets. Token never paste-into-chat; operator
sops-edits the encrypted file, worker extracts via `sops -d --input-type
dotenv --output-type dotenv` into a process-local shell var, pushes the
Resource via wmill, scrubs. Captured as `feat_secrets_migration_sops`
memory amendment with verified sops command form (bare `sops` fails on
encrypted-in-place dotenv files in this repo — both `--input-type` and
`--output-type` `dotenv` flags required).

Two-repo split:

- `~/DEV/fCC/infra-secrets` `windmill/.env.enc` gained
  `WOODPECKER_ADMIN_TOKEN`. Sample-twin `windmill/.env.sample` gained
  matching slot + doc block (mint surface, scope, format, rotation,
  live-verified facts: host `https://woodpecker.freecodecamp.net` 200,
  Woodpecker version 3.13.0, API base `/api` NOT `/api/v1`). Sops
  decrypts clean.
- Windmill platform workspace: resource type `c_woodpecker_admin`
  created (schema `{baseUrl, token}`, both required, did not exist
  pre-run); resource `u/admin/woodpecker_admin` created with
  `baseUrl=https://woodpecker.freecodecamp.net/api` + extracted token.
  Live probe: HTTP 200, login `freeCodeCamp-bot`, `admin: true`,
  `/api/users` (admin-only) HTTP 200 — admin scope confirmed.
  `/api/repos` returns `[]` (no repos activated yet — activation is
  T11 prerequisite, not G1.0b token-scope issue).

Both artifacts sit outside the `f/**` IaC perimeter that `wmill.yaml`
syncs — zero file changes in `~/DEV/fCC-U/windmill`. Matches G1.0a
precedent.

No git push. No PR. No publish. Per covenant.

Commits:

- `infra-secrets`: `749ee09` — `feat(windmill): add WOODPECKER_ADMIN_TOKEN (G1.0b)`
- `~/DEV/fCC/infra` (this commit): sprint-doc patches — dispatch
  Status flip + Closure block fill, PLAN matrix `[x] done`, this
  entry, STATUS G1.0 → both halves closed.

Next unblocked:

- **T11** (windmill per-site R2 secret provisioning flow) — admin
  deps both green now (G1.0a CF + G1.0b Woodpecker). Implementation
  pending; flow consumes `u/admin/cf_r2_provisioner` and
  `u/admin/woodpecker_admin` Resources.
- **G1.1** (cassiopeia `R2_BUCKET` export + kubeconfig pull) — still
  pending, independent of G1.0 ladder. G1.1.smoke blocked on G1.1.

### 2026-04-26 — G1.0a closed: `windmill/.env.enc` complete + cf_r2_provisioner Resource live

Operator executed dispatch G1.0a in fresh Claude Code session opened in
`~/DEV/fCC-U/windmill`. Two-repo split per dispatch:

- `~/DEV/fCC/infra-secrets` `windmill/.env.enc` now carries all 4 vars:
  `CF_R2_ADMIN_API_TOKEN` (existing, untouched), `CF_ACCOUNT_ID`
  (`ad45585c4383c97ec7023d61b8aef8c8`), `R2_OPS_ACCESS_KEY_ID` +
  `R2_OPS_SECRET_ACCESS_KEY` (admin S3 ops keys, name
  `universe-static-apps-01-ops-rw`, R2 Object Read & Write,
  bucket-scoped `universe-static-apps-01`, no TTL). Sample-twin
  mirrored. Sops decrypts clean.
- Windmill platform workspace: resource type `c_cf_r2_provisioner`
  created (schema `{cfApiToken, cfAccountId}`, both required, did not
  exist pre-run — caveat in dispatch §4 fired for real); resource
  `u/admin/cf_r2_provisioner` created with extracted values. Verify
  block returns `value_keys: ["cfAccountId", "cfApiToken"]` ✓
  (T11 §6 spec match).

Both artifacts sit outside the `f/**` IaC perimeter that `wmill.yaml`
syncs — zero file changes in `~/DEV/fCC-U/windmill`. `u/admin/*` is
admin-only namespace, lives only on the platform server. Captured as
expected closure shape (no commit in windmill repo).

No git push. No PR. No publish. Per covenant.

Commits:

- `infra-secrets`: `7d8edcb` — `feat(windmill): add R2 ops S3 keys + CF_ACCOUNT_ID (D41)`
- `~/DEV/fCC/infra` (this commit): sprint-doc patches — dispatch Status
  flip, PLAN matrix `[x] done`, this entry, STATUS G1.0 → G1.0a verified.

Next unblocked: **G1.0b** (Woodpecker admin token mint + Resource push)

- **G1.1** (cassiopeia `R2_BUCKET` export + kubeconfig pull) — both
  operator gates, both can run in parallel with each other (G1.1
  independent of G1.0a/b per Wave A graph). T11 still blocked on G1.0b.
  G1.1.smoke still blocked on G1.0a + G1.1 (G1.0a now ✓; needs G1.1).

### 2026-04-25 (recovery) — sprint-state audit + smoke refactor + 4 G-dispatches

Pre-flight on T15 phase4-smoke surfaced 5 unmet operator-env prereqs.
Cross-checked windmill / CF / Woodpecker / secrets layers. Found:

- **G1.0 mis-marked done.** STATUS L46 + HANDOFF entry below (dated
  2026-04-25, "T15 Phase 4 smoke runbook + script") claimed
  "G1.0 operator bootstrap landed earlier same day (CF Account-owned
  API Token minted, `infra-secrets/windmill/.env.enc` seeded with
  `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`, smoke-curl green,
  Windmill Resource `u/admin/cf_r2_provisioner` registered)". Reality
  per live probes:
  - CF token present + functional (R2 admin perms, proven by live
    bucket list).
  - `CF_ACCOUNT_ID` MISSING from `windmill/.env.enc` (real value
    `ad45585c4383c97ec7023d61b8aef8c8`, derived live from CF API).
  - Windmill Resource `u/admin/cf_r2_provisioner` NOT registered
    (`wmill resource list` on platform workspace returns ONLY
    `f/github/apollo_11_app`).
  - No `R2_OPS_*` admin S3 keys seeded anywhere.
- **Spec ↔ runbook ↔ reality drift on 4 axes:** R2 cred path,
  CF token name (`CF_API_TOKEN` runbook vs `CLOUDFLARE_API_TOKEN`
  global), Woodpecker API base (`/api/v1` runbook vs `/api` real),
  rclone `r2:` remote unscoped.
- **T12 operator-half never tracked.** Spec L1751 explicitly
  "Do NOT actually provision". ClickOps + cred seeding never gated.

Recovery decisions (per operator):

- Strategy: full Phase 1–5 recovery
- CF naming: keep `CLOUDFLARE_API_TOKEN`, add `CF_ZONE_ID` to global
- Smoke design: refactor to **admin Bearer + ephemeral / on-demand
  S3 keys via sops decrypt of `windmill/.env.enc`** (option 2). Drops
  rclone surface entirely. Drops per-cluster R2 ops cred (T12
  ops-rw.env.enc design superseded). Single bucket
  `universe-static-apps-01`; per-site isolation = prefix scoping
  (NOT per-bucket — operator clarified the misunderstanding).
- Worktree: stay on `feat/k3s-universe`.

This sweep delivers (no commits per phase — one sweep, then commits):

- **Reports** (saved to `reports/`):
  - `T15-smoke-preflight-2026-04-25.md`
  - `sprint-state-audit-2026-04-25.md`
- **Smoke refactor:**
  - `scripts/phase4-test-site-smoke.sh` — rewrite to aws-cli + sops
    on-demand. Env input shrinks to `R2_BUCKET` +
    `GXY_CASSIOPEIA_NODE_IP`; admin creds (`CF_ACCOUNT_ID`,
    `R2_OPS_ACCESS_KEY_ID`, `R2_OPS_SECRET_ACCESS_KEY`) decrypted
    from `infra-secrets/windmill/.env.enc` per run.
  - `scripts/tests/phase4-test-site-smoke.sh` — contract test
    rewritten: asserts new env-guard set, banishes legacy guards
    (`CF_API_TOKEN`, `CF_ZONE_ID`, `AWS_*`, `R2_ENDPOINT`), banishes
    rclone in executable code, asserts single-bucket prefix usage,
    asserts sops-on-demand path. RED → GREEN.
- **Sprint-doc truth-up:** STATUS rewrites G1.0 from done to partial
  with audit refs; this HANDOFF entry corrects the original.
- **Spec / decisions amendment:**
  - DECISIONS.md amendment block: D-amend "smoke + cleanup cron use
    admin S3 keys via on-demand sops decrypt; no per-cluster ops rw
    key; T12 ops-rw.env.enc design superseded".
  - `docs/architecture/task-gxy-cassiopeia.md` Task 12 amendment block.
  - `docs/runbooks/phase4-test-site-smoke.md` env table + tooling
    section + bucket-clarity language.
- **New G-dispatches** (4 files under `dispatches/`):
  - G1.0a — windmill `.env.enc` complete + Resource push
  - G1.0b — Woodpecker admin token mint + Resource push
  - G1.1 — gxy-cassiopeia env (`R2_BUCKET` export + kubeconfig pull)
  - G1.1.smoke — operator runs `just phase4-smoke`
- **Sprint protocol amendment:** `docs/GUIDELINES.md` + `infra/CLAUDE.md`
  add `verify <gate>` verb. Every G-dispatch declares verify command;
  operator-run gates require green verify before close.
- **PLAN.md matrix:** add G-rows to #24 sub-task matrix; update Wave A
  graph to reflect recovery dependency ladder.

Live-system facts pinned (probed during audit, sourced from CF API +
Windmill + sops + DNS):

| Fact                       | Value                                                 |
| -------------------------- | ----------------------------------------------------- |
| CF Account ID              | `ad45585c4383c97ec7023d61b8aef8c8`                    |
| Bucket                     | `universe-static-apps-01` (created 2026-04-20)        |
| Cassiopeia node IPs        | `165.227.149.249`, `46.101.179.141`, `188.166.165.62` |
| Woodpecker API base        | `/api` (not `/api/v1`)                                |
| Existing windmill resource | `f/github/apollo_11_app` only                         |

No live-system mutations during audit. No `git push` / no `wmill resource push` / no R2 writes.

### 2026-04-25 — Wave A.2 follow-up: slop strip + D37 enforcement (universe-cli)

Audit of A.2 closure surfaced T20 strip-completeness gap: 5 dead error
classes + 6 orphan exit codes survived the rclone/S3 cut with circular
tests proving dead code matches dead constants. Operator ran follow-up
in parallel universe-cli session; verified clean.

universe-cli commits (branch `feat/woodpecker-pivot`):

- `4f54012` — refactor(errors): strip orphan classes (`StorageError`,
  `OutputDirError`, `AliasError`, `DeployNotFoundError`, `ConfirmError`)
  - 6 orphan exit codes (`EXIT_STORAGE`, `EXIT_OUTPUT_DIR`, `EXIT_ALIAS`,
    `EXIT_DEPLOY_NOT_FOUND`, `EXIT_CONFIRM`, `EXIT_PARTIAL`) + circular
    tests. Net: -91 lines across 4 files.
- `0113c9c` — feat(config): D37 domain pattern + `production_branch`
  covenant. Schema enforces production hostname matches `<site>` +
  preview matches `<site>.preview.freecode.camp` (D35 dot-scheme).
  Off-list bonus surfaced during the strip; tightens promote/rollback
  branch resolution.

Acceptance: `pnpm test` 166/166 green (was 167 — net -1 from removing
62 dead tests + adding 61 D37 tests), `pnpm exec tsc --noEmit` clean,
`pnpm exec oxlint src tests` 0/0.

#25 publish path now clean — no orphan symbols carried forward.

Commits (universe-cli, awaiting operator push): `4f54012`, `0113c9c`.

### 2026-04-25 — Wave A.2 universe-cli T16-T20 closed + v0.4.0-beta.1 prepped

`feat/woodpecker-pivot` audit + closure pass. All five universe-cli
tasks shipped earlier same day were carrying open dispatch headers;
this entry closes the loop.

Universe-cli commits referenced (branch `feat/woodpecker-pivot`):

- `a7dd58e` — T16 + T17. Woodpecker client (`src/woodpecker/{client,
types,errors,stream,index}.ts`), credentials resolver
  (`src/credentials/woodpecker.ts`), site-name validator
  (`src/validation/site-name.ts`), `PipelineError` + `EXIT_PIPELINE=20`,
  config schema strict-mode + `woodpecker {endpoint,repo_id}` section.
- `f6971cf` — T18 + T19 + T20. Full rewrite of `deploy`, `promote`,
  `rollback` to trigger Woodpecker pipelines via API; deletion of
  `src/storage/*`, `src/deploy/{upload,metadata,preflight,id,walk}.ts`,
  `src/credentials/resolver.ts`; `@aws-sdk/client-s3` removed from
  `dependencies`.
- `89ab897` — D35 dot-scheme test fixture correction. Audit caught
  three `tests/commands/{deploy,promote,rollback}.test.ts` fixtures
  still using legacy `<site>--preview.freecode.camp` hyphen-scheme.
  Re-ran 167/167 green.
- `03c5f19` — T20 release prep. `package.json.version` =
  `0.4.0-beta.1`, CHANGELOG entry authored (Breaking / Added /
  Removed / Migration); release CI auto-bump remains a no-op on
  operator-triggered run.

Dispatch closures (this commit): T16, T17, T18, T19, T20 status flipped
to `done`, closure blocks filled with acceptance evidence + commit
SHAs + surprises (D35 fixture drift, early `stream.ts` extraction,
release-CI no-op behaviour). PLAN.md matrix rows flipped to `[x] done`.

Field note appended at
`~/DEV/fCC-U/Universe/spike/field-notes/universe-cli.md`.

Acceptance: `pnpm test` 167/167 green, `pnpm exec tsc --noEmit` clean,
`pnpm exec oxlint src tests` 0/0. No live Woodpecker call exercised
yet — that surfaces during Wave B (T21 template + reference repo
deploy against gxy-launchbase + gxy-cassiopeia).

Next unblocked: **Wave A.3 windmill T11** (per-site R2 secret
provisioning flow). Wave B follows once T11 observes green.

#25 release dispatch unblocks: operator can run release workflow with
`version=0.4.0-beta.1` after T11 + Wave B exercise the live Woodpecker
flow end-to-end.

Commits (universe-cli, awaiting operator push): `a7dd58e`, `f6971cf`,
`89ab897`, `03c5f19`.

### 2026-04-25 — T15 Phase 4 smoke runbook + script (Wave A.1 closed)

G1.0 operator bootstrap landed earlier same day (CF Account-owned API
Token minted, `infra-secrets/windmill/.env.enc` seeded with
`CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`, smoke-curl green, Windmill
Resource `u/admin/cf_r2_provisioner` registered). Wave A.1 fired.

T15 closed via TDD path:

- **NEW** `scripts/tests/phase4-test-site-smoke.sh` — RED-first static
  contract suite. Asserts strict mode, all 7 env guards, **D35
  dot-scheme** preview hostname (`<site>.preview.freecode.camp`),
  trap with `rclone purge` cleanup (acceptance §2544 — cleanup on
  success AND failure), `printf` over `echo -n`, `[[ ]]` over `[ ]`,
  shellcheck clean, `bash -n` clean.
- **NEW** `scripts/phase4-test-site-smoke.sh` — Phase 4 exit gate per
  RFC §6.6. Uploads test deploy → writes prod alias → polls Q6 SLO
  (30s × 2 green) → verifies preview 404 → writes preview alias →
  verifies serve → purges. Trap re-runs purge on every exit path.
- **NEW** `docs/runbooks/phase4-test-site-smoke.md` — prerequisites,
  required env, 8-step success flow, failure-path matrix, rollback,
  exit-gate semantics.
- **MODIFIED** `justfile` — new `[group('smoke')]` with two recipes:
  `phase4-smoke` (live gate) + `phase4-smoke-test` (static contract).

Deltas from spec body recorded in dispatch closure block: D35 dot-scheme
override, trap upgraded to R2 cleanup, env guards expanded 4→7, shell
rules applied.

**Live R2 / DNS run not executed by this dispatch** — script + runbook
shipped; operator runs `just phase4-smoke` against gxy-cassiopeia with
operator-added temp DNS. RFC §6.6 Phase 4 exit fires only after that
run is green.

Next unblocked: **Wave A.2 universe-cli T16** (woodpecker client) →
T17 (config schema) → observe → A.3 windmill T11.

Commits: `1e3b439`.

### 2026-04-25 (later same day) — Sprint doc consolidation: STATUS/PLAN/DECISIONS

Refactored sprint dir to filesystem-driven structure with explicit
session-roll target.

- **NEW** `STATUS.md` — canonical session-roll output (Shipped/Open/Other state/Resume prompt). Overwritten each `roll the session`.
- **NEW** `PLAN.md` — replaces `MASTER.md` + folds `24-static-apps-k7d.md`. Stable plan + Wave dep graph + sub-task matrix.
- **NEW** `DECISIONS.md` — replaces `QA-recommendations.md`. Q1–Q8 locked + D33–D40 cross-refs to RFC.
- **TRIMMED** `HANDOFF.md` (this file) — pure append-only history log; next-step content moved to STATUS.
- **DELETED** `MASTER.md`, `24-static-apps-k7d.md`, `QA-recommendations.md` (folded into PLAN/DECISIONS).
- **UPDATED** `README.md` — read-order points at STATUS first.
- **UPDATED** `docs/GUIDELINES.md` §Sprint docs — new structure + per-task derived-doc closure checklist.
- **UPDATED** `infra/CLAUDE.md` — added Sprint protocol section for minimal-prompt session start.

### 2026-04-25 — D33 second amendment + infra-secrets README rewrite

Structure deep-audit caught error in earlier same-day amendment.
First-pass D33 moved admin token from invented `platform/` dir to
`global/.env.enc`. But `global/.env.enc` is direnv-loaded into
operator shell on every `cd infra/`, leaking token into every shell.

**Corrected:** admin token home is `infra-secrets/windmill/.env.enc`
— activates the previously-empty reserved Universe-platform-app
namespace per `rfc-secrets-layout.md` D4. NOT loaded into shell
(consumed on-demand via `sops -d` or `wmill resource push`).

Commits: `f2c3767` (RFC D33 2nd amend), `f06ca87` (T11 dispatch
realigned), `c33518d` (RFC bucket name align), `584ada3` (T11 CF
token form drift fix), `a60fe10` (r2-bucket-verify SC2015 fix),
`d43d1e4` (gitignore /.cocoindex_code/), `ae82d8e` (filesystem-driven
dispatches; drop bead tracking).

### 2026-04-25 — Wave A staggered dispatch plan + D33/D40 amendments

Sprint dispatch shifted from "fire all 3 in parallel" to **staggered
Wave A** (one worker at a time, observe + verify before next launch).
Cause: T11 dispatch doc had drifted from `rfc-secrets-layout.md`
two-scope convention; structure audit caught it before any worker
fired.

- **D33 amended in place** (RFC `rfc-gxy-cassiopeia.md`): admin token path moved `platform/` → `global/.env.enc`. Vars reduced to two — `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`. S3-style admin keys dropped.
- **D34 superseded by new D40**: per-site R2 secrets persist **only** in Woodpecker (D22 channel). No `constellations/` dir, no `.sops.yaml` rule. Re-mint via CF API is recovery path.
- bun PATH NOT in shell — workers run `bunx wmill ...` from windmill repo cwd.

Commits: `ee7c08a` (HANDOFF refresh + T11 dispatch), `16df7fe` (RFC D33 amend + D40 supersede D34), `e2bdc95` (HANDOFF Wave A staggered plan).

### 2026-04-22 — QA lock + rename dogfood + RFC amendments

- gxy-mgmt → gxy-management reprovision executed. Windmill restored from S3 CronJob dump (local backup truncation bug fixed in `justfile windmill-backup`).
- Dogfood gaps captured in `docs/flight-manuals/gxy-management.md` (new Phase 3.5 Windmill restore) + `Universe/spike/field-notes/infra.md`.
- QA brainstorm Q1–Q8 accepted; `QA-recommendations.md` marked ACCEPTED 2026-04-22.
- MASTER.md written. #24 dispatch block written (`24-static-apps-k7d.md`).
- RFC amendments D33–D39 appended to `rfc-gxy-cassiopeia.md`: D5 superseded by D35 (`.preview` dot scheme); D29 superseded by D36 (DO FW only, no CF-IP allow-list).
- T32 verified live (Woodpecker DNS + CF Access posture).
- ArgoCD deployment deferred to TODO-park (not MVP crit-path).

Commits (operator pushed 2026-04-22): `e95f260`, `6bfaf6d`,
`f277aa9`, `87fcdff`, `8914d69`, `25d33df`, `99bc332`, `30f2205`,
`3465a9d`, `779ab28`, `cef8c8a`, `827bc7e`, `9d49cda`, `97b9c14`,
`39d49b5`, `6f3c84c`, `3376e86`, `4c5e38b`.

### 2026-04-21 — Audit + reset

- `docs/sprints/2026-04-20/` scrapped; drifted from post-bootstrap reality.
- Fresh plan built around shipping static-apps E2E.
- Rename `gxy-mgmt` → `gxy-management` decided; acceptable dogfood path.
- Windmill permanent home = `gxy-management` (overrides ADR-001).
- CF Access dropped globally; OAuth org-gate canonical for native-OAuth tools. Resolves D22.
- Static-apps E2E = MVP. Dynamic, BM, o11y, BetterAuth deferred.
- ADR amendment ownership bypass granted (in-place this round).
