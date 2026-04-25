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
