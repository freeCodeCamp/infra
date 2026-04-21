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

Windmill CE does not have Git Sync. Scripts, flows, and apps are managed via `wmill` CLI in a dedicated repo (`~/DEV/fCC-U/windmill`).

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

Always run from the windmill repo directory (`cd ~/DEV/fCC-U/windmill`).

**Push local → remote:**

```bash
cd ~/DEV/fCC-U/windmill
sops -d -i f/integration/apollo-11_github_app.resource.yaml   # decrypt credentials
wmill sync push --dry-run                                       # verify: all + creates, zero - deletes
wmill sync push --yes                                           # push to Windmill
sops -e -i f/integration/apollo-11_github_app.resource.yaml   # re-encrypt
```

**Pull remote → local:**

```bash
cd ~/DEV/fCC-U/windmill
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

# Part 3: gxy-launchbase

CI galaxy. Hosts Woodpecker + CNPG-backed Postgres for Universe pipeline builds.

## Pre-flight

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- [ ] All secrets decrypt OK
- [ ] age key on local machine (`~/.config/sops/age/keys.txt`)
- [ ] `infra-secrets/k3s/gxy-launchbase/` contains:
  - `woodpecker.values.yaml.enc` (chart overlay — `server.env` with OAuth + org gate)
  - `woodpecker.secrets.env.enc` (`WOODPECKER_SERVER_SECRET`, `WOODPECKER_AGENT_SECRET`, `WOODPECKER_GITHUB_CLIENT`, `WOODPECKER_GITHUB_SECRET`)
  - `woodpecker-backup.secrets.env.enc` (`ACCESS_KEY_ID`, `SECRET_ACCESS_KEY` — DO Spaces for CNPG base backups)
  - `woodpecker.tls.crt.enc` + `woodpecker.tls.key.enc` (Cloudflare Origin Certificate for `*.freecodecamp.net`, same cert as gxy-management)

## Phase 13: Infrastructure (ClickOps — codify in OpenTofu)

### 13.1 DO Droplets

- [ ] Create 3× `s-4vcpu-8gb-amd` in FRA1
- [ ] Names: `gxy-vm-launchbase-k3s-{1,2,3}`
- [ ] Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-launchbase-k3s`
- [ ] Cloud-init: `cloud-init/basic.yml`

### 13.2 DO Cloud Firewall

- [ ] Add tag `gxy-launchbase-k3s` to existing `gxy-fw-fra1`

### 13.3 Tailscale

```
just play tailscale--0-install gxy_launchbase_k3s
just play tailscale--1b-up-with-ssh gxy_launchbase_k3s
```

Verify: `tailscale status | grep gxy-vm-launchbase`

## Phase 14: Cluster Bootstrap

```
cd k3s/gxy-launchbase
just play k3s--bootstrap gxy_launchbase_k3s
```

Per-galaxy config lives in `ansible/inventory/group_vars/gxy_launchbase_k3s.yml` (cluster CIDR `10.6.0.0/16`, service CIDR `10.16.0.0/16`, `cilium_cluster_id: 3`). etcd snapshots land in `s3://net-freecodecamp-universe-backups/etcd/gxy-launchbase/` every 6h, 20 retained.

### Post-bootstrap checks

```
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff
```

## Phase 15: CNPG + Postgres Cluster

### 15.1 Install CNPG operator

```
just helm-upgrade gxy-launchbase cnpg-system
```

Chart at `k3s/gxy-launchbase/apps/cnpg-system/charts/`. The operator is cluster-scoped; installs CRDs (`Cluster`, `ScheduledBackup`, `Pooler`, etc.) and the controller in namespace `cnpg-system`.

### 15.2 Verify

```
kubectl get pods -n cnpg-system
# cnpg-controller-manager Running

just crds-grep gxy-launchbase cnpg
# postgresql.cnpg.io CRDs present
```

The `Cluster` CR and `ScheduledBackup` for `woodpecker-postgres` are part of the Woodpecker kustomize base and land in Phase 16.2.

## Phase 16: Woodpecker

### 16.1 Helm install

```
just helm-upgrade gxy-launchbase woodpecker
```

Chart at `k3s/gxy-launchbase/apps/woodpecker/charts/woodpecker/`. The sops overlay `woodpecker.values.yaml.enc` injects `server.env` with the GitHub OAuth client, `WOODPECKER_ADMIN=freeCodeCamp-bot,raisedadead,camperbot`, `WOODPECKER_ORGS=freeCodeCamp-Universe`, `WOODPECKER_OPEN=true`.

### 16.2 Deploy manifests (namespace, Postgres Cluster CR, ScheduledBackup, Gateway, HTTPRoute)

```
just deploy gxy-launchbase woodpecker
```

