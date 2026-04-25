# T19 — universe-cli — Rewrite `promote` + `rollback`

**Status:** pending
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 19](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.3 + §4.8.4](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q6 (≤2 min SLO — pipeline trigger + smoke poll); Q7 (preview parity)
**Depends on:** T18 (deploy rewrite)
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Files to touch

Per spec §Task 19 § Files. Parallel rewrites to `deploy`: trigger
Woodpecker pipelines with `OP=promote` and `OP=rollback`. `rollback`
requires `--to <deploy-id>`.

## Acceptance criteria

Authoritative: spec §Task 19 § Acceptance Criteria. All must pass.
Summary: `universe promote` flips production to current preview;
`universe rollback --to <id>` reverts production to named deploy;
both stream logs and exit with pipeline result.

## Discipline

- TDD red-green-refactor.
- vitest + DI mocks.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.

---

## Closure (filled on completion)

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `pnpm test src/commands/promote src/commands/rollback` — all green
  - `pnpm typecheck` — clean
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip.
