# Runbook — Rotate the Cloudflare origin certificate

**Type:** ClickOps (Cloudflare dashboard) + sops envelope edit. **Zone:** `freecodecamp.net` (Full Strict — see `docs/flight-manuals/UNIVERSE.md` §1.1). **Spec:** `docs/architecture/rfc-secrets-layout.md` D1–D3 (canonical zone-wildcard + per-app override + zone-fallback probe). **Last verified:** 2026-07-05.

The wildcard `*.freecodecamp.net` origin cert lives once, canonically, at `infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` (RFC D1) — this replaced three galaxy-local duplicate copies (`argocd`/`windmill`/`zot` `.tls.*.enc`) that existed pre-RFC. Rotating the canonical pair rotates it for every consumer resolving the wildcard via zone-fallback in one pass. `freecode.camp` (cassiopeia/artemis) is CF Flexible — no origin cert exists on that zone today (`global/tls/freecode-camp.*.enc` is not yet created), so this runbook is scoped to `freecodecamp.net` unless/until that lands.

If instead you're rotating a **per-app override** cert (`k3s/<cluster>/<app>.tls.{crt,key}.enc`, RFC D3 — used only when an app needs a cert distinct from its cluster's zone default), the CF-side steps are identical; swap the destination path in step 2 and the consumer in step 4 for the one app that owns the override.

## Preconditions

- Cloudflare account owner or admin on the account holding the `freecodecamp.net` zone.
- `infra-secrets/` checked out as a sibling of `infra/` with sops+age set up — see [`04-secrets-decrypt.md`](04-secrets-decrypt.md).
- Know which (cluster, app) pairs currently resolve the wildcard via zone-fallback (no per-app override file present). **Windmill retired 2026-07-07** (`docs/runbooks/archive/2026-07-07/12-windmill-decommission.md`) — it was the sole live consumer (`gxy-management`, `cluster.tls.zone` = `freecodecamp-net`, Gateway `certificateRefs: windmill-tls-cloudflare`); that Gateway + Secret are gone with the namespace. There is **no live consumer today**. `argocd`/`zot` remain parked (chart on disk, deploy frozen — RFC D4) and don't currently render a Gateway or Secret either. The cert itself is not retired — keep rotating on schedule so it's ready the moment argocd/zot (or a future galaxy plane on this zone) reactivate.

## Steps

### 1. CF dashboard — mint the replacement Origin Certificate

1. Cloudflare Dashboard → **SSL/TLS** → **Origin Server** → **Create Certificate**.

1. Private key type: RSA (matches the existing envelope; only switch to ECDSA as a deliberate, separate migration).

1. Hostnames: `*.freecodecamp.net`, `freecodecamp.net`.

1. Validity: pick the longest window offered — rotation here is compromise/revocation-driven, not calendar-driven.

1. **Create** → capture the two PEM values shown once (Origin Certificate, Private Key).

   **Verify:** `openssl x509 -in <cert>.pem -noout -subject -dates` shows `*.freecodecamp.net` and a fresh `notBefore`.

### 2. Re-encrypt the canonical envelope pair

`.crt`/`.key` are unrecognized extensions to sops, so both encrypt and decrypt default to its binary store (no `--input-type`/`--output-type` flags needed) — the same bare `sops -d "$file"` shape the `just release` zone-fallback branch already uses.

```bash
cd ~/DEV/fCC
cp <path-to-new-cert>.pem infra-secrets/global/tls/freecodecamp-net.crt
cp <path-to-new-key>.pem  infra-secrets/global/tls/freecodecamp-net.key

sops encrypt --in-place infra-secrets/global/tls/freecodecamp-net.crt
sops encrypt --in-place infra-secrets/global/tls/freecodecamp-net.key

mv infra-secrets/global/tls/freecodecamp-net.crt infra-secrets/global/tls/freecodecamp-net.crt.enc
mv infra-secrets/global/tls/freecodecamp-net.key infra-secrets/global/tls/freecodecamp-net.key.enc
```

**Verify:** `sops -d infra-secrets/global/tls/freecodecamp-net.crt.enc | openssl x509 -noout -dates` shows the new `notBefore`.

### 3. Commit + push infra-secrets

```bash
cd infra-secrets
git add global/tls/freecodecamp-net.crt.enc global/tls/freecodecamp-net.key.enc
git commit -m "chore(tls): rotate freecodecamp-net origin cert"
# operator pushes
```

### 4. Roll every zone-fallback consumer

