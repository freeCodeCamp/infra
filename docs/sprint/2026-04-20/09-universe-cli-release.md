# Session 09 — universe-cli: push, live E2E, release v0.4.0-beta.1

**Beads:** `gxy-static-k7d.21` (T20) · **Repo:** `fCC-U/universe-cli`
**Blocks:** nothing (sprint terminal). **Blocked by:** T32, T11, T21, T15.

## Why this matters

Local `main` is 2 commits ahead of `origin/main`. The CODE half of the v0.4
pivot is complete:

- `a7dd58e` — Woodpecker API client + site-name validation + WOODPECKER_TOKEN
  credential resolver + PipelineError/UsageError (T16 + T17 foundation).
- `f6971cf` — deploy/promote/rollback rewritten to trigger Woodpecker
  pipelines; `src/storage/*`, `src/deploy/{upload,metadata,preflight,id,walk}.ts`,
  `src/credentials/resolver.ts` DELETED; `@aws-sdk/client-s3`, `mrmime`,
  `p-limit` REMOVED from deps; bundle shrank 1.95 MB → 812 KB (T18 + T19 +
  T20 code-deletion half).

What is LEFT (the RELEASE half of T20):

1. Push `main` to origin (triggers nothing yet — release gate is the
   `chore(release):` commit)
2. Smoke-test the CLI against LIVE Woodpecker + gxy-cassiopeia (requires
   T32 + T11 + T21 + T15 closed)
3. Bump version `0.3.3 → 0.4.0-beta.1` + add CHANGELOG entry
4. CI OIDC publishes `@freecodecamp/universe-cli@0.4.0-beta.1` to npm

## Start session

```bash
cd /Users/mrugesh/DEV/fCC-U/universe-cli
claude
```

---

## Dispatch prompt

````
You are completing the universe-cli rewrite shipped in beads
`gxy-static-k7d.17..20` (T16-T19 done locally, not pushed) and implementing
`gxy-static-k7d.21` — T20: Remove legacy rclone/S3 + release v0.4.0-beta.1.

Authoritative spec:

- `docs/gxy-cassiopeia-tasks.md` (in this repo) — universe-cli task subset
- `../fCC/infra/docs/tasks/gxy-cassiopeia.md` Task 20 (line 3413)
- `../fCC/infra/docs/rfc/gxy-cassiopeia.md` §4.8 + §7.2 ("no R2 creds on dev machines" invariant)
- `dp_beads_show gxy-static-k7d.21`

## Environment

- cwd: `/Users/mrugesh/DEV/fCC-U/universe-cli`
- Toolchain: pnpm, vitest, tsup, husky, oxlint (from package.json)
- Registry: npm Trusted Publisher (OIDC via GitHub Actions — do NOT publish from local)

## Preconditions — HARD GATES (shell only, no bd)

Verify EACH before continuing. Any failure → STOP and report.

```sh
# 1. Woodpecker reachable + CF Access live
curl -sI https://woodpecker.freecodecamp.net | head -3
# MUST show 302 to *.cloudflareaccess.com

# 2. Per-site R2 secret flow shipped
test -f /Users/mrugesh/DEV/fCC-U/windmill/workspaces/platform/f/static/provision_site_r2_credentials.ts

# 3. Pipeline template shipped
test -f /Users/mrugesh/DEV/fCC/infra/docs/templates/woodpecker-static-deploy.yaml

# 4. Phase 4 smoke script shipped + green (operator provides log path)
test -f /Users/mrugesh/DEV/fCC/infra/scripts/phase4-test-site-smoke.sh

# 5. Local main is 2 ahead of origin/main with the right SHAs
cd /Users/mrugesh/DEV/fCC-U/universe-cli
git log --oneline origin/main..HEAD
# MUST show: f6971cf refactor!: rewrite deploy/promote/rollback ...
#            a7dd58e feat(woodpecker): add API client ...

# 6. Clean tree
git status -sb
# MUST show only "## main...origin/main [ahead 2]"
```

If any check fails, STOP. The release depends on real infra.

## Execute in order

### Phase A — Push the rewrite (T16-T19 upstream)

1. Read the 2 unpushed commits:
   `git log -p origin/main..HEAD` — skim; confirm no secrets, no absolute
   paths, no stale `// TODO: fix before ship` markers.
