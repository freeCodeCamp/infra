# T22 — Cleanup cron Windmill flow

**Status:** pending
**Worker:** w-windmill
**Repo:** `~/DEV/fCC-U/windmill` (branch: `main`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 22](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8 cleanup + ADR-007 retention](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q7 (preview pinned), Q8 (hard 7d retention)
**Depends on:** T11 closure (admin Bearer Resource `u/admin/cf_r2_provisioner` exists)
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Files to touch

Per spec §Task 22 § Files. Likely lands at
`workspaces/platform/f/static/cleanup_old_deploys.ts` + `.yaml` +
`.test.ts`. Schedule via Windmill cron Resource.

## Acceptance criteria

Authoritative: spec §Task 22 § Acceptance Criteria. All must pass.
Summary: dry-run mode computes delete list without deleting; lock
acquisition prevents concurrent runs; aliased deploys (production +
preview) NEVER deleted; deploys <1h old NEVER deleted regardless of
age; deploys >7d + not aliased + >1h deleted; alias-flip race closed
(re-check before delete).

## Discipline

- TDD red-green-refactor.
- vitest + mocked R2 + lock fixtures.
- `runScriptPreviewAndWaitResult` MCP green BEFORE `wmill sync push`.
- `wmill sync push --dry-run` zero unintended deletions.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.

---

## Closure (filled on completion)

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `pnpm test workspaces/platform/f/static/` — all green for
    `cleanup_old_deploys.test.ts`
  - `pnpm oxfmt --check` + `pnpm oxlint` + `tsc --noEmit` — clean
  - MCP preview against live Windmill — green
  - `wmill sync push --dry-run` — zero unintended deletions
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip.
