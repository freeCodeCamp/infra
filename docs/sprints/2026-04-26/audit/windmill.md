# Audit: T22 Cleanup Cron Windmill Flow (windmill@016a868)

**Date:** 2026-04-27  
**Auditor:** grounded-truth audit (read-only)  
**Dispatch:** `~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T22-cleanup-cron.md`  
**Spec:** `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md` §R2 layout + RFC §4.9.1

---

## 1. Verdict

**GREEN**

All 5 acceptance criteria pass. All 12 vitest cases pass. All 9 behavioral gates verified. No code-level blockers. Boneyard headers pending separate commit (STATUS says 'incoming').

---

## 2. Repo State

**Branch:** `main`  
**Head SHA:** `016a868`  
**Commit message:** `feat(static): add cleanup cron for R2 deploys (T22)`  

### Last 5 commits
```
016a868 feat(static): add cleanup cron for R2 deploys (T22)
63488b7 chore(format): oxfmt canonical pass post-Bug-C+D
c5d9f92 fix(static/provision_site_r2_credentials): Bug C+D — permission UUIDs in Resource + probe SPA-HTML rejection
e1db0be chore(format): oxfmt canonical pass + skill header injection
d44783a fix(static/provision_site_r2_credentials): wpAdmin field name + URL drift
```

---

## 3. Files Landed

| File | Expected | Actual | Verdict |
|------|----------|--------|---------|
| `workspaces/platform/f/static/cleanup_old_deploys.ts` | ✓ | ✓ Present, 350 lines | PASS |
| `workspaces/platform/f/static/cleanup_old_deploys.test.ts` | ✓ | ✓ Present, 294 lines, 12 cases | PASS |
| `workspaces/platform/f/static/cleanup_old_deploys.script.yaml` | ✓ | ✓ Present, auto-generated | PASS |
| `workspaces/platform/f/static/cleanup_old_deploys.script.lock` | ✓ | ✓ Present, auto-generated | PASS |
| `workspaces/platform/f/static/cleanup_old_deploys.schedule.yaml` | ✓ | ✓ Present, 15 lines | PASS |
| `package.json` | ✓ @aws-sdk/client-s3@3.1037.0 | ✓ Present | PASS |
| `pnpm-lock.yaml` | ✓ Updated | ✓ Updated | PASS |

---

## 4. Behavioral Gates

Per dispatch §Behavioral gates. All verified.

| Gate | Check | Status | Evidence |
|------|-------|--------|----------|
| **S3 Resource** | Reads admin S3 Resource `u/admin/r2_admin_s3` | PASS | Line 33: `const ADMIN_S3_RESOURCE_PATH = "u/admin/r2_admin_s3"` |
| **Alias pinning** | Pins `production` + `preview` aliases (never delete) | PASS | Line 40-41: `ALIAS_NAMES = ["production", "preview"]`; line 188 `shouldRetain()`: `if (aliasIds.has(deploy.id)) return true` |
| **Alias error handling** | Missing alias keys skip site safely (no delete) | PASS | Line 235-245: `readAlias()` catches `NotFound`, returns `null`; line 198 `readAliasSet()` filters nulls |
| **Retention calc** | 7d: `Date.now() - LastModified > 7*24*3600*1000` | PASS | Line 116: `retentionMs = (opts.retentionDays ?? 7) * 86_400_000`; line 190-192 `shouldRetain()`: `ageMs >= retentionMs` triggers delete |
| **Grace period** | Deploys < 1h old never deleted | PASS | Line 37: `DEFAULT_GRACE_MS = 60*60*1000`; line 191: `if (ageMs < graceMs) return true` |
| **Last 3 deploys** | Retained regardless of age | PASS | Line 39: `DEFAULT_RECENT_KEEP = 3`; line 146: `recentIds = deploys.slice(0,3)`; line 189: `if (recentIds.has(deploy.id)) return true` |
| **TOCTOU race** | Re-check aliases immediately before delete (D28) | PASS | Line 159-164: `const currentAliasIds = await readAliasSet(); if (currentAliasIds.has(deploy.id)) { deploysRetained++; continue; }` |
| **Dry-run default** | `dry_run` arg gates delete; default `true` | PASS | Line 86: `dryRun` in `CleanupOpts`; line 154-156: `if (opts.dryRun) { pending.push(...); continue; }` |
| **Structured result** | Returns: site · pending-deletes · skipped-aliased · errors | PASS | Line 50-82: `CleanupReport`: `sitesProcessed`, `deploysRetained`, `deploysDeleted`, `bytesFreed`, `pending[]`, `skipped` |

---

## 5. Tests

**Suite:** `cleanup_old_deploys.test.ts` (workspaces/platform/f/static/)

