# T11 — Per-site R2 secret provisioning Windmill flow

**Status:** pending
**Worker:** w-windmill
**Repo:** `~/DEV/fCC-U/windmill` (branch: `main`) — **NOT** the infra repo
**Spec:** [`task-gxy-cassiopeia.md` §Task 11](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §5.20 D22 + Decision Index D33/D40](../../architecture/rfc-gxy-cassiopeia.md)
**Sprint parent:** [`MASTER.md` → Phase 1 · P1.\*](../MASTER.md)
**QA deltas:** Q1 (alias-write last step), Q2/Q3 (rescoped to D33×2 + D40), Q7 (preview parity), Q8 (7d cleanup pin)
**Predecessor gates passed:** rename done · MASTER shipped · QA Q1–Q8 locked · RFC amendments D33–D40 landed · T32 verified live (org-gate auth, CF Access off) · T17 operator bootstrap (admin Bearer in `infra-secrets/windmill/.env.enc` + Windmill Resource `u/admin/cf_r2_provisioner`)
**Started:** —
**Closed:** —
**Closing commit(s):** —

**This doc is the authoritative dispatch for T11.** Body below is the
deep brief; worker should also cross-read spec + RFC to satisfy ALL
acceptance criteria.

---

## Session bootstrap — run these first

```bash
cd ~/DEV/fCC-U/windmill
claude
```

Then inside the new Claude Code session, paste this entire doc as the
opening prompt.

## ⚠ AMENDMENT 2026-04-25 — read before everything below

This dispatch was authored before `rfc-secrets-layout.md` two-scope
convention was reconciled with sprint Q2/Q3 decisions. Apply these
overrides **everywhere** in this doc:

| Topic                  | Old (this doc)                                                                                               | New (authoritative)                                                                                                                                                                                                                                                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Admin token path       | `infra-secrets/platform/cf-r2-provisioner.secrets.env.enc`                                                   | `infra-secrets/windmill/.env.enc` (with sample-twin in `windmill/.env.sample`) — activates the reserved `windmill/` Universe-platform-app namespace per **D33 amended ×2 2026-04-25**. NOT `global/.env.enc` (that path was an interim 1st-pass amend; rejected because `global/` direnv-loads into operator shell on every `cd infra/`, leaking admin token). |
| Per-site secret path   | `infra-secrets/constellations/<site>.secrets.env.enc`                                                        | **NONE.** Per-site secrets stay in Woodpecker only — per **D40 (supersedes D34)**                                                                                                                                                                                                                                                                              |
| sops `.sops.yaml` rule | author `^constellations/.*\.secrets\.env\.enc$` creation_rule                                                | **DROP.** No new rule — `windmill/.env.enc` already covered by existing repo-wide `path_regex: .*` (single platform age recipient).                                                                                                                                                                                                                            |
| Flow steps             | mint → sops-encrypt → Woodpecker-register → return                                                           | mint → Woodpecker-register → return (no sops write)                                                                                                                                                                                                                                                                                                            |
| Return shape           | includes `secretPath`                                                                                        | drop `secretPath` field                                                                                                                                                                                                                                                                                                                                        |
| Acceptance §D          | sops encryption checks                                                                                       | **OBSOLETE** — flow has no sops step                                                                                                                                                                                                                                                                                                                           |
| Acceptance §F2/F4–F6   | sops file rotation/preserve                                                                                  | **OBSOLETE** — Woodpecker is sole rotation surface (use `PUT` semantics from §F3)                                                                                                                                                                                                                                                                              |
| Acceptance §G1/G2      | sops failure rollback                                                                                        | **OBSOLETE** — only CF mint + Woodpecker register exist                                                                                                                                                                                                                                                                                                        |
| Acceptance §H1         | `secretPath: string`                                                                                         | **DROP field**                                                                                                                                                                                                                                                                                                                                                 |
| Acceptance §I4         | "no plaintext dotenv persists"; "list `constellations/` dir"                                                 | **OBSOLETE** — no dir to list                                                                                                                                                                                                                                                                                                                                  |
| Acceptance §I5         | "sops recipient = platform age only" via `constellations/` smoke                                             | **OBSOLETE** — admin token lives in `windmill/.env.enc`; covered by existing repo-wide `path_regex: .*` rule + single platform age recipient                                                                                                                                                                                                                   |
| Acceptance §J5/J6      | `.sops.yaml` creation_rule + commit                                                                          | **OBSOLETE** — no new rule                                                                                                                                                                                                                                                                                                                                     |
| Operator bootstrap     | `mkdir platform/`, write `cf-r2-provisioner.secrets.env.enc` (4 vars incl. S3 keys)                          | populate the reserved `windmill/` namespace: edit `windmill/.env.sample` (sample-twin), then sops-encrypt to create `windmill/.env.enc` with **2 vars only** (`CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`); S3 admin keys dropped — flow uses Bearer only (see new §below)                                                                                       |
| Commit message hints   | `feat(platform): seed cf-r2-provisioner cred (D33)` / `feat(sops): add constellations/* creation_rule (D34)` | `feat(windmill): seed CF R2 provisioner cred (D33 amended ×2 2026-04-25)`                                                                                                                                                                                                                                                                                      |

Everything else (flow logic, CF API contract, Woodpecker repo-scoped
secrets per D22, site-name regex D19, return shape minus `secretPath`,
test fixtures, MCP preview gate) is **unchanged**.

Source of truth: `docs/architecture/rfc-gxy-cassiopeia.md` D33 + D40 +
"Amendments (2026-04-25)" section. Worker MUST also patch sprint docs
`24-static-apps-k7d.md`, `MASTER.md`, `QA-recommendations.md` paths
during T11 closure (commit-only, no push).

---

## What T11 delivers

A Windmill TypeScript flow that:

1. Mints a **new CF R2 Access Token** scoped by path condition to
   `universe-static-apps-01/<site>/*` only.
2. Registers the minted creds as a **repo-scoped** Woodpecker secret
   (NOT org-scoped — D22). Woodpecker is sole persistence surface
   (D40 / 2026-04-25).
