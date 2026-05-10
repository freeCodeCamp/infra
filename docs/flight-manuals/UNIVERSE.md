# Flight Manual — UNIVERSE (shared phases)

Cross-galaxy steps that apply to every cluster. Read this before any
per-galaxy chapter. Each per-galaxy chapter assumes §0–§2 already
ran; chapters do not repeat them.

| §    | What                                                  |
| ---- | ----------------------------------------------------- |
| §0   | Prerequisites — host tools, env, infra-secrets        |
| §1   | DNS + Cloudflare baseline                             |
| §2   | infra-secrets bootstrap                               |
| §3   | Shared infrastructure — VPC, firewall, S3 backups, R2 |
| §4   | Lifecycle calendar (cross-cluster pins + EOLs)        |
| §99  | Cross-galaxy smoke (post-bring-up)                    |
| §100 | Teardown (reverse order, rarely run)                  |

> **Working-directory rule (HARD):** every cluster-touching `just`
> recipe MUST run from `k3s/<galaxy>/` so direnv loads the right DO
> token + `KUBECONFIG`. Repo-root invocation hits the wrong cluster
> or fails silently. Per-galaxy chapters repeat this above each
> recipe.

## §0 — Prerequisites

### §0.1 Host tools

Pinned versions live in `infra/docs/flight-manuals/00-index.md
§"Lifecycle calendar"`. Operator floor:

| Tool        | Floor            | Why                                                  |
| ----------- | ---------------- | ---------------------------------------------------- |
| `kubectl`   | matches k3s line | Cluster-side calls in every chapter                  |
| `helm`      | 3.14+            | All app deploys are helm-driven                      |
| `kustomize` | 5+               | argocd/windmill/zot manifests/base                   |
| `ansible`   | core 2.16+       | k3s bootstrap playbooks                              |
| `doctl`     | 1.110+           | DO inventory probes + Spaces management              |
| `gh`        | 2.50+            | GH workflow triggers (artemis, caddy-s3 image build) |
| `sops`      | 3.9+             | sops+age envelope read/write                         |
| `age`       | 1.1.1+           | sops backend                                         |
| `jq`        | 1.7+             | shell parsing in recipes                             |
| `yq`        | 4.40+            | shell parsing in recipes                             |
| `direnv`    | 2.34+            | per-galaxy env loading                               |
| `aws-cli`   | 2.15+            | R2 + Spaces interactions (S3 API)                    |

```bash
cd ~/DEV/fCC/infra
just ansible-install
```

Idempotent — installs/refreshes ansible deps into the repo's venv.

### §0.2 Environment + direnv

Repo `.envrc` hierarchy loads:

- root `.envrc` → `$SECRETS_DIR/global/.env.enc` (org-wide tokens:
  `DIGITALOCEAN_TOKEN_ORG`, CF tokens, GHCR PAT, etc.).
- `k3s/<galaxy>/.envrc` → sources root, loads
  `$SECRETS_DIR/do-universe/.env.enc` (DO Universe-scoped token),
  exports `KUBECONFIG=$(expand_path .kubeconfig.yaml)`.

`SECRETS_DIR=../infra-secrets` is the **only** supported layout. Any
other path breaks direnv loading.

```bash
direnv allow .
direnv allow k3s/gxy-management
direnv allow k3s/gxy-launchbase
direnv allow k3s/gxy-cassiopeia
```

### §0.3 age key

```bash
test -f ~/.config/sops/age/keys.txt && echo "✓ age key present" \
  || (echo "✗ age key missing"; exit 1)
```

Per RFC `infra/docs/architecture/rfc-secrets-layout.md` §"D5: single
org key"; key distribution is operator-side, not in any repo.

## §1 — DNS + Cloudflare baseline

### §1.1 Zones owned

| Zone               | Purpose                                                   | Cloud SSL   | Origin cert                   |
| ------------------ | --------------------------------------------------------- | ----------- | ----------------------------- |
| `freecodecamp.net` | Internal tools (windmill / argocd / zot when reactivated) | Full Strict | `*.freecodecamp.net` wildcard |
| `freecodecamp.org` | Public app (separate fCC scope; not Universe)             | n/a         | n/a                           |
| `freecode.camp`    | Static-apps surface (cassiopeia + artemis `uploads.…`)    | Flexible    | none (CF→origin HTTP)         |

