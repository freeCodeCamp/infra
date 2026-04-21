# Flight Manual — gxy-static

**LEGACY — retires at gxy-cassiopeia cutover.** Kept for reference until the
cutover runbook closes. Do not ship changes to this manual beyond corrections.

Static content hosting galaxy. Serves `freecode.camp` via Caddy + R2 with
rclone-sync sidecar (pre-ADR-007-D32 design).

Last rebuild-verified: 2026-04-08.

## Phase 7: Infrastructure (ClickOps)

### 7.1 DO Droplets

- Create 3× `s-4vcpu-8gb-amd` in FRA1
- Names: `gxy-vm-static-k3s-{1,2,3}`
- Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-static-k3s`
- Cloud-init: `cloud-init/basic.yml`

### 7.2 DO Cloud Firewall

- Add tag `gxy-static-k3s` to existing `gxy-fw-fra1`

### 7.3 Tailscale

```
just play tailscale--0-install gxy_static_k3s
just play tailscale--1b-up-with-ssh gxy_static_k3s
```

Verify: `tailscale status | grep gxy-vm-static`

## Phase 8: Cluster bootstrap

```
cd k3s/gxy-static
just play k3s--bootstrap gxy_static_k3s
```

### Post-bootstrap checks

```
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff
```

## Phase 9: Caddy

### 9.1 Helm install

```
just helm-upgrade gxy-static caddy
```

Requires `caddy.values.yaml.enc` in infra-secrets (R2 credentials:
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`).

### 9.2 Deploy manifests (namespace, gateway, httproutes)

```
just deploy gxy-static caddy
```

### 9.3 Verify

```
kubectl get pods -n caddy
# 3 pods Running (2/2 containers: caddy + rclone-sync)

kubectl get gateway -n caddy
# caddy-gateway Programmed=True

kubectl get httproute -n caddy
# caddy-route

curl -sI -H "Host: freecode.camp" http://<node-public-ip>
# 302 redirect to freecodecamp.org
```

## Phase 10: DNS (ClickOps)

### 10.1 Get node public IPs

```
doctl compute droplet list --tag-name gxy-static-k3s --format Name,PublicIPv4
```

### 10.2 Cloudflare DNS

- 3× A records: `freecode.camp` → node public IPs (Proxy ON)
- 3× A records: `*.freecode.camp` → node public IPs (Proxy ON)
- SSL mode: Flexible (no origin cert)

### 10.3 Smoke test

```
curl -sI https://freecode.camp
# 302 → https://www.freecodecamp.org

curl -sI https://test.freecode.camp
# 404 (no content yet — expected)
```

## Phase 11: First static site (smoke test — raw rclone)

```bash
mkdir -p /tmp/test-site && echo '<h1>freecode.camp works</h1>' > /tmp/test-site/index.html

rclone sync /tmp/test-site :s3:gxy-static-1/test.freecode.camp/ \
  --s3-provider=Cloudflare \
  --s3-endpoint=<endpoint-from-secrets> \
  --s3-access-key-id=<key-from-secrets> \
  --s3-secret-access-key=<secret-from-secrets> \
  --s3-no-check-bucket
```

Wait ~5min for rclone sidecar sync (or
`kubectl rollout restart deployment caddy -n caddy`).

```bash
curl -s https://test.freecode.camp
# Should return the HTML
```

Teardown: `rclone purge :s3:gxy-static-1/test.freecode.camp/` (same flags as
above).

## Phase 12: Immutable deploy via universe CLI

Phase 11 validated raw R2 serving. Phase 12 validates the full deploy
pipeline: immutable deploys with alias-based promotion through the `universe`
CLI.

### 12.1 Upgrade Caddy chart (alias resolver)

```bash
cd k3s/gxy-static
just helm-upgrade gxy-static caddy
```

This deploys the alias resolver (rclone sidecar reads `production` alias
files, creates `live` symlinks) and updates Caddy to serve from `{host}/live/`.

### 12.2 Verify pods restarted

```bash
kubectl get pods -n caddy
# 3 pods Running, 2/2 containers, AGE should be recent
```

### 12.3 Create test site

```bash
mkdir -p /tmp/test-static && cd /tmp/test-static

cat > platform.yaml <<'EOF'
name: hello-world.freecode.camp
stack: static
domain:
  production: hello-world.freecode.camp
  preview: preview-hello-world.freecode.camp
EOF

mkdir dist
echo '<h1>hello from gxy-static</h1>' > dist/index.html
```

### 12.4 Deploy via CLI

Credentials from `infra-secrets/k3s/gxy-static/caddy.values.yaml.enc`
(decrypt with sops).

```bash
S3_ACCESS_KEY_ID=<from-secrets> \
S3_SECRET_ACCESS_KEY=<from-secrets> \
S3_ENDPOINT=<from-secrets> \
node ~/DEV/fCC-U/universe-cli/dist/index.js static deploy --force
```

Expected output: deploy ID, file count, preview alias set.

### 12.5 Promote to production

```bash
S3_ACCESS_KEY_ID=<from-secrets> \
S3_SECRET_ACCESS_KEY=<from-secrets> \
S3_ENDPOINT=<from-secrets> \
node ~/DEV/fCC-U/universe-cli/dist/index.js static promote
```

### 12.6 Wait for sync + verify

Wait ~5min for rclone sidecar sync, or restart the deployment to trigger
init container sync.

```bash
curl -s https://hello-world.freecode.camp
# Expected: <h1>hello from gxy-static</h1>
```

### 12.7 Teardown test site

```bash
rclone purge :s3:gxy-static-1/hello-world.freecode.camp/ \
  --s3-provider=Cloudflare \
  --s3-endpoint=<from-secrets> \
  --s3-access-key-id=<from-secrets> \
  --s3-secret-access-key=<from-secrets> \
  --s3-no-check-bucket

rm -rf /tmp/test-static
```

## Teardown

### Cluster only (preserves VMs)

```
just play k3s--teardown gxy_static_k3s
```

### Full teardown (VMs too)

```
just play k3s--teardown gxy_static_k3s
doctl compute droplet delete gxy-vm-static-k3s-1 gxy-vm-static-k3s-2 gxy-vm-static-k3s-3 --force
```

VPC, firewall, Spaces persist (shared infrastructure).

## Retirement

This galaxy retires once `gxy-cassiopeia` serves `*.freecode.camp`. The
cutover runbook is [../runbooks/dns-cutover.md](../runbooks/dns-cutover.md).
Post-cutover: archive this manual under `../../flight-manuals-archive/` and
delete the galaxy via the full teardown above.