This decrypts `woodpecker.secrets.env.enc`, `woodpecker-backup.secrets.env.enc`, and the TLS cert pair, then applies `k3s/gxy-launchbase/apps/woodpecker/manifests/base/`:

- `namespace.yaml` — `woodpecker` namespace
- `postgres-cluster.yaml` — CNPG `Cluster` CR for `woodpecker-postgres`
- `scheduled-backup.yaml` — 6-hour base backups via `barmanObjectStore` plugin
- `gateway.yaml` — `:80` + `:443` listeners, TLS terminated with `woodpecker-tls-cloudflare`
- `httproute.yaml` — routes `woodpecker.freecodecamp.net` to the Woodpecker server

Wait for the CNPG cluster to settle before Woodpecker pods recover:

```
just cnpg-wait gxy-launchbase woodpecker woodpecker-postgres
```

### 16.3 Verify

```
kubectl get pods -n woodpecker
# woodpecker-server, woodpecker-agent-*, woodpecker-postgres-{1,2,3} Running

kubectl get cluster -n woodpecker
# woodpecker-postgres  3/3 instances Ready

kubectl get scheduledbackup -n woodpecker
# woodpecker-postgres-base  schedule 0 0 0,6,12,18 * * *

kubectl get gateway -n woodpecker
# woodpecker-gateway Programmed=True

kubectl get httproute -n woodpecker
# woodpecker-route
```

## Phase 17: DNS + Cloudflare Access

### 17.1 Get node public IPs

```
doctl compute droplet list --tag-name gxy-launchbase-k3s --format Name,PublicIPv4
```

### 17.2 Cloudflare DNS

- [ ] 3× A records: `woodpecker.freecodecamp.net` → launchbase node public IPs
- [ ] Proxy: ON (orange cloud)
- [ ] SSL mode: Full (Strict)

Without the Cloudflare Origin Certificate at the origin, Traefik serves `CN=TRAEFIK DEFAULT CERT` and CF Full (Strict) rejects the origin with error 526 — the cert in `woodpecker-tls-cloudflare` (Phase 16.2) is what prevents that.

### 17.3 Cloudflare Access

Cloudflare Access is intentionally **off** for this deployment — the GitHub-org gate (`WOODPECKER_ORGS=freeCodeCamp-Universe` + `WOODPECKER_OPEN=true`) is deemed sufficient for letting staff in without an extra OTP layer.

To re-enable CF Access (narrower team/email gate), follow `docs/runbook/gxy-launchbase.md` — that runbook is the authoritative reference for the Access application. Treat its ordering as advisory (Access app saved BEFORE DNS publication) only when you re-enable it.

A dedicated runbook split (OAuth app provisioning vs CF Access re-enable) is pending — tracked as `gxy-static-k7d.32`.

### 17.4 Smoke test

```
curl -sI https://woodpecker.freecodecamp.net
# 200 (or 302 to *.cloudflareaccess.com if CF Access is back in front)
```

- [ ] Browser: visit `https://woodpecker.freecodecamp.net`
- [ ] Log in via GitHub — OAuth grant page shows `freeCodeCamp-Universe` scope

## Phase 18: OAuth app provisioning

A dedicated runbook (`docs/runbook/woodpecker-oauth-app.md`) is TBD when `gxy-static-k7d.10` closes. Until then, the inline procedure is:

1. GitHub → `freeCodeCamp-Universe` org → Settings → Developer settings → OAuth Apps → New OAuth App
2. Application name: `Woodpecker CI`
3. Homepage URL: `https://woodpecker.freecodecamp.net`
4. Authorization callback URL: `https://woodpecker.freecodecamp.net/authorize`
5. Copy Client ID + Client Secret into `infra-secrets/k3s/gxy-launchbase/woodpecker.values.yaml.enc` under `server.env.WOODPECKER_GITHUB_CLIENT` + `server.env.WOODPECKER_GITHUB_SECRET`
6. Mutate via `sops --input-type yaml --output-type yaml <file>` — `sops <file>` auto-detects `.enc` as binary and errors out
7. Re-run `just helm-upgrade gxy-launchbase woodpecker` to roll the new credentials into the chart

## Backups

### What is backed up

| Data                 | Method                                          | Schedule                | Storage                                                       | Restore time                   |
| -------------------- | ----------------------------------------------- | ----------------------- | ------------------------------------------------------------- | ------------------------------ |
| etcd (cluster state) | k3s built-in S3 snapshots                       | Every 6h, 20 retained   | `s3://net-freecodecamp-universe-backups/etcd/gxy-launchbase/` | Minutes (k3s native restore)   |
| woodpecker-postgres  | CNPG base backup + continuous WAL (R2)          | 6h base, WAL continuous | R2 bucket via `barmanObjectStore` plugin                      | Minutes–hours (PITR)           |
| Woodpecker app state | Not backed up — reproduced from Postgres        | N/A                     | N/A                                                           | Re-attach chart to restored DB |
| Helm releases        | Not backed up — reproducible from values        | N/A                     | infra repo                                                    | `just helm-upgrade`            |
| TLS certs, secrets   | Not backed up — reproducible from infra-secrets | N/A                     | infra-secrets repo                                            | `just deploy`                  |

