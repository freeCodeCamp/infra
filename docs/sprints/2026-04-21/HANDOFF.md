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
