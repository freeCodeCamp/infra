# T17 — universe-cli — Config schema + site name validation

**Status:** pending
**Worker:** w-cli
**Repo:** `~/DEV/fCC-U/universe-cli` (branch: `feat/woodpecker-pivot`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 17](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8.1 + §4.8.5 + D19](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q5 (DNS scheme — informs site-name regex; D19 unchanged)
**Started:** —
**Closed:** —
**Closing commit(s):** —

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

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `pnpm test src/validation src/config` — all green
  - `pnpm typecheck` — clean
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip.
