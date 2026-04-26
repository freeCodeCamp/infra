# Sprint 2026-04-26 — HANDOFF (history log)

Append-only dated log of what shipped each session. **Not a resume doc** — see [`STATUS.md`](STATUS.md) for live cursor and resume prompt. Plan + decisions live in [`PLAN.md`](PLAN.md) + [`DECISIONS.md`](DECISIONS.md).

Convention:

- One entry per session at top of "Journal".
- Dated `YYYY-MM-DD — <one-line summary>`.
- Body: what shipped, what failed, what blocked, links to commits.
- Never edit past entries — append correction entry referencing the original.

## Journal

### 2026-04-27 — T31 closed: artemis Go svc greenfield scaffold

T31 worker session in `~/DEV/fCC-U/artemis` (greenfield repo) shipped
full Go microservice scaffold per dispatch §Files + §API surface +
§Acceptance. Single commit allowed for greenfield init.

**Closing commit (artemis `main`, NEW remote, not pushed):**

- `861e4c4` — `feat: initial artemis service scaffold`

**Worker dispatch close commit (infra `feat/k3s-universe`):**

- `7465ce41` — `docs(sprint): close T31 — artemis@861e4c4` (worker
  flipped dispatch Status header per multi-session discipline; governor
  reconciles PLAN matrix + STATUS + this HANDOFF in separate commit
  below).

**Sprint state delta this commit (infra):**

- PLAN top-level task chain row T31 → `done`.
- PLAN dispatch matrix row T31 → `[x] done` (also corrected area label
  `uploads (new repo)` → `artemis (new repo)` + dispatch path).
- STATUS Open table T31 → `done`; Shipped section gained artemis block
  - `7465ce41` worker close + this reconciliation commit; concurrency
    plan rewritten (T34 + T32 unblocked).
- HANDOFF — this entry.

**Unblocks:** T34 (Caddy reverse proxy + DNS + smoke retarget) — needs
first GHCR image tag from artemis CI before Helm install (operator:
`gh workflow run` on artemis repo). T32 (universe-cli v0.4 commands)
fully unblocked — both artemis API contract live + T33 schema landed.

### 2026-04-27 — T33 closed: `platform.yaml` v2 schema + validator + doc

T33 worker session in `~/DEV/fCC-U/universe-cli` shipped v2 schema
strip-and-replace per D016 §`platform.yaml` schema + dispatch
acceptance gates. Branch `feat/proxy-pivot` cut fresh off `main`
(per Q14); `feat/woodpecker-pivot` archaeology untouched.

**Closing commits (universe-cli `feat/proxy-pivot`, not pushed):**

- `8788648` — `feat(lib): add platform.yaml v2 schema + parser`
- `5d7b6ef` — `docs(platform-yaml): add v2 schema reference + migration`

**Files landed:**

- `src/lib/platform-yaml.schema.ts` — zod v2 schema (strict, prefault for nested defaults)
- `src/lib/platform-yaml.ts` — `parsePlatformYaml(text) → {ok,value} | {ok,error}` + v1 marker detector
- `tests/lib/platform-yaml.test.ts` — 32 tests (RED → GREEN)
- `docs/platform-yaml.md` — schema reference + v0.3→v0.4 migration delta
- `CHANGELOG.md` — `[Unreleased]` BREAKING entry
- `README.md` — Configuration section + doc link

**Gates:**

- Tests: 252/252 (24 files; new file 32/32)
- Lint: 0 warn / 0 err (oxlint, 50 files)
- `tsc --noEmit`: clean

**Behavioral verified:**

- v1 markers detected: `r2`, `stack`, `domain`, `static`, `name` — error template per dispatch §Behavioral gates
- Defaults applied: `build.output: "dist"`, `deploy.preview: true`, `deploy.ignore: ["*.map","node_modules/**",".git/**",".env*"]`
- Site name validator carries D19 + D37 (lowercase, digits, single hyphens, 1–63 chars, no leading/trailing/consecutive hyphens)

**Sprint state delta this commit (infra):**

- T33 dispatch Status `pending → done`; closing-commit SHAs recorded;
  closure checklist boxes ticked.
- PLAN top-level task chain row T33 → `done`.
- PLAN dispatch matrix row T33 → `[x] done`.
- STATUS Open table T33 → `done`; Shipped section gained universe-cli
  block; concurrency plan rewritten (T33 ✅, T32 unblocked for schema
  consumption).
- HANDOFF — this entry.

