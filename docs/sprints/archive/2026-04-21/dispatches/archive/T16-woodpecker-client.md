# T16 — universe-cli — Woodpecker API client

**Status:** done
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 16](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.6](../../architecture/rfc-gxy-cassiopeia.md) — R15 streaming
**QA deltas:** none
**Started:** 2026-04-25
**Closed:** 2026-04-25
**Closing commit(s):** `a7dd58e`

---

## Files to touch

Per spec §Task 16 § Files:

- Create: `src/woodpecker/client.ts`
- Create: `src/woodpecker/types.ts`
- Create: `src/woodpecker/client.test.ts`

## Acceptance criteria

Authoritative: spec §Task 16 § Acceptance Criteria. All must pass.
Summary: typed Woodpecker REST client, supports trigger pipeline +
stream logs (R15); injectable `fetchFn` for tests; error types preserve
HTTP status + body in `.cause`.

## Discipline

- TDD red-green-refactor.
- vitest + mocked `fetchFn`. No live Woodpecker calls in unit test.
- `pnpm oxfmt --check` + `pnpm oxlint` + `pnpm typecheck` clean.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.
- Close: edit Status, fill closure block.

---

## Closure (filled on completion)

- **Status:** done
- **Closing commit:** `a7dd58e` (universe-cli)
- **Acceptance evidence:**
  - `pnpm test tests/woodpecker` — 4/4 files green (client 12, errors 2,
    stream 2, plus credentials/woodpecker 5)
  - `pnpm exec tsc --noEmit` — clean
  - `pnpm exec oxlint src tests` — 0 warnings, 0 errors
- **Surprises:** stream module split out (`src/woodpecker/stream.ts`)
  to share polling logic across deploy/promote/rollback; not a deviation
  from spec but earlier than the §Task 19 "optional DRY" suggestion.
- **Sprint-doc patches owed:** PLAN.md matrix row flipped — done.
