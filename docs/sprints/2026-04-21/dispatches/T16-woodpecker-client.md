# T16 — universe-cli — Woodpecker API client

**Status:** pending
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 16](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.6](../../architecture/rfc-gxy-cassiopeia.md) — R15 streaming
**QA deltas:** none
**Started:** —
**Closed:** —
**Closing commit(s):** —

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

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `pnpm test src/woodpecker` — all green
  - `pnpm typecheck` — clean
  - `pnpm oxlint` — clean
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip in
  `24-static-apps-k7d.md`.
