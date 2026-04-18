# Universe Flight Manual

Rebuild the entire Universe platform from scratch. Each phase is sequenced — do not skip ahead. ClickOps steps will be codified into OpenTofu later.

# Part 1: gxy-management

## Pre-flight

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- [ ] All secrets decrypt OK
- [ ] age key on local machine (`~/.config/sops/age/keys.txt`)
- [ ] Cloudflare origin cert + key in `infra-secrets/k3s/gxy-management/`

## Phase 1: Infrastructure (ClickOps — codify in OpenTofu)

### 1.1 DO VPC

- [ ] Create VPC `universe-vpc-fra1` in FRA1, CIDR `10.110.0.0/20`

### 1.2 DO Droplets

- [ ] Create 3x `s-8vcpu-16gb-amd` in FRA1
- [ ] Names: `gxy-vm-mgmt-k3s-{1,2,3}`
- [ ] Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-mgmt-k3s`
- [ ] Cloud-init: `cloud-init/basic.yml`

### 1.3 DO Cloud Firewall

- [ ] Create firewall `gxy-fw-fra1`, attach to tag `gxy-mgmt-k3s`
- [ ] VPC rules (source 10.110.0.0/20): 2379-2380, 4240, 4244, 5001, 6443, 8472, 10250
- [ ] Public rules: 22/TCP, 80/TCP, 443/TCP

### 1.4 DO Spaces

- [ ] Bucket `net-freecodecamp-universe-backups` in FRA1 (etcd snapshots + Windmill backups)

### 1.5 Tailscale

```
just play tailscale--0-install gxy_mgmt_k3s
just play tailscale--1b-up-with-ssh gxy_mgmt_k3s
```

Verify from local:

```
tailscale status | grep gxy-vm-mgmt
```

All 3 nodes should show as connected.

## Phase 2: Cluster Bootstrap (Automated)

```
cd k3s/gxy-management
just play k3s--bootstrap gxy_mgmt_k3s
```

This runs 5 plays: validate → prerequisites → k3s deploy → Cilium → verify + kubeconfig.

### Post-bootstrap checks

```
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl top nodes
# All 3 reporting CPU/memory (metrics-server working)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff

kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium-health status
# 3/3 reachable, all endpoints 1/1
```

## Phase 3: Windmill

### 3.1 Helm install

```
just helm-upgrade gxy-management windmill
```

### 3.2 Gateway + TLS manifests

```
just deploy gxy-management windmill
```

### 3.3 Verify

```
kubectl get pods -n windmill
# 6 pods Running (app, 2x workers-default, workers-native, extra, postgresql)

kubectl get gateway -n windmill
# windmill-gateway Programmed=True

kubectl get httproute -n windmill
# windmill-route, http-redirect

kubectl get svc -n kube-system traefik
# EXTERNAL-IP shows all 3 node VPC IPs
```

## Phase 4: DNS + Access (ClickOps — codify in OpenTofu)

### 4.1 Get node public IPs

```
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="ExternalIP")].address}{"\n"}{end}'
```

If no ExternalIP (DO doesn't always populate it):

```
doctl compute droplet list --tag-name gxy-mgmt-k3s --format Name,PublicIPv4
```

### 4.2 Cloudflare DNS

- [ ] A record: `windmill.freecodecamp.net` → node 1 public IP
- [ ] A record: `windmill.freecodecamp.net` → node 2 public IP
- [ ] A record: `windmill.freecodecamp.net` → node 3 public IP
- [ ] Proxy: ON (orange cloud)
- [ ] SSL mode: Full (Strict)

### 4.3 Cloudflare Access (deferred)

- [ ] Create Access application for `windmill.freecodecamp.net`
- [ ] Policy: email OTP, allow all `@freecodecamp.org`

### 4.4 Smoke test

```
curl -sI https://windmill.freecodecamp.net
# Should return 200
```

- [ ] Browser: visit `https://windmill.freecodecamp.net`
- [ ] Windmill login page loads

## Phase 5: ArgoCD

### 5.1 Deploy

```
just helm-upgrade gxy-management argocd
just deploy gxy-management argocd
```

### 5.2 Verify

```
kubectl get pods -n argocd
# All Running

kubectl get gateway -n argocd
kubectl get httproute -n argocd
```

### 5.3 DNS + Access

- [ ] A records: `argocd.freecodecamp.net` → same 3 node public IPs
- [ ] Cloudflare Access application (deferred)

### 5.4 Get initial admin password

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Phase 6: Zot (deferred — Phase 1)

### 6.1 Deploy

