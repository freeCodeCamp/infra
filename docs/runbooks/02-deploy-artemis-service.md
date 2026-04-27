# Deploy artemis service (Universe deploy proxy)

End-to-end operator runbook for the artemis svc on `gxy-management`.
Public surface: `https://uploads.freecode.camp`. Spec: ADR-016. Sprint
dispatch: `T34-caddy-dns-smoke` (sprint-2026-04-26).

Architecture: see `k3s/gxy-management/apps/artemis/README.md`. No
Tailscale, no Caddy/cassiopeia hop, no CF Access (programmatic API
behind GitHub OAuth Bearer + Traefik rate-limit + CF WAF).

## Preconditions (one-time, ClickOps + secret mint)

### 1. CF DNS A record

| Field | Value                               |
| ----- | ----------------------------------- |
| Zone  | `freecode.camp`                     |
| Name  | `uploads`                           |
| Type  | A                                   |
| Value | gxy-management public IP (any node) |
| Proxy | proxied (orange cloud)              |
| TTL   | auto                                |

Verify: `dig +short uploads.freecode.camp` returns CF anycast IPs.

### 2. CF zone SSL mode (no origin cert at k8s layer)

`freecode.camp` zone is on **Flexible SSL** — CF Edge terminates
HTTPS using Universal SSL; CF→origin is plain HTTP. Matches the
cassiopeia caddy precedent on the same zone. Verify via CF
dashboard → SSL/TLS → Overview — mode = `Flexible`.

No origin cert mint required at the k8s layer; chart Gateway
listener is HTTP :80 only. To flip the zone to Full Strict later,
cassiopeia caddy + artemis charts both need TLS terminator
listeners + sealed origin certs; file as a separate dispatch
(`T-strict-tls`) — out of T34 scope.

### 3. GitHub OAuth App — `Universe CLI`

freeCodeCamp org → Settings → Developer settings → OAuth Apps → New:

- Name: `Universe CLI`
- Homepage URL: `https://uploads.freecode.camp`
- Authorization callback URL: `https://uploads.freecode.camp/oauth/callback` (unused for device flow but field is required)
- **Enable Device Flow** ✅
- Capture `client_id`.

### 4. Mint sops dotenv (SOT) — `infra-secrets/management/artemis.env.enc`

```bash
cp infra-secrets/management/artemis.env.sample \
   infra-secrets/management/artemis.env

# Fill 5 REQUIRED secret values:
#   R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
#   GH_CLIENT_ID, JWT_SIGNING_KEY (`openssl rand -hex 32`)
# Defaults (R2_BUCKET, GH_ORG, etc.) already set.

sops encrypt --in-place infra-secrets/management/artemis.env
mv infra-secrets/management/artemis.env \
   infra-secrets/management/artemis.env.enc

git -C infra-secrets add management/artemis.env.enc
git -C infra-secrets commit -m "feat(management): seal artemis env"
```

Decrypt incantation (canonical):

```bash
sops decrypt --input-type dotenv --output-type dotenv \
  infra-secrets/management/artemis.env.enc
```

Both flags required — sops auto-detect from `.enc` extension falls
back to JSON parser; dotenv envelopes silently fail without explicit
type flags. See `infra/CLAUDE.md` §Secrets.

### 5. Mint sops YAML overlay (helm input) — `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`

The dotenv envelope is the source of truth. The YAML overlay is the
helm input mirror — same secret values in YAML form. One-time mint
(also re-run on env-var rotation, ≤1×/quarter typical). Paste this
block from the infra repo root:

```bash
SOT="../infra-secrets/management/artemis.env.enc"
TGT="../infra-secrets/k3s/gxy-management/artemis.values.yaml.enc"
TMP_DOT=$(mktemp); TMP_YAML=$(mktemp); TMP_ENC=$(mktemp)
trap "rm -f $TMP_DOT $TMP_YAML $TMP_ENC" EXIT
sops -d --input-type dotenv --output-type dotenv "$SOT" > "$TMP_DOT"
{
  echo "# Auto-generated mirror from $SOT. Do NOT hand-edit."
  echo
  echo "secretEnv:"
  while IFS='=' read -r KEY VAL; do
    case "$KEY" in
      R2_ENDPOINT|R2_ACCESS_KEY_ID|R2_SECRET_ACCESS_KEY|GH_CLIENT_ID|JWT_SIGNING_KEY)
        ESC=$(printf '%s' "$VAL" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
        printf '  %s: "%s"\n' "$KEY" "$ESC"
        ;;
    esac
  done < "$TMP_DOT"
} > "$TMP_YAML"
python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$TMP_YAML"
sops --config ../infra-secrets/.sops.yaml \
  --encrypt --input-type yaml --output-type yaml "$TMP_YAML" > "$TMP_ENC"
mv "$TMP_ENC" "$TGT"
echo "Sealed $TGT"
```

