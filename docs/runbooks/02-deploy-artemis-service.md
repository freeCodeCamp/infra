# Deploy artemis service (Universe deploy proxy)

End-to-end operator runbook for the artemis svc on `gxy-management`. Public surface: `https://uploads.freecode.camp`. Spec: ADR-016.

Architecture: see `k3s/gxy-management/apps/artemis/README.md`. No Tailscale, no Caddy/cassiopeia hop, no CF Access (programmatic API behind GitHub OAuth Bearer + Traefik rate-limit + CF WAF).

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

`freecode.camp` zone is on **Flexible SSL** — CF Edge terminates HTTPS using Universal SSL; CF→origin is plain HTTP. Matches the cassiopeia caddy precedent on the same zone. Verify via CF dashboard → SSL/TLS → Overview — mode = `Flexible`.

No origin cert mint required at the k8s layer; chart Gateway listener is HTTP :80 only. To flip the zone to Full Strict later, cassiopeia caddy + artemis charts both need TLS terminator listeners + sealed origin certs; file as a separate dispatch (`T-strict-tls`) — out of T34 scope.

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

Both flags required — sops auto-detect from `.enc` extension falls back to JSON parser; dotenv envelopes silently fail without explicit type flags. See `infra/CLAUDE.md` §Secrets.

### 5. Mint sops YAML overlay (helm input) — `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`

The dotenv envelope is the source of truth. The YAML overlay is the helm input mirror — same secret values in YAML form. One-time mint (also re-run on env-var rotation, ≤1×/quarter typical). Paste this block from the infra repo root:

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

### 6. Bootstrap the sites registry

Source of truth is Valkey, not a file. On a fresh cluster the registry starts empty; seed it with the `test` slug (smoke-target reserved for the post-deploy E2E suite) plus any production slugs:

```bash
universe sites register test --team staff
# Production slugs once you're past preconditions:
# universe sites register hello-universe --team bots,staff
# universe sites register <slug> --team <team>[,<team>...]
```

The CLI POSTs `/api/site/register` against artemis; staff-team membership gates writes (`REGISTRY_AUTHZ_TEAM` chart env, default `staff`). Cold-start reference: `freeCodeCamp/artemis` `config/sites.yaml` is a **dormant seed** of the historical map — not consumed at runtime; only useful when replaying entries after a full Valkey wipe.

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
just release gxy-management artemis
```

The generic `deploy` recipe smart-dispatches on `apps/<app>/`:

1. Loads chart defaults (`charts/artemis/values.yaml`).
1. Loads production overlay (`apps/artemis/values.production.yaml`).
1. Decrypts + loads sops sealed overlay (`infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`).
1. Runs `helm upgrade --install` into the `artemis` namespace.

Optional: `kubectl -n artemis rollout status deploy/artemis --timeout=120s`.

## Verify

```bash
kubectl -n artemis get pods,svc,gateway,httproute
curl -fsS https://uploads.freecode.camp/healthz
# expect: {"ok":true}
```

Confirm the running version + commit via the startup banner:

```bash
kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=15m \
  | grep "starting version"
```

Expected: `artemis: starting version=<semver-or-sha-or-branch> commit=<full-sha>` one line per replica. `VERSION` reflects the tag that triggered the build (semver on tag push, `sha-<sha>` on `workflow_dispatch`, branch name on branch push); `COMMIT` is the full sha. Both embedded via `-ldflags -X main.version=… -X main.commit=…` at build time.

E2E proxy smoke:

```bash
just verify-artemis
```

Recipe wraps `make integration` against the deployed artemis (see `docs/runbooks/03-artemis-postdeploy-check.md` for the full suite shape): init→upload→finalize→preview→promote→prod against the `test` site, marker-content match on both surfaces, rollback on exit. Exit 0 on green.

## Rotate

| What rotates                         | Recipe                                                                                                                         |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| GH_CLIENT_ID, R2 keys, JWT key       | edit dotenv → `sops -e --in-place`; re-run §5 mint block; `just release gxy-management artemis`                                |
| CF zone SSL flip (Flexible → Strict) | out of artemis scope — needs zone-wide change covering cassiopeia caddy too; file as `T-strict-tls` dispatch                   |
| sites registry entries               | `universe sites register/update/rm <slug> …` (staff-gated; live in seconds via `registry.changed` pub-sub, ≤60 s TTL fallback) |
| Image tag                            | see [§Image update](#image-update-deploy-new-artemis-release) — full procedure                                                 |

## Image update (deploy new artemis release)

Use when a new artemis release lands and must roll into gxy-management. Releases are tag-triggered: an operator with push rights to `freeCodeCamp/artemis` cuts a `vX.Y.Z` annotated tag per artemis `RELEASING.md`; `.github/workflows/docker-ghcr.yml` fires automatically on the tag push, builds the image, publishes to GHCR with tags `X.Y.Z` (bare semver, no `v`-prefix — docker/metadata-action strips it; OCI convention is bare semver), `X.Y`, and `sha-<full-sha>`, and auto-publishes a GitHub Release.

The image pin lives at `k3s/gxy-management/apps/artemis/values.production.yaml` under `image.tag` (format: `X.Y.Z@sha256:<digest>`). Bootstrap-only path (no semver tag exists yet) uses `sha-<full-sha>@sha256:<digest>` via the `workflow_dispatch` route — see §7.

### 1. Confirm drift

```bash
kubectl -n artemis get deploy artemis \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
git -C ~/DEV/fCC/artemis fetch --tags origin
git -C ~/DEV/fCC/artemis describe --tags --abbrev=0 origin/main
```

If the deployed semver lags the most-recent tag on artemis `origin/main`, drift is real — proceed.

### 2. Cut + push the artemis tag

The artemis-side flow (audit unreleased commits, pick the bump, annotated tag, regen CHANGELOG, push) is documented in `~/DEV/fCC/artemis/RELEASING.md`. Operator runs that flow; the tag push fires the GHCR workflow + the GH Release auto-publish step.

Watch the build:

```bash
gh run watch --repo freeCodeCamp/artemis --exit-status
```

### 3. Resolve digest

```bash
VERSION=X.Y.Z
docker buildx imagetools inspect "ghcr.io/freecodecamp/artemis:${VERSION}" \
  --format '{{.Manifest.Digest}}'