```
just helm-upgrade gxy-management zot
just deploy gxy-management zot
```

### 6.2 Verify

```
kubectl get pods -n zot
# All Running

kubectl get gateway -n zot
kubectl get httproute -n zot
```

### 6.3 DNS + Access

- [ ] A records: `zot.freecodecamp.net` → same 3 node public IPs
- [ ] Cloudflare Access application (same pattern)

### 6.4 Smoke test

```
curl -s https://zot.freecodecamp.net/v2/ | head
# Should return OCI registry response
```

## Backups

### What is backed up

| Data                 | Method                                            | Schedule                    | Storage                                                           | Restore time                 |
| -------------------- | ------------------------------------------------- | --------------------------- | ----------------------------------------------------------------- | ---------------------------- |
| etcd (cluster state) | k3s built-in S3 snapshots                         | Every 6h, 20 retained       | `s3://net-freecodecamp-universe-backups/etcd/gxy-management/`     | Minutes (k3s native restore) |
| Windmill PostgreSQL  | CronJob pg_dump → S3 (not yet active)             | Daily 02:00 UTC, 7 retained | `s3://net-freecodecamp-universe-backups/windmill/gxy-management/` | Minutes (pg_restore)         |
| ArgoCD               | Not backed up — state is in git                   | N/A                         | N/A                                                               | Re-deploy from git           |
| Zot (deferred)       | Not backed up — images stored on S3               | N/A                         | DO Spaces (primary storage)                                       | N/A                          |
| Helm releases        | Not backed up — reproducible from values + charts | N/A                         | infra repo                                                        | `just helm-upgrade`          |
| TLS certs, secrets   | Not backed up — reproducible from infra-secrets   | N/A                         | infra-secrets repo                                                | `just deploy`                |

### Ad-hoc Windmill backup (before maintenance)

```
just windmill-backup gxy-management
```

This runs pg_dump inside the PostgreSQL pod and saves to `k3s/gxy-management/.backups/`. Run before any Helm upgrade, teardown, or PostgreSQL change.

### Automated Windmill backup (CronJob)

The CronJob manifest exists but is **not yet active**. To activate:

1. Create `windmill-backup.secrets.env.enc` in infra-secrets (fill PG_PASSWORD + S3 creds from sample)
2. Deploy:

```
just deploy gxy-management windmill
```

The CronJob (once active):

- Runs daily at 02:00 UTC
- Dumps Windmill PostgreSQL via pg_dumpall
- Compresses with gzip
- Uploads to DO Spaces (`windmill/gxy-management/windmill-YYYYMMDD-HHMMSS.sql.gz`)
- Deletes backups older than 7 days from S3
- Secret `windmill-backup-s3` is generated by kustomization from `.backup-secrets.env`

Verify CronJob is running:

```
kubectl get cronjob -n windmill
# windmill-backup   0 2 * * *   ...

kubectl get jobs -n windmill --sort-by=.metadata.creationTimestamp
# Most recent job should show Completed
```

### Restore Windmill from backup

Find the PostgreSQL pod first (chart 4.x uses inline template, not Bitnami subchart):

```
PG_POD=$(kubectl get pod -n windmill -l app=windmill-postgresql-demo-app -o jsonpath='{.items[0].metadata.name}')
```

**From ad-hoc backup (local file):**

```
kubectl cp k3s/gxy-management/.backups/windmill-YYYYMMDD.sql.gz windmill/${PG_POD}:/tmp/
kubectl exec -n windmill ${PG_POD} -- bash -c \
  'gunzip -c /tmp/windmill-YYYYMMDD.sql.gz | psql -U postgres'
```

**From S3 backup:**

```
s3cmd get s3://net-freecodecamp-universe-backups/windmill/gxy-management/windmill-YYYYMMDD-HHMMSS.sql.gz /tmp/
kubectl cp /tmp/windmill-YYYYMMDD-HHMMSS.sql.gz windmill/${PG_POD}:/tmp/
kubectl exec -n windmill ${PG_POD} -- bash -c \
  'gunzip -c /tmp/windmill-YYYYMMDD-HHMMSS.sql.gz | psql -U postgres'
```

**After restore:** Restart Windmill pods to pick up restored data:

```
kubectl rollout restart deployment -n windmill -l app.kubernetes.io/name=windmill
```

### Restore etcd from S3

If the entire cluster is lost and needs rebuilding from etcd snapshot:

```
# List available snapshots
k3s etcd-snapshot list --s3 \
  --s3-bucket net-freecodecamp-universe-backups \
  --s3-folder etcd/gxy-management \
  --s3-endpoint fra1.digitaloceanspaces.com \
  --s3-region fra1

# Restore (run on the --cluster-init node only)
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=s3://net-freecodecamp-universe-backups/etcd/gxy-management/SNAPSHOT_NAME
```