2. Run full validation pre-push:
   ```bash
   pnpm install  # if lockfile stale
   pnpm typecheck
   pnpm lint
   pnpm test
   pnpm build
   ```
   All must pass. If any fails: STOP. Do not push broken main.
3. Push:
   ```bash
   git push origin main
   ```
4. Confirm CI green on GitHub Actions before moving on.

### Phase B — E2E smoke against live Woodpecker

Create (or reuse) a test constellation repo `freeCodeCamp-Universe/hello-world`
with the `.woodpecker/deploy.yaml` template from T21 copied in.

1. Obtain a Woodpecker API token from
   `https://woodpecker.freecodecamp.net/user/tokens` and export as
   `WOODPECKER_TOKEN`.
2. Run: `universe static deploy --json --target preview`
3. Assert:
   - CLI opens SSE to Woodpecker, streams pipeline logs
   - Pipeline exits 0
   - `https://hello-world--preview.freecode.camp/` returns 200 with expected body
4. Run: `universe static promote --json`
5. Assert `https://hello-world.freecode.camp/` returns the same deploy ID
6. Run: `universe static rollback --confirm --json`
7. Assert production alias reverted

If ANY step fails, the CLI has a bug that predates release. DO NOT proceed to
Phase C. Surface the failure to the operator and open a beads entry.

### Phase C — Confirm T20 code is already in

T20's deletion half is in `f6971cf`. Confirm before touching anything:

```bash
grep -rE 'S3Client|@aws-sdk' src/ --include='*.ts' | grep -v __mocks__ | grep -v redact.ts
# MUST return zero matches (redact.ts has an AWS_KEY_PREFIX_PATTERN literal for
# log masking — that is the only permitted occurrence)

ls src/storage 2>&1 | head -3      # MUST error: No such file or directory
ls src/credentials/resolver.ts 2>&1 # MUST error
ls src/deploy/{upload,metadata,preflight,id,walk}.ts 2>&1 # MUST all error

cat package.json | grep -E 'aws|mrmime|p-limit' # MUST return zero matches
```

If any check fails, T20 deletion drifted — STOP and surface to operator.

### Phase D — Version bump + CHANGELOG

1. Edit `package.json`:
   ```json
   "version": "0.4.0-beta.1"
   ```
