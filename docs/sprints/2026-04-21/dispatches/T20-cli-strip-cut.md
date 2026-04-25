# T20 — universe-cli — Remove legacy rclone/S3 + release v0.4.0-beta.1

**Status:** pending
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 20](../../architecture/task-gxy-cassiopeia.md)
**RFC:** N/A (cleanup + release)
**QA deltas:** none
**Depends on:** T19 (promote+rollback)
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Files to touch

Per spec §Task 20 § Files. Delete every code path importing
`@aws-sdk/client-s3`, `S3Client`, `createS3Client`, `uploadDirectory`.
Bump `package.json` version to `0.4.0-beta.1`. Update `CHANGELOG.md` +
`README.md` to reflect Woodpecker-owned upload contract.

## Acceptance criteria

Authoritative: spec §Task 20 § Acceptance Criteria. All must pass.
Summary: `pnpm install && pnpm test && pnpm typecheck` exit 0;
`grep -rE 'S3Client|createS3Client|uploadDirectory' src/ --include='*.ts' | grep -v test`
returns no matches; version bumped; CHANGELOG entry present.

## Discipline

- **NO `npm publish`** — operator handles release.
- TDD: deletion-driven; remove imports + run tests; expect green.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.

---

## Closure (filled on completion)

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `pnpm install && pnpm test && pnpm typecheck` — all 0
  - grep for S3 patterns — empty
  - bundle size check (target <850KB) — pass
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip; #25 release dispatch
  unblocks (see `MASTER.md` Phase 2).