Then rejoin the other nodes. See [k3s backup/restore docs](https://docs.k3s.io/datastore/backup-restore).

### Verify backups

After setting up automated backups, verify monthly:

- [ ] Check CronJob last success: `kubectl get cronjob -n windmill`
- [ ] List S3 backups: `s3cmd ls s3://net-freecodecamp-universe-backups/windmill/gxy-management/`
- [ ] Test restore to a scratch database (not production)
- [ ] Confirm etcd snapshots: `k3s etcd-snapshot list --s3 ...`

### Migration to CNPG (production path)

The bundled PostgreSQL (Windmill chart inline template) is single-instance with no replication, no WAL archiving, and no PITR. For production:

1. Deploy CloudNativePG operator on gxy-management
2. Create a CNPG Cluster resource with S3 WAL archiving (same DO Spaces bucket)
3. pg_dump from bundled PostgreSQL → pg_restore into CNPG cluster
4. Update Windmill `databaseUrl` to point to CNPG service
5. Remove the bundled PostgreSQL (set `postgresql.enabled: false` in Helm values)

CNPG provides: continuous WAL archiving, PITR, automated base backups, replica failover. This replaces both the CronJob and the bundled PostgreSQL.

---

## Windmill IaC (CLI Sync)

Windmill CE does not have Git Sync. Scripts, flows, and apps are managed via `wmill` CLI in a dedicated repo (`~/DEV/fCC/windmill`).

### Repository structure

```
wmill.yaml                              # CLI config, branch → workspace mapping
.sops.yaml                              # sops+age encryption rules for resources
github_app.resource-type.yaml           # Custom resource type definitions (repo root)
f/
  <folder>/
    folder.meta.yaml                    # Required — folder permissions
    <script>.deno.ts                    # Code (.deno.ts = Deno, .ts = Bun)
    <script>.script.yaml                # Metadata (summary, schema, lock ref)
    <script>.script.lock                # Dependency lockfile
  integration/
    apollo-11_github_app.resource.yaml  # sops-encrypted credentials
```

### Sync workflow

Always run from the windmill repo directory (`cd ~/DEV/fCC/windmill`).

**Push local → remote:**

```bash
cd ~/DEV/fCC/windmill
sops -d -i f/integration/apollo-11_github_app.resource.yaml   # decrypt credentials
wmill sync push --dry-run                                       # verify: all + creates, zero - deletes
wmill sync push --yes                                           # push to Windmill
sops -e -i f/integration/apollo-11_github_app.resource.yaml   # re-encrypt
```

**Pull remote → local:**

```bash
cd ~/DEV/fCC/windmill
wmill sync pull
sops -e -i f/integration/apollo-11_github_app.resource.yaml   # encrypt before committing
```

**Regenerate metadata after code changes:**

```bash
wmill generate-metadata
```

### Branch strategy

- `main` — config only (`wmill.yaml`, `.sops.yaml`, `.gitignore`)
- `gxy-management` — scripts, flows, apps for the gxy-management workspace

### Critical warnings

- **NEVER run `wmill sync push` from the wrong directory.** "No wmill.yaml found" = wrong directory. Without config, push sees empty local state and deletes everything remote.
- **ALWAYS decrypt resources before push, re-encrypt after.** Pushing encrypted ciphertext stores `ENC[AES256_GCM,...]` as literal values in Windmill.
- **ALWAYS use `--dry-run` first.** Review that changes show `+` (creates) or `~` (updates), not `-` (deletes of resources you want to keep).

# Part 2: gxy-static

Static content hosting galaxy. Serves `freecode.camp` via Caddy + R2.

## Phase 7: Infrastructure (ClickOps)

### 7.1 DO Droplets

- [ ] Create 3× `s-4vcpu-8gb-amd` in FRA1
- [ ] Names: `gxy-vm-static-k3s-{1,2,3}`
- [ ] Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-static-k3s`
- [ ] Cloud-init: `cloud-init/basic.yml`

### 7.2 DO Cloud Firewall

- [ ] Add tag `gxy-static-k3s` to existing `gxy-fw-fra1`

### 7.3 Tailscale

```
just play tailscale--0-install gxy_static_k3s
just play tailscale--1b-up-with-ssh gxy_static_k3s
```

Verify: `tailscale status | grep gxy-vm-static`

## Phase 8: Cluster Bootstrap

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

Requires `caddy.values.yaml.enc` in infra-secrets (R2 credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`).

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