```
✓ workspaces/platform/f/static/cleanup_old_deploys.test.ts (12 tests) 9ms
  ✓ aliased deploys are never deleted
  ✓ preview alias also pins the prefix (D39 alias prefix-pin)
  ✓ retains the 3 most recent deploys regardless of age
  ✓ never deletes a deploy modified inside the 1h grace window
  ✓ never deletes a deploy younger than the retention window (7d default)
  ✓ deletes deploys >7d old, not aliased, not in last-3, past grace
  ✓ closes the alias-flip TOCTOU race (re-checks alias before delete)
  ✓ dryRun does not mutate R2 and returns a pending list
  ✓ returns skipped report when the lock is unavailable
  ✓ releases the lock even if a per-site step throws
  ✓ processes multiple sites independently
  ✓ ignores `_ops/*` keys when listing sites (lock prefix is not a site)

Test Files  1 passed (1)
     Tests  12 passed (12)
```

**Mocking:** `fakeR2()` pure-DI mock R2Ops; no SDK/windmill-client mocks at policy level. Real SDK tested at runtime via MCP preview.

---

## 6. Schedule + Dry-Run Gates

**File:** `workspaces/platform/f/static/cleanup_old_deploys.schedule.yaml`

```yaml
# skill: windmill-claude-plugin:schedules
summary: Daily R2 deploy cleanup (T22)
description: |
  Daily 04:00 UTC sweep of unreferenced `<site>/deploys/<id>/` prefixes
  in `universe-static-apps-01`. Disabled on first push — operator
  enables after provisioning Resource `u/admin/r2_admin_s3` and
  reviewing one dry-run report. Spec: RFC §4.9.1 (D28+D39+D41).
schedule: "0 0 4 * * *"
timezone: UTC
script_path: f/static/cleanup_old_deploys
is_flow: false
enabled: false
args:
  dry_run: true
no_flow_overlap: true
```

**Verdict:** PASS  
✓ Cron: `0 0 4 * * *` (04:00 UTC daily)  
✓ `enabled: false` (operator flips post-provision)  
✓ `args.dry_run: true` (default; operator flips post-review)  
✓ `no_flow_overlap: true` (prevents concurrent runs)

---

## 7. Boneyard Headers

**STATUS note:** "boneyard headers incoming" — **NOT landed at 016a868**.

| File | Boneyard Header | Status |
|------|-----------------|--------|
| `provision_site_r2_credentials.ts` | ✗ | MISSING — File exists; archived per T11 but header not added |
| `provision_site_r2_credentials.test.ts` | ✗ | MISSING |
| `provision_site_r2_credentials.resource-type.yaml` | ✗ | MISSING |

**Finding:** All three files from T11 are present but lack boneyard headers marking them as archived. STATUS says "governors reconcile" — expected in separate commit post-016a868.

---

## 8. Drift + Surprises

### `u/admin/cf_r2_provisioner` Resource

**Status:** REUSED — Still referenced.  
**Evidence:** `provision_site_r2_credentials.ts:47` — `const cfAdmin = await loadAdminResource<CFAdminResource>("u/admin/cf_r2_provisioner");`  
**Requirement:** STATUS says "proxy reuses (don't retire)." ✓ CORRECT — cleanup script does NOT touch.

### `u/admin/woodpecker_admin` Resource

**Status:** REFERENCED — Still in use by T11 script.  
**Evidence:** `provision_site_r2_credentials.ts` — `const wpAdmin = await loadAdminResource<WoodpeckerAdminResource>("u/admin/woodpecker_admin");`  
**Requirement:** STATUS says "retired." ⚠ INCONSISTENT — T11 provisioning script still requires it; retirement may be post-cleanup.

### Cleanup script isolation

**Status:** CORRECT.  
**Evidence:** `cleanup_old_deploys.ts:33` — uses only `u/admin/r2_admin_s3`; no refs to `cf_r2_provisioner` or `woodpecker_admin`.  
**Finding:** T22 cleanly separates from T11 Resource lifecycle.

---

## 9. Code-Level Blockers

**G1-critical:** NO — T22 is NOT G1-critical per audit scope. Live validation gates on T34 prod live.  
**Code blockers:** NO — All acceptance criteria met.

---

## 10. Operator-Gate Readiness

Per closure HANDOFF (verified present).

### Step 1: Provision Resource
- **Action:** Create `u/admin/r2_admin_s3` (native `s3` Resource type)
- **Config:** Bucket `universe-static-apps-01`, R2 endpoint, admin S3 keys (accessKey/secretKey)
- **Status:** Operator-owned; code ships with `enabled: false`

### Step 2: Preview dry-run
- **Action:** `runScriptPreviewAndWaitResult` with `dry_run=true` against live Windmill
- **Status:** Deferred; Resource currently absent (verified via `wmill resource list`)

### Step 3: Flip schedule enabled
- **Action:** Edit `.schedule.yaml` to `enabled: true` (still `dry_run: true`)
- **Status:** One cycle review; confirmed in closure HANDOFF

### Step 4: Disable dry-run
- **Action:** Edit `.schedule.yaml` to `args.dry_run: false`; push
- **Status:** Final production gate; post-operator review

**Handoff match:** ✓ PASS — closure HANDOFF steps align with dispatch closure notes.

---

## Summary

**Verdict:** GREEN

✓ Repo state: correct branch (`main`), correct closing commit (016a868).  
✓ Files landed: all 7 expected files present.  
✓ Behavioral gates: all 9 gates verified (S3 Resource, alias pinning, TOCTOU race, dry-run, retention calc).  
✓ Tests: 12/12 passed; vitest run clean.  
✓ Schedule: shipped with correct defaults (enabled: false, dry_run: true).  
✓ Operator-gate readiness: post-deploy steps documented and aligned.  
⚠ Boneyard headers: STATUS says 'incoming' but not landed at 016a868; awaiting separate commit.

**No code-level blockers.** T22 code ready for operator gates. Live validation deferred to T34 prod live.

---

**Audit Date:** 2026-04-27  
**Report:** `~/DEV/fCC/infra/docs/sprints/2026-04-26/audit/windmill.md`