No TLS material — CF Flexible SSL on `freecode.camp` (see §2).

After it succeeds, commit the new `.enc` from infra-secrets:

```bash
git -C ../infra-secrets add k3s/gxy-management/artemis.values.yaml.enc
git -C ../infra-secrets commit -m "feat(gxy-management): seal artemis values overlay"
git -C ../infra-secrets push
```

The dotenv stays the SOT — never hand-edit the YAML overlay.

### 6. sites.yaml seed — `freeCodeCamp/artemis` repo

Source of truth: `freeCodeCamp/artemis` `config/sites.yaml`. Initial
seed:

```yaml
sites:
  test:
    teams: ["staff"]
```

PR-reviewed by platform team. Operator pulls the artemis repo locally
on the deploy host so `just deploy gxy-management artemis` can `--set-file` it via `apps/artemis/.deploy-flags.sh`.

```bash
cd ~/DEV/fCC/artemis
git checkout main && git pull --ff-only
```

Override path via `ARTEMIS_REPO=/some/other/path`.

### 7. artemis CI — first GHCR image

```bash
gh workflow run ci.yml --repo freeCodeCamp/artemis --ref main
```

Pin tag + digest in `infra/k3s/gxy-management/apps/artemis/values.production.yaml`:

```bash
docker buildx imagetools inspect ghcr.io/freecodecamp/artemis:<tag>
# copy the sha256:<digest> line
```

Update `image.tag` to `sha-<full-sha>@sha256:<digest>` and commit.

## Deploy

Once all preconditions land:

```bash
cd ~/DEV/fCC/infra
just deploy gxy-management artemis
```

The generic `deploy` recipe smart-dispatches on `apps/<app>/`:

1. Loads chart defaults (`charts/artemis/values.yaml`).
2. Loads production overlay (`apps/artemis/values.production.yaml`).
3. Decrypts + loads sops sealed overlay
   (`infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`).
4. Sources `apps/artemis/.deploy-flags.sh` which appends
   `--set-file sites=$ARTEMIS_REPO/config/sites.yaml` (default
   `$HOME/DEV/fCC/artemis/config/sites.yaml`) to the helm
   invocation.
5. Runs `helm upgrade --install` into the `artemis` namespace.

Optional: `kubectl -n artemis rollout status deploy/artemis --timeout=120s`.

## Verify

```bash
kubectl -n artemis get pods,svc,gateway,httproute
curl -fsS https://uploads.freecode.camp/healthz
# expect: {"ok":true}
```

E2E proxy smoke:

```bash
just phase5-smoke
```

The script init→upload→finalize→preview→promote→prod against the
`test` site, marker-content match on both surfaces, rollback on exit.
Exit 0 on green.

## Rotate