3. Returns deterministic output for `just constellation-register <site>`
   invocation (recipe authored during this task; lands in infra repo).

**Why this matters:** every staff constellation gets its own
bounded-blast-radius credential. A compromised build dep on site A
cannot touch site B's prefix or leak org-wide R2 admin power.

## Locked decisions in scope

Pulled from `infra/docs/sprints/2026-04-21/QA-recommendations.md`
(accepted 2026-04-22) and
`infra/docs/architecture/rfc-gxy-cassiopeia.md` Decision Index
(D33–D39 amendments 2026-04-22).

| Decision                                            | Impact on T11                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **D33 / Q2 (amended ×2 2026-04-25)**                | Admin cred for provisioner lives at `infra-secrets/windmill/.env.enc` (sample-twin in `windmill/.env.sample`) — activates reserved Universe-platform-app namespace per `rfc-secrets-layout.md` D4. Flow reads via Windmill Resource `u/admin/cf_r2_provisioner` (operator seeds it after editing `windmill/.env.enc`). Vars: `CF_R2_ADMIN_API_TOKEN` (CF Account-owned API token, perm `Account → R2 Storage → Edit`) + `CF_ACCOUNT_ID`. **NO S3 admin Access Key / Secret** — flow uses CF Bearer only. **NOT** `global/.env.enc` (that file is direnv-loaded into operator shell — would expose admin token in every `cd infra/`). |
| **D40 (supersedes D34) / Q3 (resolved 2026-04-25)** | Per-site secret persistence = **Woodpecker repo-scoped secret only**. T11 flow does NOT write to infra-secrets. No `constellations/` dir, no `.sops.yaml` rule change. Recovery path = re-mint via CF API. Offline backup deferred to TODO-park.                                                                                                                                                                                                                                                                                                                                                                                     |
| **D38 / Q7**                                        | Preview is MVP-in. R2 path condition must cover **both** `<site>/` (which implicitly includes `<site>/deploys/*` + `<site>/production` + `<site>/preview` objects). Token scope = `<site>/*` covers all.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **D22** (original)                                  | Woodpecker secret is **repo-scoped**, not org-scoped. Flow must call Woodpecker API with repo owner+name, not org.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| **D35 / Q5**                                        | DNS scheme `<site>.freecode.camp` + `<site>.preview.freecode.camp` — not this flow's concern but informs site-name validation (D19 regex unchanged).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

## Files to produce

### In windmill repo (`~/DEV/fCC-U/windmill`)

Create new directory `workspaces/platform/f/static/`:

- `workspaces/platform/f/static/provision_site_r2_credentials.ts`
- `workspaces/platform/f/static/provision_site_r2_credentials.yaml`
- `workspaces/platform/f/static/provision_site_r2_credentials.test.ts`

Optional (helpers only if needed):

- `workspaces/platform/f/static/cf_r2_api.ts` (CF R2 API client helper)
- `workspaces/platform/f/static/cf_r2_api.test.ts`
- `workspaces/platform/f/static/woodpecker_api.ts` (thin HTTP client)
- `workspaces/platform/f/static/woodpecker_api.test.ts`

(`sops_write.ts` + test — **DROPPED 2026-04-25** per D40; flow no longer writes to infra-secrets.)

### In infra repo (`~/DEV/fCC/infra`)

- Modify: `justfile` — add recipe:

  ```just
  # Register a new constellation — mints R2 token, encrypts secret, Woodpecker-registers
  [group('constellations')]
  constellation-register SITE:
      @echo "Registering constellation {{SITE}}"
      wmill workspace sync  # verify no drift first
      wmill run f/static/provision_site_r2_credentials --site={{SITE}}
  ```

### In infra-secrets repo (private sibling, `~/DEV/fCC/infra-secrets`)

**Per D33 amended 2026-04-25:** edit existing `global/.env.sample` +
`global/.env.enc`. No new dirs, no new sops rules.

- Update `global/.env.sample` — add documented section for CF R2
  provisioner (sample-twin discipline; see "Operator bootstrap" below
  for exact stanza).
- Update `global/.env.enc` via `sops global/.env.enc` to add the same
  4 keys with real values minted from Cloudflare dashboard.

`.sops.yaml` requires no change — existing `path_regex: .*` covers
`global/.env.enc` already.

## Toolchain (Windmill repo conventions — 2026-04-08 lock)

**Bun + pnpm + vitest + oxfmt + oxlint + husky.** NOT Deno (bead description
is stale). Verify by reading current repo state:

```bash
cat ~/DEV/fCC-U/windmill/package.json | jq '.scripts, .packageManager, .devDependencies'
cat ~/DEV/fCC-U/windmill/vitest.config.ts
ls ~/DEV/fCC-U/windmill/.husky/
```

Test framework: **vitest with mocked `windmill-client`** (see existing
mocks under `workspaces/platform/__mocks__/` or `__mocks__/`). Follow
same pattern as existing flows under `workspaces/platform/f/github/`,
`f/repo_mgmt/`, etc.

**Preview gate:** before any `just push` / `wmill sync push`, validate
the flow with `runScriptPreviewAndWaitResult` MCP tool against the live
Windmill instance on gxy-management
(`https://windmill.freecodecamp.net`). Catches runtime issues that
local vitest mocks miss.

## Step-by-step plan (TDD discipline)

### 1. Read existing Windmill conventions

```bash
# Study existing flows for Resource patterns, error handling, logging
cat ~/DEV/fCC-U/windmill/workspaces/platform/f/github/create_repo.ts
cat ~/DEV/fCC-U/windmill/workspaces/platform/f/github/create_repo.test.ts
cat ~/DEV/fCC-U/windmill/workspaces/platform/f/github/create_repo.yaml
```

Identify:

- How flows import `windmill-client` (`import * as wmill from "windmill-client@^1"`).
- How flows access Resources (`await wmill.getResource("u/admin/cf_api_token")`).
- How `.yaml` metadata declares schema (input types, summary, description).
- How existing tests mock `windmill-client` (check `__mocks__/` dir).

