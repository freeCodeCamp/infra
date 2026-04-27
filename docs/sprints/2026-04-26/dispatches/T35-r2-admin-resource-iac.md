# T35 — IaC convert R2 admin Resource (`f/ops/r2_admin_s3`)

**Status:** done
**Worker:** w-windmill
**Repo:** `~/DEV/fCC-U/windmill` (branch: `main`)
**Spec source:** T22 dispatch `Operator handoff` step 1 (`docs/sprints/2026-04-26/dispatches/T22-cleanup-cron.md` line 65) — currently labeled "operator-provisioned at runtime" (ClickOps). This dispatch converts step 1 to declarative IaC.
**Depends on:** T22 closed (`windmill@016a868`); cleanup cron flow consumes this Resource via `wmill.getResource("f/ops/r2_admin_s3", true)`.
**Blocks:** T22 live verify (steps 2–4 of T22 operator handoff). G1/G2 unaffected.
**Started:** 2026-04-27
**Closed:** 2026-04-27
**Closing commit(s):** `windmill@8739953` — `feat(admin): add r2_admin_s3 s3 Resource (T35)`; path-drift fix `windmill@7e26390` — `fix(static/cleanup): r2_admin_s3 path → f/ops` (rename `f/admin/` → `f/ops/` + code constant flip).

---

## Why a new dispatch (problem statement)

T22 closed with operator-provisioned Resource via Windmill UI. That violates infra IaC contract:

- No declarative source for the Resource — divergence undetectable by `just drift`.
- R2 admin keys live only in operator browser session; no rotation audit trail.
- Convention elsewhere in repo (`f/github/apollo_11_app.resource.yaml`, `f/apollo/*.variable.yaml`) declares Resources + Variables as sops-encrypted YAML pushed via `wmill sync`.
- `windmill/.sops.yaml` already covers `workspaces/platform/f/.*\.resource\.yaml$` with `encrypted_regex: ^value$` and the org age recipient. Pattern extends to `f/ops/` with zero config change.

Goal: Resource provisioning becomes `git commit` + `just apply`, not browser ClickOps. Schedule flip in T22 step 3 stays ClickOps (acceptable — schedule.yaml `enabled: false` is the IaC default, flip-to-active is operational state, not config).

## Files to land

```
workspaces/platform/f/ops/r2_admin_s3.resource.yaml
```

Single file. No resource-type YAML needed — native `s3` type ships with Windmill (`admins` workspace, cross-workspace). Verified per T22 closure evidence: `bunx wmill resource-type get s3` → fields `bucket/region/endPoint/accessKey/secretKey/pathStyle`.

Folder `workspaces/platform/f/ops/` may not exist yet; `wmill` auto-creates folder objects from path on push. If the linter/metadata tooling complains, add `workspaces/platform/f/ops/folder.meta.yaml` matching sibling folder convention (`f/apollo/folder.meta.yaml`, `f/github/folder.meta.yaml` — copy the shape from one of those).

## Pre-flight (operator one-time, before worker starts)

1. **Mint R2 admin S3 API token** in Cloudflare dashboard:
   - Cloudflare → R2 → Manage R2 API Tokens → Create API Token.
   - Permissions: **Admin Read & Write** (full account-level R2 admin; matches "admin" Resource semantics — bucket lifecycle ops in cleanup cron).
   - Specify bucket: `universe-static-apps-01` only (least-priv within admin tier). If "all buckets" needed for future fan-out, document the choice in the resource description.
   - TTL: no expiry (long-lived; rotate per org policy).
   - Capture: **Access Key ID**, **Secret Access Key**.
2. **Endpoint URL:** `https://ad45585c4383c97ec7023d61b8aef8c8.r2.cloudflarestorage.com` (account ID from `infra/CLAUDE.md` Other state).
3. Hand all three values to worker via secure channel (operator pastes into worker session prompt; NEVER commit plaintext).