| What rotates                         | Recipe                                                                                                            |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| GH_CLIENT_ID, R2 keys, JWT key       | edit dotenv → `sops -e --in-place`; re-run §5 mint block; `just deploy gxy-management artemis`                    |
| CF zone SSL flip (Flexible → Strict) | out of artemis scope — needs zone-wide change covering cassiopeia caddy too; file as `T-strict-tls` dispatch      |
| sites.yaml                           | PR to artemis repo; merge; `git -C ~/DEV/fCC/artemis pull`; `just deploy gxy-management artemis` (fsnotify ≤1min) |
| Image tag                            | see [§Image update](#image-update-deploy-new-artemis-sha) — full procedure                                        |

## Image update (deploy new artemis SHA)

Use when artemis `main` advances past the deployed pin and the new
SHA must roll into gxy-management. The image pin lives at
`k3s/gxy-management/apps/artemis/values.production.yaml` under
`image.tag` (format: `sha-<full-40-char-sha>@sha256:<digest>`).

### 1. Confirm drift

```bash
kubectl -n artemis get deploy artemis \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
git -C ~/DEV/fCC/artemis log --oneline -1 main
```

If the deployed SHA prefix is not the artemis `main` HEAD, drift is
real — proceed.

### 2. Build GHCR image (if CI did not already on push)

```bash
gh workflow run ci.yml --repo freeCodeCamp/artemis --ref main
gh run watch --repo freeCodeCamp/artemis
```

GHCR tag format on success: `ghcr.io/freecodecamp/artemis:sha-<full-sha>`.

### 3. Resolve digest

```bash
SHA=$(git -C ~/DEV/fCC/artemis rev-parse main)
docker buildx imagetools inspect "ghcr.io/freecodecamp/artemis:sha-${SHA}" \
  | awk '/^Name:|^Digest:/'
```

Copy the `sha256:<digest>` line.

### 4. Bump pin

Edit `k3s/gxy-management/apps/artemis/values.production.yaml`:

```yaml
image:
  repository: ghcr.io/freecodecamp/artemis
  tag: "sha-<FULL_40_CHAR_SHA>@sha256:<DIGEST>"
  pullPolicy: IfNotPresent
```

OCI rule: when both tag and digest are present, digest wins (kubelet
pulls by digest, immutable). Tag retained for human grok in
`kubectl describe pod`.

### 5. Commit

```bash
cd ~/DEV/fCC/infra
git add k3s/gxy-management/apps/artemis/values.production.yaml
git commit -m "chore(artemis): bump image to sha-${SHA:0:7}"
```

Operator pushes.

### 6. Deploy + watch rollout

```bash
just deploy gxy-management artemis
kubectl -n artemis rollout status deploy/artemis --timeout=180s
```

### 7. Verify

```bash
kubectl -n artemis get pods -l app.kubernetes.io/name=artemis
curl -fsS https://uploads.freecode.camp/healthz   # {"ok":true}
just phase5-smoke
```

Phase5 smoke is the authoritative E2E check — green = the new image
serves init/upload/finalize/promote correctly against R2 + GH OAuth.

### Rollback

Revert the `values.production.yaml` commit and re-run `just deploy
gxy-management artemis`. Image is digest-pinned so rollback is
deterministic. No DB / state migration on artemis (stateless svc
over R2).

## Failure modes

| Symptom                                                           | Likely cause                                 | Action                                                               |
| ----------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------- |
| `Error unmarshalling input json: invalid character '#'` from sops | dotenv decrypted without explicit type flags | use the canonical incantation in §4                                  |
| Helm fail with `.Values.secretEnv.X is required`                  | sops overlay missing key                     | re-run §5 mint block (paste-once)                                    |
| Helm fail with `.Values.sites is empty`                           | artemis repo not pulled or wrong path        | `git -C ~/DEV/fCC/artemis pull` or set `ARTEMIS_REPO`                |
| 503 on `uploads.freecode.camp/healthz`                            | Gateway not bound; HTTPRoute not picked up   | `kubectl -n artemis describe gateway,httproute` — check Traefik logs |
| 502 / "no available server" via CF                                | CF zone SSL = Strict + origin no cert        | flip CF zone SSL to Flexible (zone-wide; matches cassiopeia caddy)   |
| ERR_SSL_PROTOCOL_ERROR in browser                                 | CF zone SSL = Off                            | set CF zone SSL to Flexible                                          |
| 429 on bulk upload                                                | rate-limit middleware tripped                | tune `rateLimit.average` / `.burst` in `values.production.yaml`      |

## Cross-references

- ADR-016 — Universe deploy proxy
- `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` §2026-04-26 build-residency, §2026-04-27 RUN-residency clause
- `~/DEV/fCC-U/Universe/decisions/009-...` — Tailscale Operator rejected
- [`01-deploy-new-constellation-site.md`](01-deploy-new-constellation-site.md) — staff-side deploy flow against this service
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) — E2E post-deploy gate
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — canonical sops dotenv decrypt
- [`05-r2-keys-rotation.md`](05-r2-keys-rotation.md) — R2 admin key rotation
- `infra/CLAUDE.md` §Secrets
- `infra/k3s/gxy-management/apps/artemis/README.md`
- `infra/scripts/phase5-proxy-smoke.sh`
