# Flight Manual — gxy-cassiopeia

Production static-hosting galaxy. Serves Universe constellations (e.g.
`freecode.camp` cutover target, first-party static sites) via Caddy + R2.
Replaces `gxy-static` once the cutover runbook closes.

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

Caddy image is `ghcr.io/freecodecamp-universe/caddy-s3:{sha}`, built by the
Woodpecker pipeline `.woodpecker/caddy-s3-build.yaml` (in-tree r2alias
module via xcaddy; no third-party Caddy plugins per D32). Local dev builds
via `just caddy-s3-build` + verify with `just caddy-s3-verify`.

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

Provision bucket `gxy-cassiopeia-1` (versioning enabled, per-site rw/ro keys)
per [../runbooks/r2-bucket-provision.md](../runbooks/r2-bucket-provision.md).
Store the key pair encrypted at
`infra-secrets/k3s/gxy-cassiopeia/r2-{rw,ro}.env.enc`.

Verify end-to-end:

```
just r2-bucket-verify gxy-cassiopeia-1
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

Use `just cf-dns-cutover <zone> <ips>` for declarative zone flips (see
[../runbooks/dns-cutover.md](../runbooks/dns-cutover.md)). Run
`just cutover-preflight` first — it exits non-zero on any failing site.

### 23.3 Origin allow-list

Cron + manifest to keep only Cloudflare edge IPs on the origin firewall is
TBD when `gxy-static-k7d.14` closes. Until then, the cluster firewall
(`gxy-fw-fra1`) accepts 80/443 from the public internet; CF WAF is the only
layer gating origin hits.

## Phase 24: First deploy via Woodpecker pipeline

The production pipeline template (build artifact → push to R2 with deploy
ID → promote via `universe` CLI) is TBD when `gxy-static-k7d.21` closes.
Until then, immutable deploy + alias promotion flow is the same as
[gxy-static.md](gxy-static.md) Phase 12 — point `S3_ENDPOINT` at the
`gxy-cassiopeia-1` bucket and run the `universe static deploy` /
`universe static promote` pair.

Post-cutover from `gxy-static` (T25 — `gxy-static-k7d.25`), production DNS
for `freecode.camp` and first-party constellation hosts resolves here.

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