2. Add `CHANGELOG.md` entry at the top (after the header, before `## [0.3.3]`):

   ```markdown
   ## [0.4.0-beta.1] — 2026-04-20

   ### Breaking
   - `universe static deploy|promote|rollback` now trigger Woodpecker CI
     pipelines via API. The CLI no longer touches R2 directly.
   - Requires `WOODPECKER_TOKEN` env (create at
     https://woodpecker.freecodecamp.net/user/tokens).
   - `deploy`: drops `--force`, `--output-dir`; adds `--branch`, `--follow`.
     Requires clean git tree.
   - `promote`: drops positional `[deploy-id]`; adds `--follow`.
   - `rollback`: drops `--confirm` + picker; requires
     `--to <YYYYMMDD-HHMMSS-<sha7|dirty-hex8>>`.
   - Config: new required `woodpecker: {endpoint, repo_id}`. Removed
     `static.{rclone_remote,bucket,region}` and
     `UNIVERSE_STATIC_{BUCKET,RCLONE_REMOTE,REGION}` env overrides.

   ### Removed
   - `@aws-sdk/client-s3`, `mrmime`, `p-limit` runtime deps.
   - `src/storage/*`, `src/deploy/{upload,metadata,preflight,id,walk}.ts`,
     `src/credentials/resolver.ts`.

   ### Changed
   - CJS bundle 1.95 MB → 812 KB; ESM 18 KB.
   - SSE log parser accepts `\n\n`, `\r\n\r\n`, `\r\r` separators and
     tolerates malformed JSON frames.

   ### Migration
   - `pnpm install -g @freecodecamp/universe-cli@0.4.0-beta.1`
   - `export WOODPECKER_TOKEN=...`
   - Update `platform.yaml`: add `woodpecker: {endpoint, repo_id}`; remove
     legacy `static.{rclone_remote,bucket,region}`.
   - Copy `.woodpecker/deploy.yaml` from
     [infra docs/templates/woodpecker-static-deploy.yaml](https://github.com/freeCodeCamp/infra/blob/main/docs/templates/woodpecker-static-deploy.yaml).
   - Delete any local R2/rclone credentials previously exported for
     universe-cli.
   ```

3. Re-verify suite:
   ```bash
   pnpm install && pnpm typecheck && pnpm lint && pnpm test && pnpm build
   ```

### Phase E — Release

Release flow uses the `chore(release):` commit convention (see
`ci(release): auto-bump version and CHANGELOG from workflow` on git log).

1. Commit:
   ```bash
   git add package.json CHANGELOG.md
   git commit -m "chore(release): 0.4.0-beta.1"
   ```
2. Push to main:
   ```bash
   git push origin main
   ```
3. CI release job detects the `chore(release):` commit, tags
   `v0.4.0-beta.1`, publishes to npm via OIDC Trusted Publisher. Monitor:
   `gh run watch --exit-status` or GitHub Actions UI.
4. Post-publish verification:
   ```bash
   pnpm dlx @freecodecamp/universe-cli@0.4.0-beta.1 --version
   # prints 0.4.0-beta.1
   ```

## Acceptance criteria

- `origin/main` has the full rewrite + T20 removal + release commit
- GitHub Actions release job green
- `npm view @freecodecamp/universe-cli@0.4.0-beta.1` exists on registry
- E2E smoke against live Woodpecker green (deploy → promote → rollback)
- `grep -rE 'S3Client|@aws-sdk' src/` returns no matches outside tests/mocks/redact
- No `@aws-sdk/client-s3` in `dependencies`
- CHANGELOG documents all breaking changes + migration steps

## TDD

The rewrite (T16-T19) is already committed with tests. T20 is deletion — no
new tests needed. Deletion verification is the grep + the full suite passing
without the removed modules.

## Constraints

- Do NOT publish to npm locally. Trusted Publisher OIDC via GH Actions only.
- Do NOT skip E2E (Phase B). Shipping a broken CLI is worse than shipping
  late.
- Do NOT comment out code — delete.
- Do NOT push to main if any validation (pnpm test/lint/typecheck/build) fails.

## Docs to update (after successful release)

1. **Field notes — Universe repo**:
   `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/universe-cli.md`
   Append `### v0.4.0-beta.1 released (2026-04-20)` with: published SHA,
   npm URL, bundle sizes, any CI/release-pipeline surprises, migration
   notes for staff.
2. **Flight manual — universe-cli repo**:
   `/Users/mrugesh/DEV/fCC-U/universe-cli/docs/FLIGHT-MANUAL.md` — remove
   the "pre-pivot" banner, update install instructions for v0.4.0-beta.1,
   replace deploy/promote/rollback sections with Woodpecker-API flow.
3. **README / CHANGELOG — universe-cli repo**: CHANGELOG already updated
   in Phase D. Update README badges/version if any are pinned.

## Output expected

1. Phase A: push confirmation + CI green URL
2. Phase B: E2E log with three pipeline numbers (deploy, promote, rollback)
3. Phase C: grep output proving no AWS/S3 residue
4. Phase D: diff of package.json + CHANGELOG
5. Phase E: tag URL + `npm view @freecodecamp/universe-cli@0.4.0-beta.1` output
6. Docs diffs (field notes + flight manual)
7. "T20 ready to close" signal
8. Close beads is operator action — NOT agent's job

## Commit policy

Phase A: push only after local validation clean.
Phase D: one commit — `chore(release): 0.4.0-beta.1`.
Phase E: push triggers release via CI. Verify CI success before handing back.

## When stuck

- If E2E deploy fails with `401 unauthorized` from Woodpecker: WOODPECKER_TOKEN
  is wrong or CF Access session cookie is required. Refer to T32 runbook.
- If R2 writes from the pipeline fail: T11 secret provisioning missed a
  permission. Go back and re-run the provisioning flow for the test site.
- If the release CI job fails on "version already exists": someone released
  out-of-band. Reconcile with operator before re-attempting.
- If `grep -rE '@aws-sdk' src/` finds matches after T20 deletions, a file was
  missed — do NOT ship with the grep dirty.
````

---

## Post-session

Sprint done when:

- `@freecodecamp/universe-cli@0.4.0-beta.1` live on npm
- All 10 epic tasks closed in beads
- `bd show gxy-static-k7d` — no open children remain

Final cleanup (manual, outside this session):

1. Operator promotes epic state: `dp_beads_epic_set_stage gxy-static-k7d
reviewing` (or per the dp-cto flow).
2. Operator drafts release-notes post for internal comms.
3. DNS cutover (Phase 6) is scheduled separately — NOT in this sprint.