### 2. Site-name validation (D19 — regex unchanged)

Port/reuse validator:

```ts
const SITE_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/;
// Rejects: leading/trailing `-`, uppercase, underscore, empty.
// Length 3-32 (existing invariant).
```

### 3. Write failing tests first (RED)

`provision_site_r2_credentials.test.ts` — cover:

- Valid site name mints token with path condition `universe-static-apps-01/<site>/*`.
- CF API call body has correct `permissionGroups` (R2 object read+write).
- Woodpecker secret registered with `image: plugins/s3` allowlist empty
  (no image restriction — Q1 pipeline uses native rclone/aws-cli).
- Woodpecker secret scope = **repo**, not org.
- Sops-encrypted file written to correct path
  (`infra-secrets/constellations/<site>.secrets.env.enc`).
- Invalid site name throws; CF/Woodpecker never called.
- CF API failure rolls back (no partial state).
- Woodpecker API failure rolls back CF token too (revoke the minted token).
- Idempotent: re-running for same `<site>` rotates the token, keeps same
  sops path, keeps same Woodpecker secret name.

Use dependency injection pattern (same as existing
`create_repo.ts`) so tests inject `fetchFn` + `sopsFn` mocks instead
of patching module internals.

### 4. Implement to GREEN

Sketch for `provision_site_r2_credentials.ts`:

```ts
import * as wmill from "windmill-client@^1";

export interface ProvisionInput {
  site: string;
  cf_account_id?: string;
  bucket?: string; // default "universe-static-apps-01"
  fetchFn?: typeof fetch; // DI for tests
  sopsFn?: typeof sopsEncrypt;
}

export async function provisionSiteR2Credentials(
  input: ProvisionInput,
): Promise<{
  tokenId: string;
  secretPath: string;
  woodpeckerSecretName: string;
}> {
  const {
    site,
    bucket = "universe-static-apps-01",
    fetchFn = fetch,
    sopsFn = sopsEncrypt,
  } = input;

  if (!SITE_RE.test(site)) {
    throw new Error(`invalid site name: ${site}`);
  }

  // 1. Load admin provisioner token (D33) from Windmill Resource
  const cfAdmin = await wmill.getResource("u/admin/cf_r2_provisioner");
  const accountId = input.cf_account_id ?? cfAdmin.account_id;

  // 2. Mint per-site token (D34 scope)
  const cfRes = await mintR2Token({
    accountId,
    adminToken: cfAdmin.api_token,
    tokenName: `constellation-${site}-rw`,
    bucket,
    pathPrefix: `${site}/`,
    fetchFn,
  });

  try {
    // 3. Encrypt into infra-secrets/constellations/<site>.secrets.env.enc
    const secretPath = `constellations/${site}.secrets.env.enc`;
    await sopsFn(
      secretPath,
      renderDotenv({
        R2_ACCOUNT_ID: accountId,
        R2_ACCESS_KEY_ID: cfRes.accessKeyId,
        R2_SECRET_ACCESS_KEY: cfRes.secretAccessKey,
        R2_BUCKET: bucket,
        R2_SITE_PREFIX: site,
      }),
    );

    // 4. Register repo-scoped Woodpecker secret
    const woodpeckerSecretName = `r2_${site}`;
    await registerWoodpeckerSecret({
      owner: "freeCodeCamp-Universe",
      repo: site, // convention: repo name == site name
      secretName: woodpeckerSecretName,
      secretValue: cfRes.secretAccessKey, // + access-key-id secret as second entry
      fetchFn,
    });

    return { tokenId: cfRes.tokenId, secretPath, woodpeckerSecretName };
  } catch (err) {
    // Rollback: revoke CF token if anything downstream failed
    await revokeR2Token({
      accountId,
      adminToken: cfAdmin.api_token,
      tokenId: cfRes.tokenId,
      fetchFn,
    });
    throw err;
  }
}
```

### 5. Refactor + format

```bash
pnpm oxfmt workspaces/platform/f/static/
pnpm oxlint workspaces/platform/f/static/
pnpm vitest run workspaces/platform/f/static/
```

All three must be green before preview.

### 6. Preview against live Windmill (mandatory)

Use MCP tool (from within Claude Code session):

```
mcp__windmill__runScriptPreviewAndWaitResult
  path: f/static/provision_site_r2_credentials
  args: { site: "test-dispatch-probe", cf_account_id: "<live>" }
```

Abort + debug if preview fails. **Never push without preview green.**

### 7. Push via `wmill sync push`

```bash
cd ~/DEV/fCC-U/windmill/workspaces/platform
wmill sync pull          # confirm clean baseline
wmill sync push --dry-run  # inspect changeset
# CRITICAL: Never dismiss deletion warnings. If sync wants to delete
# anything you did not intend to remove, STOP and diagnose.
wmill sync push
```

### 8. Commit (do NOT push)

Conventional commit:

```
feat(flows/static): T11 — per-site R2 secret provisioning

Implements D22 (repo-scoped), D33 (admin cred path),
D34 (per-site sops path). TDD with vitest + mocked
windmill-client. Preview green against live Windmill
on gxy-management.

Ref: infra sprint 2026-04-21 MASTER Phase 1 · P1.*.
```

Operator pushes.

### 9. Close bead

```bash
# In any repo where dp-beads.sh is sourceable
bash -c 'source /Users/mrugesh/.claude/plugins/cache/dotplugins/dp-cto/8.5.0/lib/dp-beads.sh && dp_beads_close gxy-static-k7d.12 "Shipped in windmill commit <sha>. Flow at f/static/provision_site_r2_credentials. Verified green via runScriptPreviewAndWaitResult against live Windmill. D22 repo-scope + D33 admin path + D34 per-site sops path honored."'
```

## Operator bootstrap (BEFORE T11 starts) — REVISED 2026-04-25 (×3)