No live consumer exists today (Windmill retired 2026-07-07 — see Preconditions). The command below is retained as the worked example from when Windmill held the wildcard; it also documents the mechanism zone-fallback consumers rely on, unchanged for whichever app reactivates next.

```bash
cd ~/DEV/fCC/infra
just release gxy-management windmill
```

`kustomize`'s `windmill-tls-cloudflare` secretGenerator uses `disableNameSuffixHash: true` (fixed Secret name, required so the Gateway's static `certificateRefs: windmill-tls-cloudflare` never goes stale) — `kubectl apply -k` updates the Secret's data in place. No pod restart is needed: the cert terminates at the Traefik `Gateway` (`gateway.yaml`), and Traefik's Kubernetes Gateway API provider watches referenced Secrets and hot-reloads the TLS store on change.

If/when argocd or zot reactivate on this zone, repeat `just release gxy-management <app>` for each.

### 5. Verify

No live consumer exists today; the commands below are the worked example against Windmill's former Gateway/domain — substitute the reactivated consumer's namespace/Gateway/hostname once one exists.

```bash
cd ~/DEV/fCC/infra/k3s/gxy-management
export KUBECONFIG=$(pwd)/.kubeconfig.yaml
kubectl get gateway -n windmill windmill-gateway
# windmill-gateway   Programmed=True

echo | openssl s_client -connect windmill.freecodecamp.net:443 \
  -servername windmill.freecodecamp.net 2>/dev/null \
  | openssl x509 -noout -dates -serial
# notBefore/serial match the certificate minted in step 1
```

## Rollback

Prior cert content is recoverable from `infra-secrets` git history (`git show HEAD~1:global/tls/freecodecamp-net.crt.enc`, `...key.enc`). Revert the rotation commit, then re-run step 4. Cloudflare needs no corresponding rollback — leave the old Origin Certificate un-revoked until the new one is confirmed good (step 5), then revoke it from **SSL/TLS → Origin Server**.

## Exit criteria

- `sops -d ... | openssl x509 -noout -dates` on the re-encrypted envelope shows the new `notBefore` + expected SANs.
- `kubectl get gateway -n <consumer-namespace> <consumer-gateway>` → `Programmed=True` (no live consumer today — see Preconditions; skip if none reactivated).
- Live TLS handshake serial (step 5) matches the newly minted cert for every zone-fallback consumer (none live today; was `windmill.freecodecamp.net` pre-retirement).
- Prior Origin Certificate revoked in the CF dashboard only after the above is green.
- `infra-secrets` commit pushed; no plaintext PEM left in shell scrollback or `/tmp`.

## Failure modes

| Symptom                                                            | Cause                                                                                                                                        | Fix                                                                                                                                                                                          |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CF edge returns `525`/`526` after rotation                         | Cert/key mismatch, or the Gateway listener rejected an invalid cert (Traefik takes the whole listener down on a bad `certificateRefs` entry) | Re-check step 2 (cert+key from the same mint); re-decrypt + `openssl x509 -noout -dates` both files                                                                                          |
| `openssl s_client` handshake fails entirely                        | Zone SSL mode dropped from Full Strict, or the Secret never updated                                                                          | Confirm zone mode per `UNIVERSE.md` §1.1; re-run step 4; check `kubectl get gateway -n windmill windmill-gateway -o yaml` conditions                                                         |
| `Error unmarshalling input json: invalid character` on `sops` edit | Operator manually forced `--input-type dotenv` or similar on a `.crt.enc`/`.key.enc` file — these are binary-store, not dotenv               | Use the bare `sops -d`/`sops encrypt --in-place` shape in step 2; see [`04-secrets-decrypt.md`](04-secrets-decrypt.md) for the dotenv-specific pitfall this doesn't apply to                 |
| Old cert still served after `just release`                         | Confirmed a genuine Traefik reload gap, not just propagation delay                                                                           | Check Traefik's `kube-system` pods for TLS-store reload errors; as a last resort, `kubectl -n windmill delete secret windmill-tls-cloudflare` then re-run `just release` to force recreation |

## Cross-references

- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — canonical sops decrypt/edit incantations
- [`05-r2-keys-rotation.md`](05-r2-keys-rotation.md) — sibling rotation runbook (R2 keys), same house shape
- `docs/architecture/rfc-secrets-layout.md` — D1 (single canonical wildcard), D2 (`cluster.tls.zone` marker), D3 (per-app override escape hatch)
- `docs/flight-manuals/UNIVERSE.md` §1 — DNS + Cloudflare baseline, zone SSL matrix
- `docs/flight-manuals/gxy-management.md` §B.2 — existing Gateway/HTTPRoute verify pattern this runbook reuses