- [ ] 3× A records: `freecode.camp` → node public IPs (Proxy ON)
- [ ] 3× A records: `*.freecode.camp` → node public IPs (Proxy ON)
- [ ] SSL mode: Flexible (no origin cert)

### 10.3 Smoke test

```
curl -sI https://freecode.camp
# 302 → https://www.freecodecamp.org

curl -sI https://test.freecode.camp
# 404 (no content yet — expected)
```

## Phase 11: First Static Site (smoke test — raw rclone)

```bash
mkdir -p /tmp/test-site && echo '<h1>freecode.camp works</h1>' > /tmp/test-site/index.html

rclone sync /tmp/test-site :s3:gxy-static-1/test.freecode.camp/ \
  --s3-provider=Cloudflare \
  --s3-endpoint=<endpoint-from-secrets> \
  --s3-access-key-id=<key-from-secrets> \
  --s3-secret-access-key=<secret-from-secrets> \
  --s3-no-check-bucket
```

Wait ~5min for rclone sidecar sync (or `kubectl rollout restart deployment caddy -n caddy`).

```bash
curl -s https://test.freecode.camp
# Should return the HTML
```

Teardown: `rclone purge :s3:gxy-static-1/test.freecode.camp/` (same flags as above).

## Phase 12: Immutable Deploy via Universe CLI

Phase 11 validated raw R2 serving. Phase 12 validates the full deploy pipeline: immutable deploys with alias-based promotion through the `universe` CLI.

### 12.1 Upgrade Caddy chart (alias resolver)

```bash
cd k3s/gxy-static
just helm-upgrade gxy-static caddy
```

This deploys the alias resolver (rclone sidecar reads `production` alias files, creates `live` symlinks) and updates Caddy to serve from `{host}/live/`.

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

Credentials from `infra-secrets/k3s/gxy-static/caddy.values.yaml.enc` (decrypt with sops).

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

Wait ~5min for rclone sidecar sync, or restart the deployment to trigger init container sync.

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

---

# Teardowns

## gxy-management Teardown

### Cluster only (preserves VMs)

```
just play k3s--teardown gxy_mgmt_k3s
```

### Full teardown (VMs too)

```
just play k3s--teardown gxy_mgmt_k3s
doctl compute droplet delete gxy-vm-mgmt-k3s-1 gxy-vm-mgmt-k3s-2 gxy-vm-mgmt-k3s-3 --force
```

## gxy-static Teardown

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

---

## Known Issues

| Issue                          | Workaround                               | See                         |
| ------------------------------ | ---------------------------------------- | --------------------------- |
| Pod→nodeVPCIP broken           | `hostNetwork: true` for monitoring       | Field notes Failure 8b      |
| Cilium picks up tailscale0 MTU | Pin `devices: [eth0, eth1]`, `mtu: 1500` | Field notes Failure 8a      |
| DO native routing blocked      | Use VXLAN tunnel (DO anti-spoofing)      | Field notes Cilium pitfalls |

**Resolved:** `kubeProxyReplacement: true` works on k3s HA when devices/MTU are pinned. Failure 7 was a misdiagnosis (root cause: MTU pollution). See field notes.

---

## Lifecycle Calendar

Third-party pins with known end-of-life windows. Rolling these forward is an explicit task in the backlog — not something that happens automatically.

| Component     | Current pin               | EOL / stale-after        | Action window    | Notes                                                                                               |
| ------------- | ------------------------- | ------------------------ | ---------------- | --------------------------------------------------------------------------------------------------- |
| k3s           | `v1.34.5+k3s1`            | 2026-10-27               | by Sept 2026     | All galaxies. Plan 1.35 upgrade (k3s tracks upstream Kubernetes). Test on gxy-management first.     |
| Caddy         | `v2.11.2`                 | CVE-driven               | 14 days per D30  | Bump via PR with regression tests. Tracked by Windmill reminder (filed post-M1).                    |
| Woodpecker    | `v3.13.0`                 | Community-driven         | On minor release | gxy-launchbase. CLI Woodpecker client in universe-cli is isolated for quick swap if project stalls. |
| CloudNativePG | chart `0.28` / `1.29` op  | 1.28 EOL 2026-06-30      | During `1.29.x`  | gxy-launchbase. Rolling in place via operator-guided pg_upgrade.                                    |
| Cilium        | chart default (1.19 line) | 3-minor community window | On minor bump    | All galaxies. Bump behind feature-gate tests.                                                       |

When a pin crosses its action window, create a beads task in the relevant epic and announce in the platform-team channel.