Per ADR-009 §"Domains" (with the audit-resolved cassiopeia
re-routing per `docs/architecture/adr-drift-2026-05-10.md`).

### §1.2 Per-galaxy DNS records

| Galaxy           | Records                                                                               | Galaxy chapter §     |
| ---------------- | ------------------------------------------------------------------------------------- | -------------------- |
| `gxy-management` | `windmill.freecodecamp.net` + `uploads.freecode.camp` + (parked: `argocd.…`, `zot.…`) | gxy-management.md §D |
| `gxy-launchbase` | (none at present — woodpecker DNS retired)                                            | gxy-launchbase.md §D |
| `gxy-cassiopeia` | `*.freecode.camp` wildcard                                                            | gxy-cassiopeia.md §D |

CF orange cloud ON for every record. SSL mode per zone (matrix above).

### §1.3 Cloudflare API token scope

Operator-side token with:

- `Zone.DNS:Edit` on the three zones
- `Zone.Cache Purge:Purge` on the three zones
- (R2 admin token is a separate object-storage token — see §3)

Stored encrypted at `infra-secrets/global/.env.enc` (key
`CLOUDFLARE_API_TOKEN`). Rotation cadence: annual minimum, per
ADR-011.

## §2 — infra-secrets bootstrap

### §2.1 Layout (read-only, do not edit from this repo)

`../infra-secrets/`:

```
.sops.yaml                          # creation rules; matches all *.enc
global/
  .env.enc                          # org-wide tokens (direnv)
  tls/freecodecamp-net.{crt,key}.enc  # CF Origin wildcard for the zone
do-universe/
  .env.enc                          # DO Universe-scoped token (galaxy direnv)
k3s/
  gxy-management/
    artemis.values.yaml.enc         # sops overlay for artemis chart
    windmill.values.yaml.enc        # sops overlay for windmill chart
    windmill-backup.secrets.env.enc # CronJob backup creds (DO Spaces)
    valkey.values.yaml.enc          # sops overlay for valkey chart  (after RFC §B lands)
    artemis.env.enc                 # artemis runtime secret env (artemis Q15)
  gxy-launchbase/
    (post-woodpecker-retire: cnpg-system has no secrets at this level)
  gxy-cassiopeia/
    caddy.values.yaml.enc           # sops overlay for caddy chart (R2 creds)
    r2-rw.env.enc                   # bucket-scoped rw key pair
    r2-ro.env.enc                   # bucket-scoped ro key pair
```

Authoritative spec: `infra/docs/architecture/rfc-secrets-layout.md`.
Decryption gotchas: `infra/docs/runbooks/04-secrets-decrypt.md`
(notably: sops auto-detect routes `.enc` to JSON parser — explicit
`--input-type dotenv --output-type dotenv` required for `*.env.enc`).

### §2.2 Verify all secrets decrypt

```bash
cd ~/DEV/fCC/infra
just secret-verify-all
```

Idempotent. Reports any envelope that fails to decrypt with the
operator's age key. Hard-fails before any galaxy bring-up so
`just deploy` later cannot eat a half-decrypted overlay.

## §3 — Shared infrastructure (not cluster-scoped)

These resources live above any single galaxy. Provisioned once,
referenced by every cluster.

| Resource                      | Identifier                                       | Purpose                                                         |
| ----------------------------- | ------------------------------------------------ | --------------------------------------------------------------- |
| DO VPC                        | `universe-vpc-fra1` (CIDR `10.110.0.0/20`)       | private network for all FRA1 nodes                              |
| DO Cloud Firewall             | `gxy-fw-fra1`                                    | tag-based attach: `gxy-<galaxy>-k3s`                            |
| DO Spaces bucket (backups)    | `net-freecodecamp-universe-backups`              | etcd snapshots + Windmill PG dumps + CNPG WAL (TBC)             |
| Cloudflare R2 bucket (static) | `universe-static-apps-01`                        | cassiopeia static apps deploys + `_meta/registry/<date>.rdb`    |
| Cloudflare R2 admin token     | `infra-secrets/global/.env.enc:R2_ADMIN_*`       | sole-writer for artemis; sole-uploader for valkey RDB CronJob   |
| Cloudflare R2 read-only token | `infra-secrets/k3s/gxy-cassiopeia/r2-ro.env.enc` | caddy-s3 read path                                              |
| Tailscale tailnet             | freeCodeCamp tailnet                             | SSH + kubectl on platform-team nodes (under review per ADR-009) |
| GHCR pull tokens              | implicit via `ghcr.io` direct anon-pull or PAT   | platform pillars pull images direct from GHCR (no zot mirror)   |