**×3 amendment (2026-04-25 evening):** §1 step 5 corrected. Earlier
revisions described the **user-token** form (with `Account Resources`
and `TTL` rows) but routed the operator to the **account-owned-token**
page. Account-owned tokens use a simpler 3-field form: name,
permissions, optional expiration date — nothing else. Disambiguation
note added distinguishing this from the R2-page "Manage API Tokens"
surface (which mints S3-style keys, not the Bearer this flow needs).

The provisioner admin cred lands in `infra-secrets/windmill/.env.enc`
(per D33 amended ×2 — activates the reserved Universe-platform-app
namespace; NOT `global/.env.enc` which would direnv-load into
operator shell on every `cd infra/`). T11 flow needs **only** the CF
Account API Token (Bearer) — it calls
`api.cloudflare.com/client/v4/...` to mint per-site R2 access keys +
registers them as Woodpecker repo secrets.

S3-style admin keys (R2 page → Manage API Tokens → Admin Read & Write)
are NOT needed for T11 and are deliberately out of scope (avoid extra
attack surface; mint later if direct S3 admin ops emerge).

Verified against Cloudflare docs 2026-04-25:

- https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/
- https://developers.cloudflare.com/r2/api/tokens/

### 1. Mint CF Account-owned API Token (REQUIRED)

Requires **Super Administrator** role on the account.

**Disambiguation — two CF surfaces can mint R2-capable creds; we want
the FIRST, not the second:**

- **(this doc — correct)** `Manage Account → Account API Tokens` —
  mints a Bearer `cfat_…` token for `api.cloudflare.com/client/v4/...`
  management calls. The flow uses this Bearer to mint per-site keys
  via `POST /accounts/{id}/r2/buckets/{bucket}/credentials`.
- **(NOT this doc)** `R2 → Overview → Account Details → Manage API Tokens`
  — mints S3-style `Access Key ID` + `Secret Access Key` (with
  permission picker `Admin Read & Write` / `Object Read & Write`
  etc.) for direct S3-SDK calls against
  `<account>.r2.cloudflarestorage.com`. T11 does NOT use this surface.

Steps:

1. Sign in to https://dash.cloudflare.com .
2. Top-right account picker → select the freeCodeCamp Universe account
   (NOT a personal/zone-owner sub-account).
3. **Manage Account** → **Account API Tokens**.
   (Direct nav after step 2: account dropdown → Manage Account → "Account API Tokens" tab.)
4. Click **Create Token**.
5. Fill the form. **Account-owned token form is 3 fields only** —
   simpler than the user-token form. Expect:
   - **Token name:** `r2-provisioner-universe-static-apps-01`
   - **Permissions:** add row → **Account** · **R2 Storage** · **Edit**
     (this lets the token call the R2 management endpoints incl.
     `POST /accounts/{account_id}/r2/buckets/{bucket}/credentials` to
     mint per-site access keys).
   - **Expiration date** (optional): set ~1 year out. If left blank,
     add a rotation reminder to `infra/docs/TODO-park.md`.

   **Do NOT look for** an "Account Resources" picker (token is
   inherently scoped to the account being managed) or a "Client IP
   Address Filtering" / custom "TTL" section. Those rows belong to
   the **user-token** form (`My Profile → API Tokens`) — wrong
   surface for T11. If you see them, you navigated to the user-token
   page; back out and re-enter via Manage Account.

6. **Continue to summary** → review → **Create Token**.
7. **Copy the token value immediately.** It is shown once. The new
   format is `cfat_<random>` (account-owned scannable prefix; CF
   credential scanners auto-detect leaked tokens).

Also grab your **Account ID** while you're there:

- Any dashboard URL contains it: `https://dash.cloudflare.com/<account-id>/...`
- Or: Account Home → right sidebar → **Account ID** (copy icon).
- Format: 32-char hex.

### 2. Author `windmill/.env.sample` (sample-twin discipline)

The reserved `windmill/` namespace exists today as an empty `.env.sample`
stub (per `rfc-secrets-layout.md` D4). T11 is the first activation.

```bash
cd ~/DEV/fCC/infra-secrets
# Replace the empty stub with documented sample (overwrite is fine; it has no real content yet)
cat > windmill/.env.sample <<'SAMPLE'
# =============================================================================
# Reserved namespace: cross-cluster Universe-platform Windmill app secrets
# =============================================================================
# Consumed by Windmill flows running on gxy-management Windmill instance
# (https://windmill.freecodecamp.net). NOT loaded into operator shell env —
# this file is read on-demand by `wmill resource push` / direct sops decrypt
# during operator bootstrap or rotation.
#
# Convention: every `.env.enc` here has a matching `.env.sample` documenting
# every variable, why it exists, where to mint, and the consuming flow path.

# -----------------------------------------------------------------------------
# REQUIRED — Cloudflare R2 Provisioner (D33 amended ×2 2026-04-25; T11)
# -----------------------------------------------------------------------------
# Bearer token consumed by Windmill flow
# `f/static/provision_site_r2_credentials` to mint per-site R2 access keys
# (which become Woodpecker repo secrets — Woodpecker is sole persistence
# per D40).
#
# Mint at: dashboard → Manage Account → Account API Tokens → Create Token
# Permission: Account → R2 Storage → Edit
# Resources:  Specific account = freeCodeCamp Universe
# Format:     cfat_<random>  (account-owned API token prefix)
# Docs:       https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/
CF_R2_ADMIN_API_TOKEN=

# 32-char hex account identifier — copy from any dashboard URL
# (https://dash.cloudflare.com/<this-id>/...) or Account Home sidebar.
CF_ACCOUNT_ID=
SAMPLE
```

### 3. Create `windmill/.env.enc` with real values

```bash
cd ~/DEV/fCC/infra-secrets
# First-time create (file does not exist yet):
cat > windmill/.env <<DOTENV
CF_R2_ADMIN_API_TOKEN=cfat_<paste-real-token>
CF_ACCOUNT_ID=<32-char-hex>
DOTENV

sops -e --input-type dotenv --output-type dotenv \
  windmill/.env > windmill/.env.enc
shred -u windmill/.env 2>/dev/null || rm -P windmill/.env  # macOS uses rm -P
```