CNPG base backups are scheduled by the `woodpecker-postgres-base` `ScheduledBackup` CR (6-hour cadence, aligns with etcd snapshots for consistent recovery planning). WAL archiving runs continuously.

The earlier `barmanObjectStore` native mode was deprecated in CNPG ≥ 1.26; the plugin-based replacement is now the default. If the cluster ever deadlocks on `restore_command`, drop `spec.backup` from the `Cluster` CR temporarily and re-apply the `ScheduledBackup` after the cluster is healthy. A belt-and-braces weekly `pg_dump` export remains an operator-side compensating control until plugin operation has a few months of track record.

### Restore woodpecker-postgres from backup

Recovery from the latest base backup + WAL replay:

```
kubectl delete cluster -n woodpecker woodpecker-postgres
# Re-apply the Cluster CR with spec.bootstrap.recovery pointing at the same
# barman-cloud backup source — see CNPG recovery docs.
kubectl apply -k k3s/gxy-launchbase/apps/woodpecker/manifests/base/
just cnpg-wait gxy-launchbase woodpecker woodpecker-postgres
```

For a full cluster-reset drill see [CNPG recovery](https://cloudnative-pg.io/documentation/current/recovery/).

### Restore etcd from S3

Same procedure as gxy-management Phase 1 — see `# Part 1: gxy-management` → `Restore etcd from S3`. Substitute `etcd/gxy-launchbase` for the folder.

## Usage — first pipeline

1. In the Woodpecker UI, hit **Add repository** and pick a repo under `freeCodeCamp-Universe` (OAuth grant must include that org).
2. Drop a minimal `.woodpecker.yaml` in the repo:

   ```yaml
   steps:
     smoke:
       image: alpine:3.20
       commands:
         - echo "pipeline runs on gxy-launchbase"
   ```

3. Push to a branch → Woodpecker picks it up → pipeline runs on the agent.
4. Confirm via `kubectl logs -n woodpecker deploy/woodpecker-agent` (or via the UI).

Scale agents by editing `server.env.WOODPECKER_MAX_WORKFLOWS` in the sops overlay, then re-run `just helm-upgrade gxy-launchbase woodpecker`.

---

# Part 4: gxy-cassiopeia

Production static galaxy. Serves Universe constellations (e.g. `freecode.camp` cutover target, first-party sites) via Caddy + R2. Replaces `gxy-static` once T25 cutover closes.

## Pre-flight

```
cd ~/DEV/fCC/infra
just ansible-install
just secret-verify-all
```

- [ ] All secrets decrypt OK
- [ ] age key on local machine (`~/.config/sops/age/keys.txt`)
- [ ] `infra-secrets/k3s/gxy-cassiopeia/` contains:
  - `caddy.values.yaml.enc` (R2 credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`)
  - `r2-rw.env.enc` + `r2-ro.env.enc` (bucket-scoped key pair for `just r2-bucket-verify`)

## Phase 19: Infrastructure (ClickOps)

### 19.1 DO Droplets

- [ ] Create 3× `s-4vcpu-8gb-amd` in FRA1
- [ ] Names: `gxy-vm-cassiopeia-k3s-{1,2,3}`
- [ ] Image: Ubuntu 24.04, VPC: `universe-vpc-fra1`, Tag: `gxy-cassiopeia-k3s`
- [ ] Cloud-init: `cloud-init/basic.yml`

No OpenTofu workspace exists for gxy-cassiopeia yet — provisioning is DO dashboard today, codify as a follow-up when the layout stabilises post-cutover.

### 19.2 DO Cloud Firewall

- [ ] Add tag `gxy-cassiopeia-k3s` to existing `gxy-fw-fra1`

### 19.3 Tailscale

```
just play tailscale--0-install gxy_cassiopeia_k3s
just play tailscale--1b-up-with-ssh gxy_cassiopeia_k3s
```

Verify: `tailscale status | grep gxy-vm-cassiopeia`

## Phase 20: Cluster Bootstrap

```
cd k3s/gxy-cassiopeia
just play k3s--bootstrap gxy_cassiopeia_k3s
```

Per-galaxy config in `ansible/inventory/group_vars/gxy_cassiopeia_k3s.yml` (cluster CIDR `10.7.0.0/16`, service CIDR `10.17.0.0/16`, `cilium_cluster_id: 4`). etcd snapshots land in `s3://net-freecodecamp-universe-backups/etcd/gxy-cassiopeia/`.

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

Local chart at `k3s/gxy-cassiopeia/apps/caddy/charts/caddy/`. The chart templates Gateway + HTTPRoute + NetworkPolicy + the Caddy Deployment with rclone-sync sidecar. Chart defaults are overlaid by `k3s/gxy-cassiopeia/apps/caddy/values.production.yaml` (image tag pin, per-site host list) and then by the sops overlay `caddy.values.yaml.enc` (R2 credentials).

Caddy image is `ghcr.io/freecodecamp-universe/caddy-s3:{sha}`, built by the Woodpecker pipeline `.woodpecker/caddy-s3-build.yaml` (in-tree r2alias module via xcaddy; no third-party Caddy plugins per D32). Local dev builds via `just caddy-s3-build` + verify with `just caddy-s3-verify`.

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

Provision bucket `gxy-cassiopeia-1` (versioning enabled, per-site rw/ro keys) per `docs/runbook/r2-bucket-provision.md`. Store the key pair encrypted at `infra-secrets/k3s/gxy-cassiopeia/r2-{rw,ro}.env.enc`.

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

- [ ] 3× A records per production domain → cassiopeia node public IPs (Proxy ON)
- [ ] SSL mode: Full (Strict) for domains with origin cert, Flexible otherwise

Use `just cf-dns-cutover <zone> <ips>` for declarative zone flips (see `docs/runbook/dns-cutover.md`). Run `just cutover-preflight` first — it exits non-zero on any failing site.

### 23.3 Origin allow-list

Cron + manifest to keep only Cloudflare edge IPs on the origin firewall is TBD when `gxy-static-k7d.14` closes. Until then, the cluster firewall (`gxy-fw-fra1`) accepts 80/443 from the public internet; CF WAF is the only layer gating origin hits.

## Phase 24: First deploy via Woodpecker pipeline

The production pipeline template (build artifact → push to R2 with deploy ID → promote via `universe` CLI) is TBD when `gxy-static-k7d.21` closes. Until then, immutable deploy + alias promotion flow is the same as `# Part 2: gxy-static` Phase 12 — point `S3_ENDPOINT` at the `gxy-cassiopeia-1` bucket and run the `universe static deploy` / `universe static promote` pair.

Post-cutover from `gxy-static` (T25 — `gxy-static-k7d.25`), production DNS for `freecode.camp` and first-party constellation hosts resolves here.

## Troubleshooting

### Alias cache invalidation

rclone sidecar syncs `production`/`preview` aliases every ~5 minutes. Force a sync by restarting the deployment:

```
kubectl rollout restart deployment -n caddy caddy
```

### R2 503s

- Check R2 status page first. The `caddy-s3` in-tree module surfaces upstream 503s as 502 to the client.
- If the bucket is healthy: `kubectl logs -n caddy deploy/caddy -c rclone-sync` to inspect the last sync cycle.
- Fall back to serving from the previous deploy ID by running `universe static promote --to <previous-deploy-id>`.

### CF cache purge

After a promote, CF edge still serves the old alias for the cache TTL:

- Zone-wide purge: CF dashboard → Caching → Configuration → Purge Everything (use sparingly).
- Targeted purge: API `POST /zones/{id}/purge_cache` with `{ "files": [...] }` for the specific URLs.

---

# Post-M5 Hetzner migration

`gxy-launchbase` and `gxy-cassiopeia` both run on DO FRA1 today (per ADR-003 for Woodpecker/CNPG and ADR-007 D32 for static v2). Both galaxies migrate to Hetzner post-M5 — tracked as `gxy-static-k7d.30` (**deferred**).

**Constraint:** the Talos / k0s distro evaluation must close before any Hetzner provisioning begins. Do not open a Hetzner project, cut DNS, or rebuild state on Hetzner until `gxy-static-k7d.30` lands. A premature migration locks the distro choice and strands any etcd state on the source cluster.

When the evaluation closes, a dedicated migration runbook lands in `docs/runbook/` and gets linked from this section.

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

## gxy-launchbase Teardown

Destructive: this kills the CNPG cluster and Woodpecker state. Export any
needed pipeline state before teardown.

### Cluster only (preserves VMs)

```
just play k3s--teardown gxy_launchbase_k3s
```

### Full teardown (VMs too)

```
just play k3s--teardown gxy_launchbase_k3s
doctl compute droplet delete gxy-vm-launchbase-k3s-1 gxy-vm-launchbase-k3s-2 gxy-vm-launchbase-k3s-3 --force
```

Also pull the DNS records for `woodpecker.freecodecamp.net`. CF Access is off
for this deployment, so no Access application to delete — only re-enable if
`docs/runbook/gxy-launchbase.md` was followed to turn it on.

## gxy-cassiopeia Teardown

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

R2 buckets, VPC, firewall, Spaces persist (shared infrastructure).

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