R2 bucket DR posture: versioning enabled; per-prefix retention is
informal today (R2 lifecycle GC for orphan deploy bytes is parked
per RFC §"Out of scope").

## §4 — Lifecycle calendar (cross-cluster pins)

Third-party pins with EOL windows. Roll-forward is an explicit
backlog item — never automatic.

| Component                 | Current pin               | EOL / stale-after        | Action window   | Notes                                                                 |
| ------------------------- | ------------------------- | ------------------------ | --------------- | --------------------------------------------------------------------- |
| k3s                       | `v1.34.5+k3s1`            | 2026-10-27               | by Sept 2026    | All galaxies. Plan 1.35 upgrade. Test on gxy-management first.        |
| Caddy (in caddy-s3 image) | `v2.11.2`                 | CVE-driven               | 14 days per D30 | gxy-cassiopeia. Bump via PR + caddy-s3 build + smoke.                 |
| CloudNativePG             | chart `0.28` / op `1.29`  | 1.28 EOL 2026-06-30      | during `1.29.x` | gxy-launchbase. Operator-guided pg_upgrade rolling in place.          |
| Cilium                    | chart default (1.19 line) | 3-minor community window | on minor bump   | All galaxies. MTU/devices pin must persist; bump behind feature gate. |
| Valkey                    | (added with RFC §B)       | LF community             | on minor bump   | gxy-management. Single-instance; bolt on Sentinel later.              |

When a pin crosses its action window, file an entry in the active
sprint dossier (or `infra/.scratchpad/sprints/...`).

## §99 — Cross-galaxy smoke (post-bring-up)

Run after all 3 galaxy chapters have been rehearsed end-to-end on a
fresh cluster set. Confirms cross-galaxy seams hold.

```bash
cd ~/DEV/fCC/infra

# 1. Each galaxy reachable from operator box via Tailscale or kubectl.
for GXY in management launchbase cassiopeia; do
  cd ~/DEV/fCC/infra/k3s/gxy-$GXY
  KUBECONFIG=$(pwd)/.kubeconfig.yaml kubectl get nodes -o wide || echo "✗ $GXY unreachable"
done

# 2. Static-apps end-to-end through artemis (gxy-management) → R2 → caddy (cassiopeia).
cd ~/DEV/fCC/infra
just artemis-postdeploy-check
just phase5-smoke

# 3. R2 bucket integrity (rw + ro keys both work).
just r2-bucket-verify universe-static-apps-01
```

Smoke success = `phase5-smoke` exits 0 (deploys to `test.freecode.camp`,
curls 200, rolls back).

## §100 — Teardown (reverse rebuild order)

Destructive. Confirm DNS is flipped before tearing down a galaxy or
live traffic 5xxs. Reverse the rebuild order (cassiopeia → launchbase →
management) so dependent planes go down first.

| Step | What                                                                                            | Anchor                 |
| ---- | ----------------------------------------------------------------------------------------------- | ---------------------- |
| 1    | Flip CF DNS off cassiopeia public records (or move CF status to "under maintenance")            | CF dashboard           |
| 2    | `just play k3s--teardown gxy_cassiopeia_k3s`                                                    | `gxy-cassiopeia.md §G` |
| 3    | `just play k3s--teardown gxy_launchbase_k3s`                                                    | `gxy-launchbase.md §G` |
| 4    | `just play k3s--teardown gxy_management_k3s`                                                    | `gxy-management.md §G` |
| 5    | (Optional) delete droplets — `doctl compute droplet delete --tag-name gxy-<galaxy>-k3s --force` | per-galaxy §G          |
| 6    | Shared infra (VPC, firewall, R2, Spaces) — preserve unless full-platform retire                 | this file §3           |

R2 bucket state survives all of the above (the buckets are the
source of truth — clusters only serve them).