For subsequent rotations / additions:

```bash
sops windmill/.env.enc   # opens $EDITOR; edit in place
```

Verify decrypt round-trip without leaking the value:

```bash
sops -d windmill/.env.enc | grep -c '^CF_R2_ADMIN_API_TOKEN='   # → 1
sops -d windmill/.env.enc | grep -c '^CF_ACCOUNT_ID='           # → 1
```

### 4. Commit (no push) per cmd-git-rules

```bash
cd ~/DEV/fCC/infra-secrets
git add windmill/.env.sample windmill/.env.enc
git commit -m "feat(windmill): seed CF R2 provisioner cred (D33 amended x2 2026-04-25)"
# Operator pushes when ready. NEVER auto-push from worker.
```

### 5. Smoke-test the token (≤ 30 seconds)

```bash
TOKEN=$(sops -d ~/DEV/fCC/infra-secrets/windmill/.env.enc | sed -n 's/^CF_R2_ADMIN_API_TOKEN=//p')
ACCT=$(sops  -d ~/DEV/fCC/infra-secrets/windmill/.env.enc | sed -n 's/^CF_ACCOUNT_ID=//p')

# Should return 200 with bucket list (or empty list if no buckets yet)
curl -fsSL \
  -H "Authorization: Bearer $TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCT/r2/buckets" | jq '.success,.result|length'
```

Expected: `true` then a number. If 401/403 → permission missing or
wrong account. If 404 → wrong account ID.

### 6. Register Windmill Resource `u/admin/cf_r2_provisioner`

Either via Windmill UI (Resources → Add Resource → custom type) **or**
via one-off `wmill resource push` from the flow source. Shape (only
what the flow consumes):

```ts
{
  cfApiToken: string; // CF_R2_ADMIN_API_TOKEN — Bearer for api.cloudflare.com
  cfAccountId: string; // CF_ACCOUNT_ID — 32-char hex
}
```

Flow reads this Resource each invocation. No S3 keys, no admin
Access Key ID / Secret Access Key in the Resource (out of scope).

### 7. Acknowledge sprint-doc patches owed

Worker must, as part of T11 closure (commit-only), patch these files
to drop the obsolete `platform/` + `constellations/` references, the
now-removed S3-admin-keys notion, AND the interim `global/.env.enc`
mention (replaced by `windmill/.env.enc`):

- `docs/sprints/2026-04-21/24-static-apps-k7d.md` (Q2/Q3 rows + secrets-layout block)
- `docs/sprints/2026-04-21/MASTER.md` (Q2/Q3 rows + Phase 1 sub-deliverable refs)
- `docs/sprints/2026-04-21/QA-recommendations.md` (append dated amendment block; do NOT rewrite locked Q2/Q3 prose — append-only correction)
- `docs/sprints/2026-04-21/HANDOFF.md` (rolling log entry 2026-04-25 noting D33 amend ×2 + D40 supersede)

## Test data + fixtures

- Use fixed CF API response shapes (snapshot the real API in a recorded
  fixture at `workspaces/platform/f/static/__fixtures__/cf_r2_mint.json`).
- Use fixed Woodpecker API shapes at
  `__fixtures__/woodpecker_secret_create.json`.
- Mock `sopsFn` to return written buffer — do NOT call real sops in
  tests.
- Test `SITE_RE` with table-driven cases: valid (`foo`, `foo-bar`,
  `a1b2c3`), invalid (`-foo`, `foo-`, `foo--bar`, `Foo`, `foo_bar`,
  empty).

## Non-obvious invariants

- **Preview before deploy.** Never `wmill sync push` without
  `runScriptPreviewAndWaitResult` green first.
- **Local test first.** vitest + mocked windmill-client must pass before
  any live call.
- **Never dismiss sync deletions.** `wmill sync push` output flags
  deletes as warnings; ignoring them destroys flows. If surprised, STOP.
- **Repo-scoped Woodpecker secrets** per D22. Use API endpoint
  `POST /api/repos/<owner>/<repo>/secrets` NOT
  `POST /api/orgs/<org>/secrets`.
- **wmill inline-flow filename drift:** if using inline-flow submodules,
  the local filename must match `sanitizeForFilesystem(summary)`
  (wmill-client `main.js:62983`). Otherwise sync shows phantom
  delete+add.
- **sops is stateful:** `sops decrypt --in-place` → mutate → `sops
encrypt --in-place`. Never edit the `.enc` file directly.
- **Windmill repo path** is `~/DEV/fCC-U/windmill` (hyphen U, dash
  windmill). NOT `~/DEV/fCC/windmill` — that stale path appears in the
  bead's original Agent Prompt; ignore it.
- **Operator pushes.** Session commits only; `git push` by operator.

## References

Source of truth + auxiliary:

| Doc                                                             | Role                                                            |
| --------------------------------------------------------------- | --------------------------------------------------------------- |
| `~/DEV/fCC/infra/docs/architecture/rfc-gxy-cassiopeia.md`       | RFC (with 2026-04-22 amendments D33–D39)                        |
| `~/DEV/fCC/infra/docs/architecture/task-gxy-cassiopeia.md`      | Original task breakdown (stale toolchain, useful for structure) |
| `~/DEV/fCC/infra/docs/sprints/2026-04-21/MASTER.md`             | Sprint dispatch checklist                                       |
| `~/DEV/fCC/infra/docs/sprints/2026-04-21/QA-recommendations.md` | Locked decisions                                                |
| `~/DEV/fCC/infra/docs/sprints/2026-04-21/24-static-apps-k7d.md` | Parent #24 dispatch block                                       |
| `~/DEV/fCC/infra/docs/sprints/2026-04-21/HANDOFF.md`            | Session resumption context                                      |
| `~/DEV/fCC-U/Universe/spike/field-notes/windmill.md`            | Windmill operational findings                                   |

