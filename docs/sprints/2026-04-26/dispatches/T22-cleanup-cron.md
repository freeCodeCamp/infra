# T22 — Cleanup cron Windmill flow

**Status:** done
**Worker:** w-windmill
**Repo:** `~/DEV/fCC-U/windmill` (branch: `main`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 22](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.8 cleanup + ADR-007 retention](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q7 (preview pinned), Q8 (hard 7d retention)
**Depends on:** D41 admin S3 Resource (`u/admin/r2_admin_s3`, native `s3` type) — operator-provisioned at runtime; D40-era `u/admin/cf_r2_provisioner` Bearer dep dropped post-D43 pivot.
**Started:** 2026-04-27
**Closed:** 2026-04-27
**Closing commit(s):** `windmill@016a868` — `feat(static): add cleanup cron for R2 deploys (T22)`

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

- **Status:** done
- **Closing commit:** `windmill@016a868` — `feat(static): add cleanup cron for R2 deploys (T22)`
- **Files landed (windmill repo):**
  - `workspaces/platform/f/static/cleanup_old_deploys.ts` — pure-DI policy + S3-SDK-backed `R2Ops` impl + `main(dry_run)` entry.
  - `workspaces/platform/f/static/cleanup_old_deploys.test.ts` — 12 vitest cases (alias pin, recent-3, grace, retention, TOCTOU, dryRun, lock-busy, finally-release, multi-site, `_ops/*` filter).
  - `workspaces/platform/f/static/cleanup_old_deploys.script.yaml` + `.script.lock` — wmill metadata (auto-generated).
  - `workspaces/platform/f/static/cleanup_old_deploys.schedule.yaml` — daily `0 0 4 * * *` UTC, `enabled: false`, `args.dry_run: true`, `no_flow_overlap: true`.
  - `package.json` + `pnpm-lock.yaml` — `@aws-sdk/client-s3@3.1037.0` added via `pnpm add`.
- **Acceptance evidence:**
  - `bun run --bun vitest run` — 30 files, 412 tests passed (12 new for T22).
  - `bunx oxfmt --check` + `bunx oxlint` — clean.
  - `bunx tsc --noEmit` — 38 pre-existing errors in unrelated files (google_chat / lib/approval / ops / repo_mgmt); zero new errors in T22 files (verified via stash diff).
  - `wmill sync push --dry-run` (via `just plan`) — 4 additions, 0 deletions, 0 unintended drift.
  - MCP preview against live Windmill — **DEFERRED** to operator post-deploy gate. Blocks on operator provisioning Resource `u/admin/r2_admin_s3` (currently absent — verified via `bunx wmill resource list`). Schedule ships `enabled: false` so this is safe to land code-only.
- **Reviewer gate:** `windmill-reviewer` run — verdict **CLEAR**, 0 mandatory findings, 3 advisory (A1 atomic CAS lock via `IfNoneMatch: "*"` — applied; A2 schedule.yaml skill marker — applied; A3 Resource artifact runbook — operator-owned).
- **Primitives evidence carried:**
  - Skill markers: `cleanup_old_deploys.ts` line 1 → `windmill-claude-plugin:write-script-bun`; `.schedule.yaml` line 1 → `windmill-claude-plugin:schedules`; `wmill.getResource(path, true)` documented in `node_modules/windmill-client/dist/client.mjs:43-58` (404 → undefined safe-probe).
  - Empirical: native `s3` resource-type schema captured via `bunx wmill resource-type get s3` (workspace `admins` cross-workspace; fields `bucket/region/endPoint/accessKey/secretKey/pathStyle`); remote workspace inventory confirms 3 existing Resources, none of type `s3`.
- **Surprises:**
  - Spec test case "dryRun does not delete" wants a deletion to occur in the pending list, but the spec's own retention policy ("keep last 3 regardless of age") pins the only deploy of a single-deploy site. Tests fixed by adding 3 filler deploys so the target falls out of the recent-3 window. Same fix applied to the multi-site test.
- **Operator handoff (post-T31 gates):**
  1. Provision Resource `u/admin/r2_admin_s3` (native `s3` type) with admin S3 keys for `universe-static-apps-01` (R2 endpoint + access/secret).
  2. `mcp__windmill-platform__runScriptPreviewAndWaitResult` with `dry_run=true` against live Windmill — confirm pending list shape.
  3. Flip schedule `enabled: true` (still `dry_run=true`) for one cycle. Review Slack/Chat report.
  4. After dry-run review, edit `.schedule.yaml` to `args.dry_run: false`, push.
- **Sprint-doc patches owed:** matrix row flip in `PLAN.md`; HANDOFF entry — governor reconciles.
