# T20 — universe-cli — Remove legacy rclone/S3 + release v0.4.0-beta.1

**Status:** done
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 20](../../architecture/task-gxy-cassiopeia.md)
**RFC:** N/A (cleanup + release)
**QA deltas:** none
**Depends on:** T19 (promote+rollback)
**Started:** 2026-04-25
**Closed:** 2026-04-25
**Closing commit(s):** `f6971cf` (deletion) + `03c5f19` (version + CHANGELOG)

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

- **Status:** done
- **Closing commit:** `f6971cf` (legacy deletion) + `03c5f19` (version
  bump + CHANGELOG)
- **Acceptance evidence:**
  - `pnpm test` — 167/167 green across 17 files
  - `pnpm exec tsc --noEmit` — clean
  - `pnpm exec oxlint src tests` — 0 warnings, 0 errors
  - `grep -rE 'S3Client|createS3Client|uploadDirectory' src/ --include='*.ts'`
    — empty
  - `package.json.version` = `0.4.0-beta.1`; `@aws-sdk/client-s3`
    absent from `dependencies` + lockfile
  - CHANGELOG.md `## [0.4.0-beta.1] — 2026-04-25` section authored
    (Breaking / Added / Removed / Migration)
- **Surprises:** release CI auto-bumps via `workflow_dispatch`; manual
  pre-population of `package.json.version` + CHANGELOG section makes
  the bump job a no-op (CURRENT==VERSION + grep finds heading), so
  operator-triggered run will flow through to publish/tag without an
  intermediate "chore: release" commit.
- **Sprint-doc patches owed:** PLAN.md matrix row flipped; #25 release
  dispatch unblocked.