```

Output is the `sha256:<64-hex>` digest that becomes the load-bearing pin.

### 4. Bump pin

Edit `k3s/gxy-management/apps/artemis/values.production.yaml`:

```yaml
image:
  repository: ghcr.io/freecodecamp/artemis
  # release: X.Y.Z
  tag: "X.Y.Z@sha256:<digest>"
  pullPolicy: IfNotPresent
```

Both the `# release:` comment and the `tag:` value carry the bare semver (no `v`-prefix). The `@sha256:<digest>` suffix is the immutable anchor — kubelet pulls by digest when both are present. Never ship `tag: X.Y.Z` without the digest, and never ship `tag: latest` in production values.

### 5. Commit

```bash
cd ~/DEV/fCC/infra
git add k3s/gxy-management/apps/artemis/values.production.yaml
git commit -m "chore(artemis): pin vX.Y.Z"
```

Operator pushes per infra-repo conventions (small-fix-direct vs PR-with-review threshold; see `PR_WORKFLOW.md`).

### 6. Deploy + watch rollout

```bash
just release gxy-management artemis
kubectl -n artemis rollout status deploy/artemis --timeout=180s
```

### 7. Verify

```bash
just verify-app gxy-management artemis
curl -fsS https://uploads.freecode.camp/healthz   # {"ok":true}
just verify-artemis
```

Confirm the running version banner picks up the new release:

```bash
kubectl -n artemis logs -l app.kubernetes.io/name=artemis --since=15m \
  | grep "starting version"
```

Expected: `artemis: starting version=X.Y.Z commit=<full-sha>` one line per replica.

`verify-artemis` is the authoritative E2E check — green = the new image serves init/upload/finalize/promote correctly against R2 + GH OAuth.

### Rollback

Revert the `values.production.yaml` commit and re-run `just release gxy-management artemis`. Image is digest-pinned so rollback is deterministic. No DB / state migration on artemis (stateless svc over R2).

Faster path when the regression is acute: `helm -n artemis history artemis` + `helm -n artemis rollback artemis <revision>` — re-pin the file afterward so the next `just release` does not undo the rollback.

## Failure modes

| Symptom                                                           | Likely cause                                 | Action                                                               |
| ----------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------- |
| `Error unmarshalling input json: invalid character '#'` from sops | dotenv decrypted without explicit type flags | use the canonical incantation in §4                                  |
| Helm fail with `.Values.secretEnv.X is required`                  | sops overlay missing key                     | re-run §5 mint block (paste-once)                                    |
| `whoami` lists no sites on a freshly bootstrapped cluster         | Valkey registry not yet seeded               | `universe sites register <slug> --team <team>` per §6 bootstrap      |
| 503 on `uploads.freecode.camp/healthz`                            | Gateway not bound; HTTPRoute not picked up   | `kubectl -n artemis describe gateway,httproute` — check Traefik logs |
| 502 / "no available server" via CF                                | CF zone SSL = Strict + origin no cert        | flip CF zone SSL to Flexible (zone-wide; matches cassiopeia caddy)   |
| ERR_SSL_PROTOCOL_ERROR in browser                                 | CF zone SSL = Off                            | set CF zone SSL to Flexible                                          |
| 429 on bulk upload                                                | rate-limit middleware tripped                | tune `rateLimit.average` / `.burst` in `values.production.yaml`      |

## Cross-references

- ADR-016 — Universe deploy proxy
- `~/DEV/fCC/artemis/RELEASING.md` — artemis-side release flow (cut, tag, CHANGELOG, push)
- `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` §2026-04-26 build-residency, §2026-04-27 RUN-residency clause
- `~/DEV/fCC-U/Universe/decisions/009-...` — Tailscale Operator rejected
- [`01-deploy-new-constellation-site.md`](01-deploy-new-constellation-site.md) — staff-side deploy flow against this service
- [`03-artemis-postdeploy-check.md`](03-artemis-postdeploy-check.md) — E2E post-deploy gate
- [`04-secrets-decrypt.md`](04-secrets-decrypt.md) — canonical sops dotenv decrypt
- [`05-r2-keys-rotation.md`](05-r2-keys-rotation.md) — R2 admin key rotation
- `infra/CLAUDE.md` §Secrets
- `infra/k3s/gxy-management/apps/artemis/README.md`
- `infra/scripts/phase5-proxy-smoke.sh`
