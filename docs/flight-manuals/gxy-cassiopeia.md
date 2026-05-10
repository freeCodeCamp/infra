# Flight Manual — gxy-cassiopeia

Production static-apps galaxy. Serves `*.freecode.camp` from R2 via
caddy-s3 with the in-tree `caddy.fs.r2` alias module. Three nodes, DO
FRA1.

| Field             | Value                                                  |
| ----------------- | ------------------------------------------------------ |
| Role              | Static-apps serve plane (read-side of Universe static) |
| Provider          | DigitalOcean FRA1                                      |
| Pod CIDR          | `10.7.0.0/16`                                          |
| Service CIDR      | `10.17.0.0/16`                                         |
| Cilium cluster ID | `4`                                                    |
| TLS posture       | CF Flexible (CF-edge HTTPS, origin HTTP)               |
| Last rehearsed    | 2026-05-10 (post universe-master-audit)                |

> **Read first:** [`UNIVERSE.md`](UNIVERSE.md) §0 prereqs, §1 DNS, §2
> secrets. Those are shared across all galaxies and are **not**
> repeated here.
>
> **Working-directory rule (HARD):** every cluster-touching recipe in
> this chapter must run from `k3s/gxy-cassiopeia/`. The galaxy `.envrc`
> loads the right DO token + `KUBECONFIG`. Running from repo root
> targets the wrong cluster or fails. Each section repeats the `cd`.
>
> **Idempotency:** every state-changing step has a "skip-if-already-done"
> guard. Re-run any section in isolation and the second run is a no-op.

This chapter feeds the cassiopeia design captured in
[`../architecture/rfc-gxy-cassiopeia-ga.md`](../architecture/rfc-gxy-cassiopeia-ga.md);
read it before deviating from any step.

## §A — k3s bootstrap

### A.1 Pre-flight

`UNIVERSE.md §0` already covers tool versions, age key, infra-secrets
mount, and `just secret-verify-all`. Cassiopeia-specific files:

- `infra-secrets/k3s/gxy-cassiopeia/caddy.values.yaml.enc` — sops
  overlay carrying R2 credentials (`endpoint`, `accessKeyId`,
  `secretAccessKey`).
- `infra-secrets/k3s/gxy-cassiopeia/r2-rw.env.enc` +
  `r2-ro.env.enc` — bucket-scoped key pair for `just r2-bucket-verify`.

Verify before proceeding:

```bash
cd ~/DEV/fCC/infra
just secret-verify-all
```

### A.2 DigitalOcean infrastructure (one-time, ClickOps)

3× `s-4vcpu-8gb-amd` in FRA1, named `gxy-vm-cassiopeia-k3s-{1,2,3}`,
tag `gxy-cassiopeia-k3s`, image Ubuntu 24.04, VPC `universe-vpc-fra1`,
cloud-init `cloud-init/basic.yml`. Add tag `gxy-cassiopeia-k3s` to
the existing `gxy-fw-fra1` Cloud Firewall.

Idempotency check (skip if 3 droplets already up):

```bash
test "$(doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format ID --no-header | wc -l)" -eq 3 \
  && echo "✓ 3 cassiopeia droplets present, skipping" \
  || echo "↻ provision via DO dashboard (no OpenTofu workspace yet)"
```

OpenTofu codification is parked per ADR-002 drift report.

### A.3 Tailscale + cluster bootstrap

```bash
cd ~/DEV/fCC/infra

just play tailscale--0-install gxy_cassiopeia_k3s
just play tailscale--1b-up-with-ssh gxy_cassiopeia_k3s

cd k3s/gxy-cassiopeia
just play k3s--bootstrap gxy_cassiopeia_k3s
```

