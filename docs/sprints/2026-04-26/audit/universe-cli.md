# Audit: universe-cli feat/proxy-pivot (Sprint 2026-04-26)

## Verdict

**YELLOW** — G1 spec 100% landed; **T32 addendum NOT YET LANDED** (blocks G2 gate). All CLI surface, tests, identity chain, proxy client verified. Addendum bake DEFAULT_GH_CLIENT_ID is the sole blocker per spec.

- T32 main: GREEN. 17 commits, 265/265 tests, 0 lint errors, 0 type errors.
- T33 (platform.yaml v2): GREEN. Schema + v1 migration + docs shipped.
- T32 addendum: RED. src/commands/login.ts:50 still requires env var; no fallback constant.

---

## Branch + Commit State

| Metric | Value |
|--------|-------|
| HEAD SHA | 24d6fa1 (docs: rewrite README + CHANGELOG for v0.4 proxy) |
| Branch | feat/proxy-pivot (off main) |
| Commits ahead | 20 total from main (ccc71ab..24d6fa1 = 17 dispatch commits per spec) |
| Version | 0.4.0-alpha.1 (package.json) |
| Branch origin | Off main — VERIFIED (git merge-base --is-ancestor main feat/proxy-pivot) |

---

## CLI Surface Conformance (Post-Namespace-Pivot)

| Feature | Expected | Actual | Status |
|---------|----------|--------|--------|
| Top-level login | present | src/cli.ts:49 | OK |
| Top-level logout | present | src/cli.ts:61 | OK |
| Top-level whoami | present | src/cli.ts:70 | OK |
| Top-level version | present | src/cli.ts:78 (cli.version()) | OK |
| static group | present | src/cli.ts:36 (args[0] === "static") | OK |
| static deploy --promote --dir | YES | src/cli.ts:40 | OK |
| static promote --from | YES | src/cli.ts:55 | OK |
| static rollback --to | YES | src/cli.ts:66 | OK |
| static ls --site | YES | src/cli.ts:75 | OK |
| --json flag | ALL commands | All 8 commands | OK |
| NO top-level deploy/promote/rollback/ls | MUST NOT exist | Verified absent | OK |

---

## Identity Priority Chain (Q10 / ADR-016)

Implementation: src/lib/identity.ts

| Priority | Slot | Status | File:Line | Notes |
|----------|------|--------|-----------|-------|
| 1 | GITHUB_TOKEN or GH_TOKEN env | OK | identity.ts:24-28 | Direct env lookup |
| 2 | GHA OIDC ACTIONS_ID_TOKEN_REQUEST_TOKEN | OK | identity.ts:30-35 | Implemented; caveat: GitHub API revalidation will reject OIDC token. Documented limitation. |
| 3 | Woodpecker OIDC env | OK | identity.ts:37-39 | Placeholder (never matches in v0.4). Deferred per closure notes. |
| 4 | gh auth token shell-out | OK | identity.ts:41-50 | execFile("gh", ["auth", "token"]) |
| 5 | Device-flow stored token | OK | identity.ts:52-60 | ~/.config/universe-cli/token (loadToken) |

All 5 slots present. Order correct per spec. Tests verify chain: tests/lib/identity.test.ts 17 pass.

---

## T32 Addendum Gap: DEFAULT_GH_CLIENT_ID Bake

**BLOCKER for G2 gate (npm publish).**

Expected state (per addendum 2026-04-27):
- src/commands/login.ts:50 imports DEFAULT_GH_CLIENT_ID constant
- Fallback: env["UNIVERSE_GH_CLIENT_ID"] ?? DEFAULT_GH_CLIENT_ID
- src/lib/constants.ts (NEW): exports const DEFAULT_GH_CLIENT_ID = "Iv23liIuGmZRyPd5wUeN"

Actual state (pre-addendum-fire):
- src/commands/login.ts:50: const clientId = env["UNIVERSE_GH_CLIENT_ID"];
- Exit with EXIT_CONFIG if unset
- NO constants.ts file exists
- NO DEFAULT_GH_CLIENT_ID anywhere in codebase

Impact: universe login fails with "UNIVERSE_GH_CLIENT_ID env var is required" on user laptops. npm published binary unusable out-of-the-box.

Status: KNOWN. Closure notes confirm "single follow-up commit" pending operator approval. Worker task complete; handoff correct.

---

## Proxy Client Endpoints (src/lib/proxy-client.ts)

All 7 endpoints wired per D016 + closure notes. Per-file PUT (not multipart).

| Endpoint | Method | Path | JWT? | Status |
|----------|--------|------|------|--------|
| whoami | GET | /api/whoami | GitHub bearer | OK |
| deployInit | POST | /api/deploy/init | GitHub bearer | OK |
| deployUpload | PUT | /api/deploy/{id}/upload?path=<file> | Deploy JWT | OK (per-file, raw body + query param) |
| deployFinalize | POST | /api/deploy/{id}/finalize | Deploy JWT | OK |
| siteDeploys | GET | /api/site/{site}/deploys | GitHub bearer | OK |
| sitePromote | POST | /api/site/{site}/promote | GitHub bearer | OK |
| siteRollback | POST | /api/site/{site}/rollback | GitHub bearer | OK |

