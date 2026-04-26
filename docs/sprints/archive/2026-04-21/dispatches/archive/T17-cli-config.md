# T17 — universe-cli — Config schema + site name validation

**Status:** done
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 17](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.1 + §4.8.5 + D19](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q5 (DNS scheme — informs site-name regex; D19 unchanged)
**Started:** 2026-04-25
**Closed:** 2026-04-25
**Closing commit(s):** `a7dd58e`

---

## Files to touch

Per spec §Task 17 § Files:

- Modify: `src/config/schema.ts` — add `woodpecker: {endpoint, repo_id}`,
  remove `static.rclone_remote` + `static.bucket`
- Modify: `src/config/loader.ts`
- Create: `src/validation/site-name.ts` — regex per RFC §4.8.5
- Create: `src/validation/site-name.test.ts`
- Modify: `src/config/schema.test.ts`

## Acceptance criteria

Authoritative: spec §Task 17 § Acceptance Criteria. All must pass.
Summary: site-name regex `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, max 50
chars, no `--`, RFC-1123 DNS label rules; soft-warn `*-preview` /
`preview-*`; loader rejects legacy `rclone_remote` / `bucket` fields.

## Discipline

- TDD red-green-refactor with table-driven cases.
- vitest + mocked filesystem.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.

---

## Closure (filled on completion)

- **Status:** done
- **Closing commit:** `a7dd58e` (universe-cli)
- **Acceptance evidence:**
  - `pnpm test tests/validation tests/config` — site-name 14, schema 19,
    loader 14 — all green
  - `pnpm exec tsc --noEmit` — clean
- **Surprises:** site-name soft-warn list (`preview-` prefix /
  `-preview` suffix) preserved verbatim from §4.8.5; under D35
  dot-scheme the collision risk diminishes but the warn remains a UX
  guard. No semantic change.
- **Sprint-doc patches owed:** PLAN.md matrix row flipped — done.