## Acceptance criteria (exhaustive)

Every item below is **independently verifiable** and **falsifiable**.
Do not mark T11 closed until every checkbox passes. If any criterion
slips, annotate precisely what and why before closure — do not skip.

### A. Code quality gates

- [ ] **A1** `pnpm vitest run workspaces/platform/f/static/` exits 0
      with ≥ 95 % line coverage across
      `provision_site_r2_credentials.ts` + helpers. Show
      `vitest --coverage` output in closure note.
- [ ] **A2** `pnpm oxfmt --check workspaces/platform/f/static/` exits 0
      (no diff).
- [ ] **A3** `pnpm oxlint workspaces/platform/f/static/` exits 0
      (no warnings, no errors).
- [ ] **A4** `tsc --noEmit` (or `bunx tsc --noEmit`) passes across
      the windmill repo after changes.
- [ ] **A5** No `console.log` statements committed; use
      `wmill.setFlowUserState` / structured return values instead.
- [ ] **A6** All `fetch` call sites are injectable (`fetchFn` param);
      all `sops` call sites injectable (`sopsFn` param). Grep confirms
      no direct `globalThis.fetch` / `Bun.spawn("sops", ...)` calls in
      the main module.
- [ ] **A7** No `any` types in the public API of
      `provision_site_r2_credentials.ts`. `unknown` is acceptable at
      boundaries with runtime narrowing.
- [ ] **A8** Input schema in `provision_site_r2_credentials.yaml`
      matches the TypeScript `ProvisionInput` interface exactly
      (drift prevention). Validate via a yaml-schema ⇄ TS
      parity test (hand-rolled or via `json-schema-to-typescript`).

### B. Site-name validation (D19)

- [ ] **B1** Table-driven test covers **every** valid case:
      `foo`, `foo-bar`, `a1b2c3`, `a1`, `a`, `1`,
      `a-b-c-d-e-f-g-h-i-j-k-l-m-n-o-p` (≤ 32 chars),
      `1a`, `a1`, `hello-world-2026`.
- [ ] **B2** Table-driven test covers **every** invalid case:
      empty string, `-foo`, `foo-`, `--foo`, `foo--bar`, `Foo`,
      `foo_bar`, `foo.bar`, `foo/bar`, `foo bar`, `.foo`, `foo.`,
      33-char string (over limit), non-ASCII (`café`), null byte,
      SQL-injection probe (`foo';DROP`), path-traversal (`../foo`),
      leading space, trailing space.
- [ ] **B3** Validation runs **before** any CF/Woodpecker call
      (ordering test: mocks record zero fetch calls on invalid input).

### C. CF R2 token minting

- [ ] **C1** POST body includes `permissionGroups` containing
      `{ id: "<R2 object read/write permission group UUID>" }`
      — pull real UUIDs from CF API list at flow bootstrap or pin
      them in a fixture.
- [ ] **C2** POST body includes `resources` with path condition
      `com.cloudflare.api.account.<account-id>.r2.bucket.universe-static-apps-01.path.<site>/*`
      — **exact prefix format** verified against live CF API docs.
- [ ] **C3** Token name = `constellation-<site>-rw-YYYYMMDD`
      (date-suffixed for rotation audit).
- [ ] **C4** Token expiry = 90 days (rotation cadence per
      `r2-bucket-provision.md` runbook). Test asserts the request body
      `expires_on` is 90 days from request time ± 1 day.
- [ ] **C5** Test asserts NO other bucket appears in the condition
      (isolation invariant — most dangerous regression).
- [ ] **C6** CF API 4xx response → typed `CFApiError` with status
      code + body preserved in `.cause`.
- [ ] **C7** CF API 5xx response → retried with exponential backoff
      (3 attempts, 1s/2s/4s), then `CFApiError`. Test with
      `fetchFn` returning 503 twice then 200.
- [ ] **C8** Network timeout (simulate with `fetchFn` that never
      resolves) → timeout after 30 s → typed `CFTimeoutError`.
- [ ] **C9** Response parse failure (malformed JSON) → typed
      `CFApiError` with clear message.
- [ ] **C10** Token ID returned is preserved for downstream rollback
      (assert it's in the function's closure before any next step).

### D. Sops encryption step