**Unblocks:** T32 (universe-cli v0.4) can now consume the validator
surface for `deploy` / `promote` / `rollback` command wiring. T31 still
in-flight (independent lane). T34 still blocks on T31 image.

### 2026-04-26 (late evening) — T30 closed: ADR-016 landed in Universe

Governing session under broken-ownership authorization wrote
`~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md` per T30 dispatch
brief. ADR mirrors ADR-015 conventions; nine sections present (Context,
Decision, Architecture, Authn/Authz, R2 layout, Operational surface,
Migration, Consequences, Cross-references) plus empty Amendments block.
Q9–Q15 verbatim leans recorded; cross-refs ADR-003 / ADR-004 / ADR-008 /
ADR-009 / ADR-010 / ADR-011, RFC cassiopeia (D33–D42), and supersedes
prior-sprint dispatch T11. Universe `decisions/README.md` Accepted list
gained ADR-016 row.

**Closing commit:** `Universe@e2a9356` —
`feat(decisions): D016 deploy proxy plane`. Universe now ahead of
`origin/main` by 4 commits (3 prior field-notes + this ADR). Operator
pushes at sprint close.

**Sprint state delta this commit (infra):**

- T30 dispatch Status flipped `pending → done`; closing-commit SHA
  recorded; closure checklist boxes ticked.
- PLAN top-level task chain row T30 → `done`.
- PLAN dispatch matrix row T30 → `[x] done`.
- HANDOFF — this entry.
- DECISIONS D43 row already cross-refs `016-deploy-proxy.md` from sprint
  open; no edit required.

**Next move:** open T31 — Go scaffold + endpoints + tests in NEW
greenfield repo `~/DEV/fCC-U/uploads/`. Module path
`github.com/freeCodeCamp/uploads`. Go 1.26.2 verified on host.

### 2026-04-26 (late evening) — Sprint opens at branch point

Governing session in `~/DEV/fCC/infra` (branch `feat/k3s-universe`).

**Predecessor:** [`../archive/2026-04-21/`](../archive/2026-04-21/).
That sprint shipped Wave A.1 (Caddy `r2_alias` D35 dot-scheme + R2
single-bucket layout + Phase 4 smoke harness) green. Wave A.2
(`universe-cli@feat/woodpecker-pivot`) shipped but is archaeology
post-pivot. Wave A.3 (T11 per-site R2 token mint) SUPERSEDED by D016
deploy-proxy plane (logged in archived sprint HANDOFF 2026-04-26
evening + this sprint DECISIONS D43).

**This sprint scope:** Phase 1 sub-deliverables P1.1 + P1.7 + P1.8
(deploy-proxy svc + universe-cli v0.4 + `platform.yaml` v2 schema). T22
cleanup cron carried forward (post-T31 live verification).

**Authority:** Broken ownership for tonight's session per operator
command 2026-04-26 evening. Session governs cross-repo (Universe ADRs

- universe-cli + windmill + new uploads repo) without per-team
  round-trip. Logged here for transparency. Teams can amend post-hoc via
  append-only blocks.

**Sprint state delta this commit:**

- Created sprint dir `docs/sprints/2026-04-26/` with README, STATUS, PLAN, DECISIONS, HANDOFF (this file).
- Moved 6 active dispatches from prior sprint dir: T22 + T30–T34.
- Archived prior sprint dir → `docs/sprints/archive/2026-04-21/` (full content preserved; closure entry appended to its HANDOFF).
- DECISIONS D43 row + Q9–Q15 brainstorm rationale landed.
- PLAN: Phase 1 sub-deliverables + dispatch graph clean-rewritten (no pre/post pivot mixing).
- STATUS: live cursor focused on T30→T34→T22 sequence; resume prompt rewritten.
- README: read order + layout + predecessor pointer + authority model.

**Carries forward (commits not pushed):** all Phase 0 foundation + Wave
A.1 commits + T11 artifact at `windmill@010d577`. Operator pushes at
sprint close (4 repos + new uploads remote).

**Next move:** open T30. Write `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`.
Single Universe commit. Then T31 (uploads svc Go scaffold + endpoints + tests).

**Tooling verified for incoming work:** Go 1.26.2 darwin/arm64
(`/opt/homebrew/bin/go`). Universe-cli toolchain (Bun + vitest + oxfmt

- oxlint + tsup + husky) unchanged. ctx-mode v1.0.98 healthy
  (`ctx_doctor` PASS).