## Worker steps (TDD-style: write → encrypt → plan → apply → verify)

### Step 1 — Write plain YAML (will be encrypted in-place)

Create `workspaces/platform/f/ops/r2_admin_s3.resource.yaml`:

```yaml
description: |
  R2 admin S3 credentials (account-level admin token, bucket-scoped to
  universe-static-apps-01). Consumed by f/static/cleanup_old_deploys.ts
  for retention sweep (T22). Native Windmill s3 resource-type — schema
  fields enforced by `bunx wmill resource-type get s3` from admins
  workspace. Replaces D40-era u/admin/cf_r2_provisioner Bearer auth
  (retired post-D43 pivot per ADR-016).
value:
  bucket: universe-static-apps-01
  region: auto
  endPoint: https://ad45585c4383c97ec7023d61b8aef8c8.r2.cloudflarestorage.com
  accessKey: <R2_ADMIN_ACCESS_KEY_FROM_CF_DASHBOARD>
  secretKey: <R2_ADMIN_SECRET_FROM_CF_DASHBOARD>
  pathStyle: true
resource_type: s3
```

Substitute the real `<...>` placeholders. **Do not commit yet.**

### Step 2 — Encrypt in place via sops

```bash
cd ~/DEV/fCC-U/windmill
sops -e -i workspaces/platform/f/ops/r2_admin_s3.resource.yaml
```

Verify `value:` is now `ENC[AES256_GCM,...]` per-key, and a `sops:` footer is appended with `recipient: age1dj2tkgtplys5whp0rnw8kd4ell9m6jgfac5d8m8nprmgap70047sgfjtfr` and `encrypted_regex: ^value$`. Match the shape of `f/github/apollo_11_app.resource.yaml`.

### Step 3 — (If folder missing) seed `folder.meta.yaml`

```bash
ls workspaces/platform/f/ops/folder.meta.yaml || \
  cp workspaces/platform/f/github/folder.meta.yaml \
     workspaces/platform/f/ops/folder.meta.yaml
```

Edit summary/extra_perms in the new file to match `admin` semantics. If `f/apollo/` or `f/github/` folder.meta has acceptable shape, base the copy on whichever is closest in access policy.

### Step 4 — Regen metadata + format

```bash
just meta     # generate-metadata + oxfmt canonical pass
just check    # format-check + lint + test composite gate
```

`just check` MUST pass clean. Resource YAML doesn't have a `.script.lock`, but `just meta` ensures sibling files in the workspace stay coherent.

### Step 5 — Plan (DRY RUN)

```bash
just plan
```

Expected diff: **1 addition** (`f/ops/r2_admin_s3` resource) + **0 deletions** + 0 unintended drift. Optionally 1 folder addition (`f/ops/`) if seeded in step 3.

If output shows deletions or modifications outside `f/ops/`, **STOP** — do not proceed to apply. Investigate drift, run `just pull` to reconcile, redo from step 1 if needed (per global memory: never dismiss sync deletions).

### Step 6 — Apply (REAL push)

```bash
just apply
```

This decrypts → dry-run → push → re-encrypts. Working tree should end clean (`git status` shows only the new file as added; sops re-wrap leaves `value` encrypted at rest).

### Step 7 — Verify Resource live in prod

```bash
bunx wmill resource list 2>/dev/null | grep r2_admin_s3
```

Expected: `f/ops/r2_admin_s3` listed, type `s3`.

Smoke test access (read-only, no mutation):

```bash
bunx wmill resource get f/ops/r2_admin_s3 --workspace platform | head -10
```

Expect non-empty output, `resource_type: s3`. Don't print full body to logs (contains keys).

### Step 8 — Drift check

```bash
just drift
```

Expected: zero drift. If drift reported, capture in HANDOFF — likely benign yaml-quote or whitespace; fix via `just meta` + amend.

### Step 9 — Commit