Auth header construction: Authorization: Bearer <token>
Retry: Implemented (3 attempts, exponential backoff on 5xx/429)
Timeout: Configured (30s default)

---

## Build / Test / Lint

Build Output:
- ESM dist/index.js: 47.63 KB OK
- CJS dist/index.cjs: 859.32 KB OK
- tsup v8.5.1: 15ms/70ms OK
- Matches closure-notes expectations

Test Results:
- Test Files: 23 passed
- Tests: 265 passed
- Duration: 1.10s
- All 23 files green, matches spec >= 80% coverage

Lint (oxlint):
- Found 0 warnings and 0 errors
- Finished in 36ms on 48 files with 69 rules
- Clean

Typecheck (tsc --noEmit):
- No output = 0 errors
- Clean. Husky gate works.

---

## T33 — platform.yaml v2

File: src/lib/platform-yaml.ts (parser) + src/lib/platform-yaml.schema.ts (zod schema)
Docs: docs/platform-yaml.md (EXISTS, verified)

Schema (v2, locked per D016):
- site: my-site (required)
- build:
  - command: bun run build (optional)
  - output: dist (optional; defaults shown)
- deploy:
  - preview: true (optional)
  - ignore: gitignore-style (optional)

Removed fields (v1 to v2): r2.*, stack, domain, static, name

v1 Migration Helper:
- detectV1() checks for v1 markers (r2, stack, domain, static, name)
- Error message points users to docs/platform-yaml.md
- User-friendly and correct

Validator:
- parsePlatformYaml(text): ParseResult returns tagged result (no exception)
- Zod validation on parsed YAML
- Field-specific error messages
- Test coverage: 32 tests (platform-yaml.test.ts) — all pass

Documentation:
- docs/platform-yaml.md shipped (T33 closure requirement)
- T32 addendum verified: platform-yaml.md "universe deploy" to "universe static deploy" text fix
- Commits 1b087ab / 4f29379 per closure notes

---

## Husky Pre-Commit Gate

File: .husky/pre-commit

Content:
- pnpm lint
- pnpm typecheck
- pnpm test

Per closure notes: gate gained pnpm typecheck (tsc --noEmit) after 3 type errors slipped through in earlier commits. Fix-up commit ae9c477 + gate commit f7f3b2b included in 17-commit set.

Verification: pnpm typecheck runs clean (0 errors). OK

---

## Drift & Surprises

AWS SDK Cleanup:
- Expected: @aws-sdk/client-s3, @smithy/util-stream, aws-sdk-client-mock, aws-sdk-client-mock-vitest removed
- Actual: grep -i 'aws-sdk|@smithy|aws-sdk-client-mock' package.json = empty OK
- tests/setup.ts: Deleted (was mock extension only) OK
- vitest.config.ts: Reference dropped OK

Woodpecker References:
- Expected: No Woodpecker refs in dist/
- Actual: grep -r 'woodpecker' dist/ = 0 matches OK

Branch Origin:
- Expected: feat/proxy-pivot off main (not archaeology from feat/woodpecker-pivot)
- Actual: git merge-base --is-ancestor main feat/proxy-pivot = YES OK

oxfmt Status:
- Note (closure): oxfmt not installed in package.json. No pnpm fmt command.
- Status: Expected per closure notes ("deferred to TODO-park entry confirmed").
- Implication: oxfmt --check not run; no failure. TODO-park candidate for next sprint.

---

## G1-Blocking Gaps

NONE. T32 main dispatch complete. All acceptance criteria met.

---

## G2-Blocking Gaps

DEFAULT_GH_CLIENT_ID bake (T32 addendum 2026-04-27) — single follow-up commit pending.
- File: src/commands/login.ts (add constant import + fallback)
- File: src/lib/constants.ts (NEW)
- File: package.json / CHANGELOG.md (version bump to 0.4.0-alpha.2)

Blocks npm publish. Addendum is operator-approved per spec; worker noted "waiting on governor session + approval." Expected to land today (2026-04-27) post-audit.

---

## Out-of-Scope / TODO-Park

1. oxfmt installation + pnpm fmt command
   - Deferred per T32 closure ("package never installed").
   - Candidate for next sprint dispatch or tech-debt block.

2. GHA OIDC revalidation gap
   - Slot 2 (GHA OIDC) implemented as placeholder. GitHub API GET /user rejects OIDC ID tokens today.
   - Documented in README + closure notes.
   - Practical workaround: CI supplies GITHUB_TOKEN (slot 1).
   - Requires artemis + GitHub API alignment; parked for future amendment.

3. JWT minting for rate-limit pressure
   - Noted in D016 Consequences. Each request re-validates against cached identity (5-min cache).
   - Long-lived JWT minting deferred to v0.5+ when rate pressure surfaces.

---

## Summary by Scope

| Scope | Status | Dispatch | Commits | Tests | Lint | Type |
|-------|--------|----------|---------|-------|------|------|
| T32 (CLI v0.4 rewrite) | done | Main + addendum-pending | 17 OK | 265/265 OK | 0 err OK | 0 err OK |
| T33 (platform.yaml v2) | done | Closed | (folded into T32) | 32/32 OK | (included) | (included) |

