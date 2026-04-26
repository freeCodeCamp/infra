# T18 — universe-cli — Rewrite `deploy` command

**Status:** done
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 18](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.2](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q1 (Woodpecker pipeline owns build+upload+alias); D35
(dot-scheme preview hostname applied to `previewUrl` builder + tests)
**Depends on:** T16 (woodpecker client) + T17 (config schema)
**Started:** 2026-04-25
**Closed:** 2026-04-25
**Closing commit(s):** `f6971cf`, `89ab897` (D35 dot-scheme test fixture)

---

## Files to touch

Per spec §Task 18 § Files. `deploy` consumes T16 client + T17 config:
triggers Woodpecker pipeline with appropriate `OP=deploy` variable.
Streams logs back to operator terminal.

## Acceptance criteria

Authoritative: spec §Task 18 § Acceptance Criteria. All must pass.
Summary: `universe deploy` triggers pipeline, streams logs, exits with
pipeline result code; rejects invalid site names pre-flight.

## Discipline

- TDD red-green-refactor.
- vitest + DI mocks (no live Woodpecker call in unit test).
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.

---

## Closure (filled on completion)

- **Status:** done
- **Closing commit:** `f6971cf` (rewrite) + `89ab897` (D35 dot-scheme
  test fixture)
- **Acceptance evidence:**
  - `pnpm test tests/commands/deploy` — 9/9 green
  - `pnpm exec tsc --noEmit` — clean
  - `pnpm exec oxlint src tests` — 0 warnings, 0 errors
- **Surprises:** preview hostname comes from `config.domain.preview`
  (no scheme baked in); audit caught test fixtures still using legacy
  `<site>--preview.freecode.camp` hyphen-scheme — corrected in
  follow-up commit `89ab897` to dot-scheme per Q5/D35.
- **Sprint-doc patches owed:** PLAN.md matrix row flipped — done.
