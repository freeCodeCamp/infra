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

### 2. CF Origin certificate (per-app TLS pattern)

CF dashboard → SSL/TLS → Origin Server → Create Certificate.

| Field    | Value                                                  |
| -------- | ------------------------------------------------------ |
| Hostname | `*.freecode.camp` AND `freecode.camp` (wildcard reuse) |
| Validity | 15 years                                               |
| Format   | Origin CA                                              |

Save PEM blocks locally; absolute paths feed the mirror recipe in §4.

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
helm input mirror — same secret values, plus the CF Origin cert/key
PEM. Generated automatically:

```bash
export ARTEMIS_TLS_CERT=/path/to/uploads.freecode.camp.cert.pem
export ARTEMIS_TLS_KEY=/path/to/uploads.freecode.camp.key.pem
just mirror-artemis-secrets
```

The recipe:

1. Decrypts the dotenv via `sops` with explicit `--input-type dotenv`.
2. Pulls the 5 secret keys, emits `secretEnv:` block.
3. Inlines the cert + key PEMs into a `tls:` block.
4. Validates the assembled YAML via `python3 -c "import yaml; ..."`.
5. Re-seals with `sops --encrypt --input-type yaml`.

After it succeeds, commit the new `.enc` from infra-secrets:

```bash
git -C infra-secrets add k3s/gxy-management/artemis.values.yaml.enc
git -C infra-secrets commit -m "feat(gxy-management): seal artemis values overlay"
```

Re-run after env-var rotation OR cert rotation. The dotenv stays the
SOT — never hand-edit the YAML overlay.

### 6. sites.yaml seed — `freeCodeCamp/artemis` repo

Source of truth: `freeCodeCamp/artemis` `config/sites.yaml`. Initial
seed:

```yaml
sites:
  test:
    teams: ["staff"]
```

PR-reviewed by platform team. Operator pulls the artemis repo locally
on the deploy host so `just artemis-deploy` can `--set-file` it.

```bash
cd ~/DEV/fCC-U/artemis
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
just artemis-deploy
```

The recipe:

1. Loads chart defaults (`charts/artemis/values.yaml`).
2. Loads production overlay (`apps/artemis/values.production.yaml`).
3. Decrypts + loads sops sealed overlay
   (`infra-secrets/k3s/gxy-management/artemis.values.yaml.enc`).
4. Renders sites.yaml from `$ARTEMIS_REPO/config/sites.yaml`
   (default `$HOME/DEV/fCC-U/artemis/config/sites.yaml`) via
   `--set-file sites=...`.
5. Runs `helm upgrade --install` into the `artemis` namespace.
6. Waits for rollout (120s timeout).

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

| What rotates                    | Recipe                                                                                               |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- |
| GH_CLIENT_ID, R2 keys, JWT key  | edit dotenv → `sops -e --in-place`; then `just mirror-artemis-secrets` + `just artemis-deploy`       |
| CF Origin cert (15y — calendar) | new PEMs → `just mirror-artemis-secrets` + `just artemis-deploy`                                     |
| sites.yaml                      | PR to artemis repo; merge; `git -C ~/DEV/fCC-U/artemis pull`; `just artemis-deploy` (fsnotify ≤1min) |
| Image tag                       | bump `apps/artemis/values.production.yaml` `image.tag`; `just artemis-deploy`                        |

## Failure modes

| Symptom                                                           | Likely cause                                 | Action                                                               |
| ----------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------- |
| `Error unmarshalling input json: invalid character '#'` from sops | dotenv decrypted without explicit type flags | use the canonical incantation in §4                                  |
| Helm fail with `.Values.secretEnv.X is required`                  | sops overlay missing key                     | re-run `just mirror-artemis-secrets`                                 |
| Helm fail with `.Values.sites is empty`                           | artemis repo not pulled or wrong path        | `git -C ~/DEV/fCC-U/artemis pull` or set `ARTEMIS_REPO`              |
| Pod CrashLoopBackOff with TLS error                               | cert/key mismatch in sops overlay            | re-run mirror with correct PEM paths                                 |
| 503 on `uploads.freecode.camp/healthz`                            | Gateway not bound; HTTPRoute not picked up   | `kubectl -n artemis describe gateway,httproute` — check Traefik logs |
| 429 on bulk upload                                                | rate-limit middleware tripped                | tune `rateLimit.average` / `.burst` in `values.production.yaml`      |

## Cross-references

- ADR-016 — Universe deploy proxy
- `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` §2026-04-26 build-residency, §2026-04-27 RUN-residency clause
- `~/DEV/fCC-U/Universe/decisions/009-...` — Tailscale Operator rejected
- `infra/CLAUDE.md` §Secrets (canonical sops dotenv decrypt)
- `infra/k3s/gxy-management/apps/artemis/README.md`
- `infra/scripts/phase5-proxy-smoke.sh`
