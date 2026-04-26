# T19 — universe-cli — Rewrite `promote` + `rollback`

**Status:** done
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 19](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.3 + §4.8.4](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q6 (≤2 min SLO — pipeline trigger + smoke poll); Q7
(preview parity); D35 (dot-scheme test fixture aligned)
**Depends on:** T18 (deploy rewrite)
**Started:** 2026-04-25
**Closed:** 2026-04-25
**Closing commit(s):** `f6971cf`, `89ab897` (D35 dot-scheme test fixture)

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

- **Status:** done
- **Closing commit:** `f6971cf` (rewrite) + `89ab897` (D35 dot-scheme
  test fixture)
- **Acceptance evidence:**
  - `pnpm test tests/commands/promote tests/commands/rollback` — 6+9
    green
  - `pnpm exec tsc --noEmit` — clean
  - `EXIT_ARGS` + `EXIT_PIPELINE=20` added to `src/output/exit-codes.ts`
    without colliding with prior codes
- **Surprises:** `streamFirstStepLogs` extracted to
  `src/woodpecker/stream.ts` early (during T16) — DRY pulled forward;
  promote/rollback consume it directly without further refactor.
- **Sprint-doc patches owed:** PLAN.md matrix row flipped — done.