`k3s--bootstrap` is idempotent: it's a sequence of validate →
prerequisites → k3s deploy → Cilium → verify + kubeconfig that
no-ops on already-applied state. Cilium devices/MTU pin
(`devices: [eth0, eth1]`, `mtu: 1500`) is in
`k3s/gxy-cassiopeia/cluster/cilium/values.yaml` — required to keep
cross-node TCP working when Tailscale is on the node (per ADR-009
spike finding 2026-04-06).

### A.4 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff

kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium-health status
# 3/3 reachable, all endpoints 1/1
```

etcd snapshots auto-land in
`s3://net-freecodecamp-universe-backups/etcd/gxy-cassiopeia/` every
6h, 20 retained.

## §B — caddy-s3 + R2

### B.1 Helm-upgrade caddy chart

```bash
cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia

# Skip if helm release already at the pinned SHA.
PINNED=$(yq '.image.tag' apps/caddy/values.production.yaml)
LIVE=$(helm get values -n caddy caddy 2>/dev/null | yq '.image.tag' - || echo "")
if [ "$LIVE" = "$PINNED" ]; then
  echo "✓ caddy already at $PINNED, skipping"
else
  cd ~/DEV/fCC/infra
  just helm-upgrade gxy-cassiopeia caddy
fi
```

The recipe layers chart defaults → `values.production.yaml` (image
SHA pin, hostnames, replicas) → sops overlay
`caddy.values.yaml.enc` (R2 credentials). Image pulls from
`ghcr.io/freecodecamp/caddy-s3:<sha-tag>@sha256:<digest>` direct
(build-residency principle — pillars build outside Universe; never
through zot for chicken-egg avoidance).

### B.2 R2 bucket verify

```bash
cd ~/DEV/fCC/infra
just r2-bucket-verify universe-static-apps-01
# Asserts: rw key writes, ro key cannot write, both can read.
# Idempotent — touches a temp key it cleans up.
```

R2 layout (per ADR-016 §"R2 layout"):

```
universe-static-apps-01/
├── <site>/deploys/<ts>-<sha>/...   (immutable)
├── <site>/preview                  (alias: body = deploy id)
└── <site>/production               (alias: body = deploy id)
```

caddy reads alias keys at `<site>.freecode.camp/<env>` (full FQDN —
the `<sitePrefix>.<rootDomain>` form). artemis writes the same
form via `ALIAS_*_KEY_FORMAT` env. **Format coupling is real**: any
chart edit on either side must echo the other (probe 03).

### B.3 Verify Gateway + HTTPRoute

```bash
cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get pods -n caddy
# 3 pods Running. Container count depends on whether the rclone-sync
# sidecar is present in templates/deployment.yaml — D32 absorbed S3
# filesystem in-tree, sidecar may have been retired. Check the chart.

kubectl get gateway -n caddy
# caddy-gateway   Programmed=True

kubectl get httproute -n caddy
# caddy-route   matches *.freecode.camp via parentRef caddy-gateway
```

R2 read-only token rotation: see
[`../runbooks/05-r2-keys-rotation.md`](../runbooks/05-r2-keys-rotation.md).
Rotate at least annually; cluster reads non-disruptively after secret
update + pod rollout.

## §C — Static-apps registry

### C.1 What it is, where it lives

The static-apps registry maps `<site-slug> → [authorized GH teams]`
and is the source of truth for both site enumeration and per-deploy
authz (per ADR-016 §Authn / authz). Per
`rfc-gxy-cassiopeia-ga.md` §B (locked 2026-05-10), the registry
substrate is **Valkey single-instance alongside artemis on
gxy-management**. AOF + RDB on PVC; nightly RDB dump to R2.

This galaxy (cassiopeia) does **not** host the registry — the
cassiopeia caddy reads R2 only, and the alias bytes in R2 are produced
by artemis on gxy-management after authz lands. Bring-up of valkey +
artemis lives in `gxy-management.md §C/§D` and is run **before** the
first staff deploy hits cassiopeia.

### C.2 What cassiopeia consumes

Caddy on cassiopeia reads:

