# R2 Bucket Provisioning Runbook — `universe-static-apps-01`

**Task:** T12 (`gxy-static-k7d.13`)
**Spec:** `docs/rfc/gxy-cassiopeia.md` §4.4
**Type:** ClickOps (Cloudflare dashboard) — OpenTofu import post-M5 per ADR-002.

---

## Prerequisites

- Cloudflare account owner or admin access on the **freeCodeCamp-Universe** account
- `infra-secrets/` repo checked out locally and sops+age keys configured
- `rclone` installed locally for the post-provisioning verification
- `scripts/r2-bucket-verify.sh` executable (`chmod +x scripts/r2-bucket-verify.sh`)

---

## Steps

### 1. Create the R2 bucket

1. Cloudflare Dashboard → R2 Object Storage → Create bucket
2. Name: `universe-static-apps-01` (exact match — sequential suffix per D8)
3. Location hint: **EEUR** (Europe, matches DO FRA1)
4. Default storage class: Standard
5. Create bucket

### 2. Enable versioning (§7.4 — data integrity)

Versioning provides a 30-day undelete window against bad cleanup cron or malicious overwrites.

1. Bucket → Settings → Object versioning → Enable
2. Confirm: settings page shows "Object versioning: Enabled"

### 3. Mint read-write access key (Woodpecker, per-site — D22)

**Scope:** organization-wide rw key used only until the per-site token flow (T11) is live. T11 replaces this with per-site path-conditioned tokens.

1. Dashboard → R2 → Manage R2 API Tokens → Create API Token
2. Token name: `universe-static-apps-01-rw-bootstrap`
3. Permissions: **Object Read & Write**
4. Specify bucket: `universe-static-apps-01`
5. TTL: none (rotated every 90 days per rotation procedure below)
6. Create → copy the Access Key ID + Secret Access Key + jurisdictional endpoint URL

Encrypt and store:

```bash
cd ../infra-secrets/gxy-cassiopeia
cat > r2-rw.env <<EOF
R2_ACCOUNT_ID=<copy-from-CF-dashboard>
R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID_RW=<copy>
R2_SECRET_ACCESS_KEY_RW=<copy>
EOF
sops -e -i --input-type dotenv --output-type dotenv r2-rw.env
mv r2-rw.env r2-rw.env.enc
git add r2-rw.env.enc
git commit -m "feat(gxy-cassiopeia): bootstrap R2 rw key"
```

### 4. Mint read-only access key (Caddy)

Caddy pods only read alias files + deploy objects — separate key bounds blast radius of a compromised Caddy pod.

1. Dashboard → R2 → Manage R2 API Tokens → Create API Token
2. Token name: `universe-static-apps-01-ro-caddy`
3. Permissions: **Object Read** only
4. Specify bucket: `universe-static-apps-01`
5. TTL: none (90-day rotation)
6. Create → copy credentials

Encrypt and store:

```bash
cd ../infra-secrets/gxy-cassiopeia
cat > r2-ro.env <<EOF
R2_ACCESS_KEY_ID_RO=<copy>
R2_SECRET_ACCESS_KEY_RO=<copy>
EOF
sops -e -i --input-type dotenv --output-type dotenv r2-ro.env
mv r2-ro.env r2-ro.env.enc
git add r2-ro.env.enc
git commit -m "feat(gxy-cassiopeia): add R2 ro key for Caddy"
```

### 5. Verify

Run the verification script against the new bucket:

```bash
just r2-bucket-verify universe-static-apps-01
```

Expected output: all checks PASS.

If any check fails, DO NOT proceed with dependent tasks (T13 Caddy chart, T14 CF IP refresh, T21 pipeline). Fix the failing check before closing T12.

### 6. Disable public access (confirmation)

R2 buckets default to private. Confirm:

1. Dashboard → `universe-static-apps-01` → Settings → Public access
2. Should read: "Public access: Disabled"
3. Custom domains: none for the bucket itself (Caddy is the only edge).

---

## Rotation (every 90 days)

### rw key rotation

The rw key is rotated by the per-site token flow (T11) once live. Until T11 ships:

1. Mint a new rw token following step 3 with name `universe-static-apps-01-rw-bootstrap-<YYYYMMDD>`.
2. Update `r2-rw.env.enc` in infra-secrets with the new creds (sops -e).
3. Roll Woodpecker repo-secrets via `just woodpecker-secret-rotate`.
4. Revoke the old token from CF dashboard only AFTER the next successful deploy on the new key.

### ro key rotation

1. Mint new ro token following step 4.
2. Update `r2-ro.env.enc` in infra-secrets.
3. Helm upgrade the Caddy chart with the new credentials (chart consumes the sops-decrypted values overlay).
4. `kubectl rollout restart deploy/caddy -n gxy-cassiopeia` — pods pick up new creds on restart per RFC §11.5.
5. Revoke the old token from CF dashboard only AFTER `kubectl rollout status` reports Ready.

Both rotations produce a field-notes entry at `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` under the `## Secrets rotation log` heading.

---

## Exit criteria

- [ ] Bucket `universe-static-apps-01` exists in the freeCodeCamp-Universe CF account
- [ ] Versioning: Enabled
- [ ] `infra-secrets/gxy-cassiopeia/r2-rw.env.enc` committed and sops-decryptable
- [ ] `infra-secrets/gxy-cassiopeia/r2-ro.env.enc` committed and sops-decryptable
- [ ] `just r2-bucket-verify universe-static-apps-01` passes all checks
- [ ] Public access confirmed disabled

Only when all six hold, close T12 in beads:

```bash
bash -c 'source /Users/mrugesh/.claude/plugins/cache/dotplugins/dp-cto/8.0.4/lib/dp-beads.sh && dp_beads_close gxy-static-k7d.13 "completed: bucket + keys + verification green"'
```