Per `cmd-git-rules`: title-only conventional commit, stage specific files only.

```
feat(resource/admin): add r2_admin_s3 native s3 Resource (T35)
```

Stage:

```bash
git add workspaces/platform/f/ops/r2_admin_s3.resource.yaml
# only if seeded:
git add workspaces/platform/f/ops/folder.meta.yaml
git add workspaces/platform/f/ops/r2_admin_s3.resource-value.yaml  # if generate-metadata produced one
```

Operator pushes (worker commit-only).

## Acceptance criteria

1. `workspaces/platform/f/ops/r2_admin_s3.resource.yaml` exists, sops-encrypted on `value:`, recipient = org age key.
2. `just check` clean.
3. `just plan` shows 1 addition, 0 unintended deletions.
4. `just apply` succeeds; working tree clean post-push.
5. `bunx wmill resource list` shows `f/ops/r2_admin_s3` type `s3`.
6. `just drift` clean.
7. Commit follows `cmd-git-rules` (title ≤ 50 chars, no body unless "why" not obvious from diff).

## Discipline (carries from T22)

- **No plaintext keys in git history.** If a plain-YAML draft is accidentally staged, `git restore --staged` and rotate the R2 token immediately (assume compromise — the file is in your reflog).
- **Operator pushes** — worker stops at commit.
- **No `bd doctor`** — broken-state recovery via `launchctl kickstart` per global memory feedback.
- **Skill markers:** windmill skills auto-inject on `just meta`; verify `windmill-claude-plugin:resources` skill marker did not need manual stamp on resource.yaml (resource files don't carry skill markers — only scripts do).
- **MCP preview:** unlike T22 cleanup_old_deploys script, Resource files have no executable surface — `runScriptPreviewAndWaitResult` does not apply. Verification = `wmill resource get` + downstream consumer dry-run (T22 step 2 of original handoff).

## Post-T35 (resumes original T22 operator handoff)

After T35 closes, T22 step 2 unblocks (cleanup cron MCP preview with `dry_run=true`). The remaining T22 ClickOps gates (schedule flip + dry_run flip) stay operational state, not IaC.

## Closure (filled on completion)

- **Status:** done
- **Closing commits:**
  - `windmill@8739953` — `feat(admin): add r2_admin_s3 s3 Resource (T35)` — initial landing under `f/admin/` (path matched original dispatch).
  - `windmill@7e26390` — `fix(static/cleanup): r2_admin_s3 path → f/ops` — post-close rename `f/admin/` → `f/ops/` + `cleanup_old_deploys.ts` constant flipped from `u/admin/r2_admin_s3` to `f/ops/r2_admin_s3`. Resolves consumer-vs-resource path drift surfaced during T22 wiring review.
- **Files landed (final):**
  - `workspaces/platform/f/ops/r2_admin_s3.resource.yaml`
  - `workspaces/platform/f/ops/folder.meta.yaml`
- **Acceptance evidence:** `just check` clean; `just plan` 1 add; `just apply` clean; `bunx wmill resource list` shows `f/ops/r2_admin_s3` type `s3`; `just drift` clean.
- **Reviewer gate:** `windmill-reviewer` — verdict CLEAR.
- **Surprises:**
  - **Path drift.** Dispatch authored `u/admin/r2_admin_s3` (user-scope) and filesystem path `f/admin/`. Both updated post-close to `f/ops/r2_admin_s3` (folder-scope) — operator decision; aligns with consumer location (`f/static/cleanup_old_deploys.ts` reads via `wmill.getResource`) and separates ops resources from `u/admin/*` user-scope convention. This dispatch rewritten in place to reflect the final path; commit history (`8739953` → `7e26390`) preserves the original landing → rename trail.
- **Sprint-doc patches owed:** STATUS.md / PLAN.md / HANDOFF.md path refs swept to `f/ops/r2_admin_s3`; commit-message quotes left intact (immutable git history).
