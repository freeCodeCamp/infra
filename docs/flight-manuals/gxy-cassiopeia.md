# Flight Manual — gxy-cassiopeia

Production static-hosting galaxy. Serves Universe constellations
(`freecode.camp` + first-party static sites) via Caddy + R2.

Last rebuild-verified: 2026-04-20.

## Pre-flight

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- All secrets decrypt OK
- age key on local machine (`~/.config/sops/age/keys.txt`)
- `infra-secrets/k3s/gxy-cassiopeia/` contains:
  - `caddy.values.yaml.enc` (R2 credentials: `AWS_ACCESS_KEY_ID`,
    `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`)
  - `r2-rw.env.enc` + `r2-ro.env.enc` (bucket-scoped key pair for
    `just r2-bucket-verify`)

## Phase 19: Infrastructure (ClickOps)

### 19.1 DO Droplets

- Create 3× `s-4vcpu-8gb-amd` in FRA1
- Names: `gxy-vm-cassiopeia-k3s-{1,2,3}`
- Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-cassiopeia-k3s`
- Cloud-init: `cloud-init/basic.yml`

No OpenTofu workspace exists for gxy-cassiopeia yet — provisioning is DO
dashboard today, codify as a follow-up when the layout stabilises
post-cutover.

### 19.2 DO Cloud Firewall

- Add tag `gxy-cassiopeia-k3s` to existing `gxy-fw-fra1`

### 19.3 Tailscale

```
just play tailscale--0-install gxy_cassiopeia_k3s
just play tailscale--1b-up-with-ssh gxy_cassiopeia_k3s
```

Verify: `tailscale status | grep gxy-vm-cassiopeia`

## Phase 20: Cluster bootstrap

```
cd k3s/gxy-cassiopeia
just play k3s--bootstrap gxy_cassiopeia_k3s
```

Per-galaxy config in `ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml`
(cluster CIDR `10.7.0.0/16`, service CIDR `10.17.0.0/16`, `cilium_cluster_id: 4`).
etcd snapshots land in
`s3://net-freecodecamp-universe-backups/etcd/gxy-cassiopeia/`.

### Post-bootstrap checks

```
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff
```

## Phase 21: Caddy Helm chart install

```
just helm-upgrade gxy-cassiopeia caddy
```

Local chart at `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/`. The chart
templates Gateway + HTTPRoute + NetworkPolicy + the Caddy Deployment with
rclone-sync sidecar. Chart defaults are overlaid by
`k3s/gxy-cassiopeia/apps/caddy/values.production.yaml` (image tag pin,
per-site host list) and then by the sops overlay `caddy.values.yaml.enc`
(R2 credentials).

Caddy image is `ghcr.io/freecodecamp/caddy-s3:{sha}`, built by the
GitHub Actions workflow `.github/workflows/docker--caddy-s3.yml` on
github-hosted runners (build-residency principle — platform pillars
build outside Universe so the recovery path is never circular). The
in-tree r2alias module is compiled via xcaddy; no third-party Caddy
plugins per D32. Local dev builds via `just caddy-s3-build` + verify
with `just caddy-s3-verify`. The Woodpecker pipeline at
`.woodpecker/caddy-s3-build.yaml` is retained as a manual-trigger
secondary; will retire via T-build-residency dispatch.

### Verify

```
kubectl get pods -n caddy
# 3 pods Running, 2/2 containers (caddy + rclone-sync)

kubectl get gateway -n caddy
# caddy-gateway Programmed=True

kubectl get httproute -n caddy
# caddy-route
```

## Phase 22: R2 bucket provisioning

Bucket `universe-static-apps-01` is already provisioned (versioning enabled,
prefix-scoped per site under ADR-016 artemis). For credential rotation use
[`../runbooks/05-r2-keys-rotation.md`](../runbooks/05-r2-keys-rotation.md).
Store key pairs encrypted at
`infra-secrets/k3s/gxy-cassiopeia/r2-{rw,ro}.env.enc`.

Verify end-to-end:

```
just r2-bucket-verify universe-static-apps-01
# rw key writes, ro key cannot write, both can read
```

## Phase 23: CF DNS + origin allow-list

### 23.1 Get node public IPs

```
doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format Name,PublicIPv4
```

### 23.2 Cloudflare DNS

- 3× A records per production domain → cassiopeia node public IPs (Proxy ON)
- SSL mode: Full (Strict) for domains with origin cert, Flexible otherwise

Set A records (`@`, `www`, `*`) via Cloudflare dashboard or `dash.cloudflare.com` API.
Cutover already applied for cassiopeia zones — historical tooling lived under
justfile §`cf-dns` group (retired post-cutover). For DR rewind, use Cloudflare
Audit Log → revert.

### 23.3 Origin allow-list

Cron + manifest to keep only Cloudflare edge IPs on the origin firewall is
TBD when `gxy-static-k7d.14` closes. Until then, the cluster firewall
(`gxy-fw-fra1`) accepts 80/443 from the public internet; CF WAF is the only
layer gating origin hits.

## Phase 24: Deploy plane

Production deploys land via the artemis upload-proxy on `gxy-management`
(`uploads.freecode.camp`) — see ADR-016 §deploy proxy. Staff run
`universe static deploy <site>` from any environment; artemis writes
`<site>.freecode.camp/<ts>-<sha>/` to `universe-static-apps-01` and
flips the `production`/`preview` alias key. cassiopeia caddy reads
the alias-pinned object and serves at the edge.

Production DNS for `freecode.camp` + first-party constellation hosts
resolves to cassiopeia node IPs.

## Troubleshooting

### Alias cache invalidation

rclone sidecar syncs `production`/`preview` aliases every ~5 minutes. Force
a sync by restarting the deployment:

```
kubectl rollout restart deployment -n caddy caddy
```

### R2 503s

- Check R2 status page first. The `caddy-s3` in-tree module surfaces
  upstream 503s as 502 to the client.
- If the bucket is healthy: `kubectl logs -n caddy deploy/caddy -c rclone-sync`
  to inspect the last sync cycle.
- Fall back to serving from the previous deploy ID by running
  `universe static promote --to <previous-deploy-id>`.

### CF cache purge

After a promote, CF edge still serves the old alias for the cache TTL:

- Zone-wide purge: CF dashboard → Caching → Configuration → Purge Everything
  (use sparingly).
- Targeted purge: API `POST /zones/{id}/purge_cache` with `{ "files": [...] }`
  for the specific URLs.

## Teardown

Destructive: this kills the Caddy cluster. R2 bucket state persists (buckets
are the source of truth — the cluster only serves them). Confirm CF DNS has
been flipped off cassiopeia before teardown so live traffic does not 5xx.

### Cluster only (preserves VMs)

```
just play k3s--teardown gxy_cassiopeia_k3s
```

### Full teardown (VMs too)

```
just play k3s--teardown gxy_cassiopeia_k3s
doctl compute droplet delete gxy-vm-cassiopeia-k3s-1 gxy-vm-cassiopeia-k3s-2 gxy-vm-cassiopeia-k3s-3 --force
```

R2 buckets, VPC, firewall, Spaces persist (shared infrastructure — see
[00-index.md](00-index.md)).
