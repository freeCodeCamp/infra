# Session 05 — T22: Cleanup cron Windmill flow

**Beads:** `gxy-static-k7d.23` · **Repo:** `fCC-U/windmill`
**Blocks:** nothing (standalone). **Blocked by:** nothing — parallel-safe at T+0.

## Why this matters

Without cleanup, R2 grows unbounded. D28 specifies a TOCTOU-safe algorithm:
R2 lock + 1-hour grace + pre-delete alias re-check. Critical invariant: never
delete a deploy that a freshly-written alias still references.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC-U/windmill
claude
```

---

## Dispatch prompt

```
You are implementing beads `gxy-static-k7d.23` — T22: Cleanup cron Windmill
flow. Authoritative spec:

- `/Users/mrugesh/DEV/fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.9.1 (D28) — pseudocode is authoritative
- `/Users/mrugesh/DEV/fCC/infra/docs/tasks/gxy-cassiopeia.md` Task 22 (line 3748)
- `dp_beads_show gxy-static-k7d.23`

Read §4.9.1 in full before writing anything.

## Environment

- cwd: `/Users/mrugesh/DEV/fCC-U/windmill`
- Toolchain: Bun, vitest, wmill CLI, oxfmt, oxlint

## Execute in order — strict TDD

1. **RED tests first** — create
   `workspaces/platform/f/static/cleanup_old_deploys.test.ts`. Required cases
   per RFC §4.9.1 + task doc Step 1:
   - keeps deploys referenced by production / preview aliases
   - keeps last 3 deploys regardless of age (D28 "retain at least 3")
   - deletes deploys > 7 days old AND not aliased AND past the 1-hour grace
   - re-checks alias before delete (simulate race: alias moves between list
     and delete — deploy must NOT be deleted)
   - acquires R2 lock before deleting; releases lock on all exit paths
   - dry-run mode prints what WOULD be deleted without side effects
   - fails closed on R2 API error (never delete on uncertainty)
2. **GREEN** — write `workspaces/platform/f/static/cleanup_old_deploys.ts`.
   Inject `r2` client and `now()` for testability.
3. **Flow metadata** via `wmill generate-metadata`. Cron `0 4 * * *` (daily 04:00 UTC).
4. **Resources** — R2 admin credentials Resource (bucket-admin rw, NOT per-site
   path-restricted). Flag to operator that this Resource must be provisioned
   separately and is OFFICE-ONLY (no pipeline should ever reference it).
5. **vitest green, oxlint/oxfmt clean.**
6. **Preview dry-run** — run flow with `dryRun: true` against real R2 bucket.
   Verify it lists candidates without deleting.
7. **`just drift`** — only new files, no deletions.

## Acceptance criteria (RFC + beads)

- D28 algorithm implemented verbatim: lock → list → filter → 1h-grace →
  re-check-alias → delete-with-lock → release-lock
- Aliased deploys never deleted (tests cover race)
- Minimum 3 retained per site (tests cover)
- Dry-run is a no-op on R2 state
- Cron metadata: daily at 04:00 UTC
- Preview run against real R2 reports zero deletions on a healthy bucket (all
  deploys are aliased or within retention)

## TDD

Write failing test first, every single change. If you find yourself writing
production code without a red test, stop and go back.

## Constraints

- Do NOT use `listObjectsV2` without `ContinuationToken` loop — bucket has
  1000+ objects, pagination is mandatory.
- Do NOT delete via `deleteObject` per-key in a tight loop — batch via
  `deleteObjects` (max 1000) for R2 rate-limit friendliness.
- Do NOT hold the R2 lock across network I/O beyond the delete call.
- Do NOT push.

## Output expected

1. Files
2. vitest summary
3. Preview dry-run report
4. `just drift` output
5. Proposed commit message
6. "T22 ready to close" signal

## Commit policy

Prepare commit; do not push.

## When stuck

- If R2 lock primitive doesn't exist yet, use an S3 object with
  `If-None-Match: "*"` atomic-put semantics to implement a lock. This is the
  standard pattern; reference AWS SDK docs via Context7.
- If the "re-check alias" test is flaky, the algorithm has a race — fix the
  algorithm, do not weaken the test.
```

---

## Hand-off

T22 closes independently. No downstream unblocks.