- `<site>/preview` and `<site>/production` alias keys (atomic R2 puts).
- `<site>/deploys/<ts>-<sha>/...` deploy bytes pointed-at by the alias.

caddy never talks to Valkey, never talks to artemis. The trust
boundary is one-directional: artemis (gxy-management) writes R2;
caddy (cassiopeia) reads R2. Compromise of cassiopeia cannot mutate
the registry or cross-write deploy bytes (caddy uses an R2
read-only token, see B.2).

### C.3 Cassiopeia-side verifier

Once gxy-management has Valkey + artemis up and at least one site
registered (default: `test`), this galaxy's read-side smoke is:

```bash
# Replace with any registered site from `universe site list`.
SITE=test
ENV=preview

curl -fsSI "https://${SITE}.freecode.camp/" | head -5
# HTTP/2 200 (or 404 if no deploy has landed yet — that's still
# evidence cassiopeia is reachable; pair with the deploy smoke in §E).

# Confirm the underlying alias resolves:
aws --endpoint-url "$R2_ENDPOINT" s3api get-object \
  --bucket universe-static-apps-01 \
  --key "${SITE}.freecode.camp/${ENV}" \
  /dev/stdout
# → body is the current deploy id (e.g. "20260510-152301-abc1234").
```

### C.4 Cross-references

| Concern                                 | See                                                                                             |
| --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Registry design + KV substrate decision | [`../architecture/rfc-gxy-cassiopeia-ga.md`](../architecture/rfc-gxy-cassiopeia-ga.md) §B       |
| ADR governing the deploy proxy plane    | `Universe/decisions/016-deploy-proxy.md`                                                        |
| Operator bring-up of valkey + artemis   | [`gxy-management.md`](gxy-management.md) §C/§D                                                  |
| `universe site register` CLI            | RFC §B "CLI surface"                                                                            |
| What's not yet decoupled (drift)        | [`../architecture/adr-drift-2026-05-10.md`](../architecture/adr-drift-2026-05-10.md) §"ADR-016" |

## §D — Ingress + DNS + cert

### D.1 Cloudflare DNS

Wildcard A records to all 3 cassiopeia node public IPs, CF orange
cloud ON, SSL Flexible.

```bash
# Confirm node public IPs.
doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format Name,PublicIPv4

# Confirm DNS resolution at CF edge (after the A records are in).
dig +short test.freecode.camp @1.1.1.1
# → 3 cassiopeia node IPs (or CF anycast IPs depending on proxy mode;
#   anycast is the steady state with proxy ON).
```

The wildcard `*.freecode.camp` covers both `<site>.freecode.camp`
(production) and `<site>--preview.freecode.camp` (preview, double-dash
per ADR-009 §"Domains"). **No per-site DNS edit required** after
the wildcard is in place — site registration via `universe site
register` does not provision DNS, only registers in Valkey.

### D.2 TLS posture (recap, source of truth in `UNIVERSE.md §1`)

`freecode.camp` zone is **CF Flexible**: CF terminates HTTPS at the
edge, origin is plain HTTP. caddy listens on HTTP `:80` only behind
Traefik gatewayClassName. No origin cert at the k8s layer for this
zone.

The `freecodecamp.net` zone (windmill, future argocd/zot) uses Full
Strict with origin cert pair from
`infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc`. The two
postures coexist intentionally — see `UNIVERSE.md §1` for the matrix.

cert-manager / DNS-01 issuer is **not deployed** and not on the
short-term path (RFC §D).

### D.3 Origin allow-list (parked gap)

DO Cloud Firewall on `gxy-fw-fra1` accepts `80/443` from
`0.0.0.0/0`. Only CF WAF gates origin hits today. The "only-CF-edge-IPs
on origin firewall" cron + manifest is parked
(`gxy-static-k7d.14`); document the gap when handing over operator
state. Not GA-blocking — origin reveals galaxy IPs but everything
serves through CF.

