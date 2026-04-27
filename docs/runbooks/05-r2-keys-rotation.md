# R2 keys — provision + rotation

**Type:** ClickOps (Cloudflare dashboard) + sops envelope edit.
**Bucket:** `universe-static-apps-01` (single, prefix-scoped per D8).
**Spec:** ADR-016 §R2 layout; `docs/rfc/gxy-cassiopeia.md` §4.4.

Two role-keys exist on the bucket. They live in different sops envelopes
because the consumers run in different galaxies and different blast-radius
domains.

| Role          | Permission        | Consumer                    | Sops envelope                                                   |
| ------------- | ----------------- | --------------------------- | --------------------------------------------------------------- |
| artemis-admin | Object Read+Write | `artemis` (gxy-management)  | `infra-secrets/management/artemis.env.enc` (dotenv SOT)         |
| caddy-ro      | Object Read       | `caddy-s3` (gxy-cassiopeia) | `infra-secrets/k3s/gxy-cassiopeia/caddy.values.yaml.enc` (yaml) |

Caddy is read-only by design: a compromised caddy pod cannot promote,
rollback, or write artifacts. Artemis holds the only rw key and gates
every write behind GitHub team membership (see
[`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) and ADR-016).

> **Superseded path.** A third role-key — Woodpecker per-site rw bootstrap
> — was specced under T11 / D40. D016 (deploy-proxy plane) supersedes
> that flow: Woodpecker no longer holds R2 credentials; artemis brokers
> every write. Historical T11 mint procedure is archived at
> [`archive/r2-bucket-provision.md`](archive/r2-bucket-provision.md).

---

## Prerequisites

- Cloudflare account owner or admin on the **freeCodeCamp-Universe** account.
- `infra-secrets/` checked out as a sibling of `infra/` with sops+age set
  up — see [`04-secrets-decrypt.md`](04-secrets-decrypt.md).
- `rclone` installed locally (verification only).

---

## Mint a fresh artemis-admin key

Use this on first artemis bring-up or on rotation. Steps 1–4 are
ClickOps; step 5 is the dotenv envelope edit.

### 1. CF dashboard → mint token

1. Cloudflare Dashboard → R2 → **Manage R2 API Tokens** → **Create API Token**.
2. Token name: `universe-static-apps-01-artemis-admin-<YYYYMMDD>` (date suffix lets two coexist during rotation).
3. Permissions: **Object Read & Write**.
4. Specify bucket: `universe-static-apps-01`.
5. TTL: none (rotated every 90 days).
6. **Create** → capture three values shown once:
   - Access Key ID
   - Secret Access Key
   - Jurisdictional endpoint (`https://<account-id>.r2.cloudflarestorage.com`)

### 2. Edit the artemis dotenv envelope

```bash
cd ~/DEV/fCC
sops infra-secrets/management/artemis.env.enc
# Replace these three values:
#   R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
#   R2_ACCESS_KEY_ID=<new key id>
#   R2_SECRET_ACCESS_KEY=<new secret>
```

Save + exit. Sops re-encrypts on close.

### 3. Mirror dotenv → YAML overlay (helm input)

The chart consumes a YAML overlay; the dotenv is the SOT. Re-run the
mirror block from
[`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) §5 to
re-encrypt the YAML overlay.

### 4. Commit + push infra-secrets

```bash
cd infra-secrets
git add management/artemis.env.enc \
        k3s/gxy-management/artemis.values.yaml.enc
git commit -m "chore(artemis): rotate R2 admin key"
# operator pushes
```

### 5. Roll the artemis pods

```bash
cd ~/DEV/fCC/infra
just deploy gxy-management artemis
direnv exec ~/DEV/fCC/infra/k3s/gxy-management \
  kubectl -n artemis rollout status deploy/artemis --timeout=180s
```

### 6. Verify

```bash
curl -fsS https://uploads.freecode.camp/healthz                           # 200
just artemis-postdeploy-check                                             # E2E green
```

See [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md)
for the full E2E gate.

### 7. Revoke old key

CF dashboard → R2 → API Tokens → revoke the prior `*-artemis-admin-*`
token **only after** step 6 is green. Keeping both live during the
soak window means a fast revert if the new key is bad.

---

## Mint a fresh caddy-ro key

### 1. CF dashboard → mint token

1. Cloudflare Dashboard → R2 → **Manage R2 API Tokens** → **Create API Token**.
2. Token name: `universe-static-apps-01-caddy-ro-<YYYYMMDD>`.
3. Permissions: **Object Read** only.
4. Specify bucket: `universe-static-apps-01`.
5. TTL: none.
6. Create → capture credentials.

### 2. Edit the caddy values overlay

```bash
cd ~/DEV/fCC
sops infra-secrets/k3s/gxy-cassiopeia/caddy.values.yaml.enc
# Update keys (YAML, not dotenv):
#   r2:
#     endpoint:        https://<account-id>.r2.cloudflarestorage.com
#     accessKeyId:     <new key id>
#     secretAccessKey: <new secret>
```

### 3. Commit + push

```bash
cd infra-secrets
git add k3s/gxy-cassiopeia/caddy.values.yaml.enc
git commit -m "chore(caddy): rotate R2 ro key"
# operator pushes
```

### 4. Roll caddy pods

```bash
cd ~/DEV/fCC/infra
just helm-upgrade gxy-cassiopeia caddy
direnv exec ~/DEV/fCC/infra/k3s/gxy-cassiopeia \
  kubectl -n caddy rollout restart deploy/caddy
direnv exec ~/DEV/fCC/infra/k3s/gxy-cassiopeia \
  kubectl -n caddy rollout status deploy/caddy --timeout=180s
```

### 5. Verify

Pick any production site (e.g. `https://test.freecode.camp/`) and
confirm 200 + content match. Caddy serves from R2 via the `r2_alias`
module; if the new ro key is bad, expect `502` or `404` on the live
site immediately.

### 6. Revoke old key

CF dashboard → R2 → API Tokens → revoke the prior `*-caddy-ro-*`
token only after the rollout is Ready and a real-site curl is 200.

---

## Cadence

| Key           | Rotation interval | Trigger                                              |
| ------------- | ----------------- | ---------------------------------------------------- |
| artemis-admin | 90 days           | calendar reminder; immediate on suspected leak       |
| caddy-ro      | 90 days           | calendar reminder; immediate on caddy pod compromise |
| Both          | Out-of-cycle      | platform-team lead's discretion (incident response)  |

Both rotations should produce a field-notes entry at
`~/DEV/fCC-U/Universe/spike/field-notes/infra.md` under the
`## Secrets rotation log` heading.

---

## Failure modes

| Symptom                                               | Cause                                            | Fix                                                                           |
| ----------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------- |
| `403 Forbidden` from artemis on `init`/`finalize`     | new key not yet propagated to pods               | re-run rollout; pods pick up new env on restart                               |
| `502 r2_put_failed`                                   | new artemis-admin key revoked early              | mint replacement; re-roll                                                     |
| `404` on production site immediately after caddy roll | new caddy-ro key wrong endpoint or revoked       | check sops envelope; mint replacement                                         |
| `Error unmarshalling input json: invalid character`   | sops auto-detect on `.enc` routed to JSON parser | use canonical incantation in [`04-secrets-decrypt.md`](04-secrets-decrypt.md) |

---

## Cross-references

- [`02-deploy-artemis-service.md`](02-deploy-artemis-service.md) — operator-side artemis lifecycle (sops envelope structure)
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) — E2E gate after rotation
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — canonical sops dotenv decrypt pattern
- [`archive/r2-bucket-provision.md`](archive/r2-bucket-provision.md) — historical bucket-creation steps + superseded T11 Woodpecker rw mint
- ADR-016 — Universe deploy proxy
