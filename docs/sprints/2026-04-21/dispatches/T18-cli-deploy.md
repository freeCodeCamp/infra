# T18 — universe-cli — Rewrite `deploy` command

**Status:** pending
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 18](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.2](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q1 (Woodpecker pipeline owns build+upload+alias)
**Depends on:** T16 (woodpecker client) + T17 (config schema)
**Started:** —
**Closed:** —
**Closing commit(s):** —

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

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `pnpm test src/commands/deploy` — all green
  - `pnpm typecheck` — clean
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip.