- [ ] **D1** Dotenv body written contains exactly 5 keys:
      `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
      `R2_BUCKET`, `R2_SITE_PREFIX`. No extra keys, no omissions.
- [ ] **D2** `R2_BUCKET` = `universe-static-apps-01`, exact string.
- [ ] **D3** `R2_SITE_PREFIX` = `<site>` exactly (no trailing `/`).
- [ ] **D4** Dotenv values are not shell-quoted by the writer (sops
      does its own handling).
- [ ] **D5** Output path = `constellations/<site>.secrets.env.enc`
      exactly (test asserts path string).
- [ ] **D6** Sops encrypt call uses `--input-type dotenv
--output-type dotenv`. Verified via `sopsFn` mock arg capture.
- [ ] **D7** Plaintext dotenv is never written to disk outside the
      sops-encrypt call boundary (sopsFn receives the buffer in
      memory; no temp file survives).
- [ ] **D8** If sops binary missing / permission denied, typed
      `SopsError` raised with remediation hint in message.
- [ ] **D9** `.sops.yaml` creation_rule must already be present in
      `~/DEV/fCC/infra-secrets/.sops.yaml` matching
      `^constellations/.*\.secrets\.env\.enc$` with platform age
      recipient. T11 verifies-or-authors this. Test reads the file
      during E2E smoke, not unit test.

### E. Woodpecker secret registration (D22 — repo-scoped)

- [ ] **E1** API endpoint called = `POST /api/repos/<owner>/<repo>/secrets`
      NOT `POST /api/orgs/<org>/secrets`. Grep test confirms no
      `/api/orgs/` substring in any production code path.
- [ ] **E2** `<owner>` = `freeCodeCamp-Universe` (parameterized with
      default; override via `ProvisionInput.woodpeckerOwner`).
- [ ] **E3** `<repo>` = `<site>` (convention: repo name == site name;
      override via `ProvisionInput.woodpeckerRepo`).
- [ ] **E4** Secret is split into two entries: `r2_access_key_id` +
      `r2_secret_access_key`. Names lowercase + underscore — matches
      Woodpecker `from_secret` convention in `.woodpecker/deploy.yaml`
      template (#24 T21).
- [ ] **E5** Secret `events` field = `["push", "manual"]` (no
      `pull_request` — prevents secret leak via fork PRs). Test
      asserts explicit rejection of `"pull_request"`.
- [ ] **E6** Secret `image` field = `[]` (empty allowlist means any
      image can use it; step-level trust from D22). If this changes,
      bump D22 amendment.
- [ ] **E7** Woodpecker API 4xx → typed `WoodpeckerApiError`,
      triggers CF token rollback (see G below).
- [ ] **E8** Woodpecker API 5xx → retried 3× with backoff, then
      `WoodpeckerApiError` + rollback.
- [ ] **E9** Woodpecker auth header = `Authorization: Bearer
<WOODPECKER_ADMIN_TOKEN>` pulled from Windmill Resource
      `u/admin/woodpecker_admin`; test asserts header exactly.
- [ ] **E10** Repo existence probed first: `GET /api/repos/<owner>/<repo>`
      returns 200 before POST. 404 → typed `WoodpeckerRepoMissingError`
      with remediation: "run repo_mgmt.create_repo first".

### F. Idempotency + rotation

- [ ] **F1** Re-running flow for same `<site>` **rotates** the CF
      token (new Access Key ID + new Secret Access Key).
- [ ] **F2** Re-running **preserves** the sops path
      (`constellations/<site>.secrets.env.enc`) — overwrites in place.
- [ ] **F3** Re-running **preserves** Woodpecker secret names;
      uses `PUT /api/repos/<owner>/<repo>/secrets/<name>` or
      delete+recreate to update values.
- [ ] **F4** Stale (previous-rotation) CF token is revoked as the
      last step of successful rotation. Test asserts CF API
      `DELETE /accounts/<id>/tokens/<old-token-id>` was called.
- [ ] **F5** Old token ID is read from the existing sops file before
      revocation; if sops file absent, rotation proceeds without
      revoke + logs a warning (first-run path).
- [ ] **F6** Rotation completes atomically: if CF revoke of old token
      fails, new token still registered; warning emitted; stale
      token flagged in return shape as `staleTokenLeaked: true`.
      Operator can manually revoke.

### G. Rollback semantics

- [ ] **G1** If sops encrypt fails AFTER CF mint: CF token is
      revoked; flow throws. Test asserts CF `DELETE` call was
      issued before throw.
- [ ] **G2** If Woodpecker registration fails AFTER sops write: CF
      token revoked; sops file deleted (or reverted to pre-run
      state if rotation). Test covers both first-run + rotation paths.
- [ ] **G3** If CF revoke-during-rollback fails: rollback still
      continues; error aggregated into a typed
      `RollbackIncompleteError` containing the leaked `tokenId`
      for operator cleanup.
- [ ] **G4** Rollback never deletes the admin provisioner Resource
      (`u/admin/cf_r2_provisioner`). Test asserts zero Resource
      writes.
- [ ] **G5** No partial state on any failure path: either all 3
      artifacts (CF token + sops file + Woodpecker secret) exist,
      or none do.

### H. Return shape + observability

- [ ] **H1** Success return shape exactly:
      `ts
{
  tokenId: string;               // CF token UUID
  accessKeyId: string;           // masked form: "AKIA…3F2C" (first4+last4)
  secretPath: string;            // "constellations/<site>.secrets.env.enc"
  woodpeckerSecretNames: string[]; // ["r2_access_key_id", "r2_secret_access_key"]
  expiresAt: string;             // ISO-8601
  rotated: boolean;              // true if this overwrote prior state
  staleTokenLeaked?: { tokenId: string };
}
`
      Secret Access Key NEVER appears in return shape. Test asserts
      full literal key set, no extras.
- [ ] **H2** Secret Access Key NEVER logged — test scans captured
      log lines for the fixture-mock secret value and asserts 0
      occurrences.
- [ ] **H3** CF token value NEVER logged.
- [ ] **H4** All errors are typed subclasses of a root `T11Error`;
      each has a `retriable: boolean` + `rollbackPerformed: boolean`
      field. Exhaustive test ensures every error thrown type-matches.
- [ ] **H5** Structured flow logs (via `wmill.setFlowUserState` or
      return-shape diagnostics) include: elapsed time per stage,
      CF token ID, secret path, Woodpecker repo, success/failure.

### I. Security invariants (zero-tolerance)

- [ ] **I1** Token path condition regex never allows bucket-wide
      access. Grep test: production code contains no string
      literal `r2.bucket.*` (wildcard bucket) or
      `resources: {}` (empty = account-wide).
- [ ] **I2** Admin provisioner token is read only via
      `wmill.getResource` — never from env, never hardcoded.
      Grep test: no `CF_R2_ADMIN_TOKEN` string literal outside
      the operator-bootstrap dotenv template.
- [ ] **I3** Woodpecker admin token is read only via
      `wmill.getResource` — same invariant.
- [ ] **I4** No plaintext dotenv file persists after the flow
      returns. E2E smoke lists `constellations/` dir: only `.enc`
      files present.
- [ ] **I5** Sops recipient list includes **only** the platform age
      key — no personal age keys. E2E smoke runs `sops -d` with the
      platform key and asserts success; runs with a random key and
      asserts failure.
- [ ] **I6** Token path condition uses exact site prefix — NOT a
      regex, NOT a wildcard like `<site>*` (which would match
      `<site>-evil` sibling prefixes). Fuzz test: provision
      `foo`, attempt writes to `foo-bar/x`, assert 403.
- [ ] **I7** Test asserts `pull_request` events are rejected for the
      Woodpecker secret (see E5) — prevents fork-PR exfil.

### J. Infra-repo deliverables (justfile + sops rule)

- [ ] **J1** `just constellation-register <site>` runs end-to-end
      against a real test site (`test-dispatch-probe`) and returns
      success.
- [ ] **J2** `just --list` shows the recipe under
      `[group('constellations')]`.
- [ ] **J3** `just constellation-register` without args prints
      usage + exits non-zero.
- [ ] **J4** Recipe calls `wmill workspace sync` first to confirm
      no drift, per invariants.
- [ ] **J5** `.sops.yaml` in infra-secrets contains the new
      creation_rule; `sops --encrypt --in-place` on a seeded file
      under `constellations/` succeeds without manual recipient
      override.
- [ ] **J6** `.sops.yaml` change committed (not pushed) with
      message matching `feat(sops): add constellations/* creation_rule (D34)`.

### K. Live verification (MCP preview + smoke)

- [ ] **K1** `runScriptPreviewAndWaitResult` MCP tool invocation
      against live Windmill on gxy-management returns success
      for valid input.
- [ ] **K2** Preview output includes non-null `tokenId`,
      `secretPath`, `woodpeckerSecretNames[]`.
- [ ] **K3** Preview output does NOT contain the plaintext secret
      access key (check preview JSON payload literally).
- [ ] **K4** Live CF API check: `curl` with the minted token can
      `PUT` to `universe-static-apps-01/<site>/smoke-probe.txt`.
- [ ] **K5** Live CF API check: same token CANNOT `PUT` to
      `universe-static-apps-01/<other-site>/smoke-probe.txt`
      (expect 403).
- [ ] **K6** Live Woodpecker check: `GET /api/repos/<owner>/<site>/secrets`
      lists both secret names.
- [ ] **K7** Live sops check: `sops -d constellations/<site>.secrets.env.enc`
      on operator machine decrypts cleanly.
- [ ] **K8** Cleanup: all K1–K7 artifacts removed after smoke —
      CF token revoked, sops file deleted, Woodpecker secrets
      deleted, R2 smoke-probe object deleted.

### L. Sync + commit hygiene

- [ ] **L1** `wmill sync push --dry-run` shows **zero** unintended
      deletions. If any appear, STOP, diagnose, document in
      field-notes before proceeding.
- [ ] **L2** Pre-commit hook (husky) passes: oxfmt + oxlint + vitest.
- [ ] **L3** Commit message follows conventional commits
      (`feat(flows/static): T11 …`).
- [ ] **L4** Commit body references: bead ID, sprint + MASTER phase,
      D22/D33/D34 locked decisions.
- [ ] **L5** No `.env` files, no `*.secrets.env` (un-encrypted)
      files, no tmp test artifacts in the commit. `git show --stat`
      output inspected.
- [ ] **L6** No `co-authored-by` lines (per user settings).
- [ ] **L7** Not amended; not force-pushed; operator pushes.

### M. Bead + docs closure

- [ ] **M1** Bead `gxy-static-k7d.12` closed with reason that names:
      windmill commit sha, infra commit sha (justfile),
      infra-secrets commit sha (.sops.yaml), D22/D33/D34 honored,
      K4+K5 smoke evidence summary.
- [ ] **M2** `Universe/spike/field-notes/windmill.md` updated with a
      new journal entry documenting anything surprising encountered
      during T11 (API quirks, CF rate limits, Woodpecker auth
      gotchas). Append-only; preserve format.
- [ ] **M3** `infra/docs/sprints/2026-04-21/MASTER.md` Phase 1 P1.1
      line ticked (mark T11 portion done).
- [ ] **M4** `infra/docs/sprints/2026-04-21/24-static-apps-k7d.md`
      sub-task matrix row `.12 T11` status updated.
- [ ] **M5** Dispatch doc (`windmill-t11-dispatch.md`) closing
      addendum added at bottom: "Closed <date> in windmill
      commit <sha>. Notes: <surprises, if any>."

### N. Failure-mode documentation

Before closure, verify the runbook portion of this dispatch
addresses each failure mode **explicitly** (what operator should do):

- [ ] **N1** Flow fails midway → where to look first (flow run URL,
      Windmill logs).
- [ ] **N2** CF revoke fails → how to manually revoke via CF
      dashboard with just `tokenId`.
- [ ] **N3** Sops file corrupt / unreadable → how to regenerate from
      a fresh rotation.
- [ ] **N4** Woodpecker repo missing → how to create it + re-invoke.
- [ ] **N5** Rate limited on CF API → back-off guidance + when to
      expect self-heal.
- [ ] **N6** Wrong age recipient in `.sops.yaml` → how to rotate all
      constellations to new recipient.

---

**Closure procedure:** every checkbox above must pass. Attach
evidence (command output excerpts, test run summary, CF dashboard
screenshot reference, Woodpecker secret list snippet) to the bead
closure note. Do NOT close on trust — close on evidence.

## What happens after T11 closes

Next in MVP chain per `24-static-apps-k7d.md`:

- **T21**: `.woodpecker/deploy.yaml` pipeline template —
  consumes per-site credential provisioned by T11.
- universe-cli lane T16–T20 can start in parallel (no dep on T11).

---

## Closure (filled on completion)

- **Status:** —
- **Closing commit(s):** windmill@—, infra@— (justfile recipe), infra-secrets@— (none if D40 honored)
- **Acceptance evidence:**
  - `pnpm test workspaces/platform/f/static/` — all green (≥95% line coverage)
  - `pnpm oxfmt --check` + `pnpm oxlint` + `tsc --noEmit` — clean
  - `runScriptPreviewAndWaitResult` MCP against live Windmill — green
  - `wmill sync push --dry-run` — zero unintended deletions
  - Live K1–K7 smoke probe — all pass
  - K8 cleanup — CF token revoked, Woodpecker secrets deleted, R2 probe object deleted
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip in `24-static-apps-k7d.md`
  - closure note in `HANDOFF.md` rolling log + `Universe/spike/field-notes/windmill.md` journal entry.