### D.4 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-cassiopeia
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Edge cert + 200 from a known site (assumes §E smoke has populated `test`):
curl -fsSI https://test.freecode.camp/ | head -5

# Traefik gatewayClassName picks up the HTTPRoute:
kubectl get httproute -n caddy caddy-route -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}'
# → True
```

## §E — End-to-end smoke

The smoke harness lives on the artemis side (it's the one that holds
the R2 admin token). From the operator box, with kubeconfig pointed
at gxy-management:

```bash
cd ~/DEV/fCC/infra
just artemis-postdeploy-check        # auth + sites/list + 200 on uploads.freecode.camp/healthz
just phase5-smoke                    # init → upload → finalize (preview) → preview curl → promote → prod curl
```

`phase5-smoke` deploys to a known marker site (`test`), curls the
public URL on cassiopeia, and rolls back to the prior production
deploy on exit (success OR failure). Exit 0 = green.

### Acceptance gates (from RFC §E)

- **G1** k3s + Cilium green (§A.4 above).
- **G2** caddy chart 3/3 + Gateway Programmed (§B.3).
- **G3** R2 reachable r/w with the correct keys (§B.2).
- **G4** `*.freecode.camp` resolves to 3 cassiopeia node IPs (§D.1).
- **G7** `universe site register test --teams=staff` succeeds without
  operator action (run on the artemis side; smoke confirms read-side
  here in §C.3).
- **G8** `phase5-smoke` exits 0 (deploys to `test.freecode.camp`).
- **G12** Idempotency — full chapter §A→§D rerun is a no-op.

G5 (Valkey running), G6 (artemis with `REGISTRY_BACKEND=valkey`),
G9-G11 (registry restart, Valkey pod restart, RDB to R2) belong to
gxy-management.md.

## §F — Troubleshooting

### Caddy serving 503 on `<site>.freecode.camp/`

1. Check R2 status: <https://www.cloudflarestatus.com/>. Caddy maps
   upstream R2 5xx to 502 by default.
2. Read alias key directly:
   `aws --endpoint-url "$R2_ENDPOINT" s3api get-object --bucket universe-static-apps-01 --key "<site>.freecode.camp/production" /dev/stdout`.
   If the alias is empty or points at a deleted prefix → the registry
   side wrote a bad pointer; fall back via
   `universe static promote --to <previous-deploy-id>`.
3. caddy logs:
   `kubectl logs -n caddy deploy/caddy --tail=200 | grep -i 'r2'`.

### CF cache shows old deploy after promote

CF edge caches the alias-resolved bytes for the cache TTL. Targeted
purge via CF API is the surgical option:

```
curl -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/purge_cache" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"files":["https://test.freecode.camp/index.html"]}'
```

Zone-wide purge is available in CF dashboard → Caching → Purge
Everything. Use sparingly.

### Cilium / MTU pinning regression

If cross-node TCP starts failing after a node-level change (Tailscale
upgrade, new NIC, kernel bump), check Cilium's `devices` and `mtu`
config still pin to `[eth0, eth1]` and `1500`. ADR-009 spike finding;
recurring footgun.

## §G — Teardown

Destructive. Confirm CF DNS has been flipped off cassiopeia before
teardown, otherwise live traffic 5xxs.

### Cluster only (preserves VMs, lets you replay §A.3 on the same droplets)

```bash
cd ~/DEV/fCC/infra
just play k3s--teardown gxy_cassiopeia_k3s
```

### Full teardown (VMs too)

```bash
cd ~/DEV/fCC/infra
just play k3s--teardown gxy_cassiopeia_k3s
doctl compute droplet delete \
  gxy-vm-cassiopeia-k3s-1 gxy-vm-cassiopeia-k3s-2 gxy-vm-cassiopeia-k3s-3 \
  --force
```

R2 buckets, VPC, firewall, and DO Spaces persist (shared
infrastructure — see `UNIVERSE.md §"Shared infrastructure"`).
