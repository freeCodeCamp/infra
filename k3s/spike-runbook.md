# Rancher Spike Runbook

> Migrates Appsmith to Rancher-managed ops-backoffice cluster with DNS cutover. Validates architecture with live production traffic before migrating remaining apps.

## Prerequisites

- [ ] DigitalOcean account with API token (`DO_API_TOKEN`)
- [ ] DO Spaces bucket: `net.freecodecamp.ops-k3s-backups` (nyc3)
- [ ] DO Spaces access key + secret key (S3-compatible)
- [ ] Tailscale account with OAuth client ID + secret (tag: `tag:k8s`)
- [ ] Tailscale ACL `autoApprovers` configured for `10.40.0.0/16`, `10.41.0.0/16`, `10.42.0.0/16`, `10.43.0.0/16`
- [ ] Helm 3.x installed locally
- [ ] Ansible installed (`uv run ansible-playbook` from `ansible/`)
- [ ] Cloudflare origin cert + key for `appsmith.freecodecamp.net`
- [ ] Existing Appsmith secrets from `ops-backoffice-tools` (encryption keys, MongoDB Atlas URL)
- [ ] Cloudflare API token or dashboard access for DNS updates

---

## Phase 1: ops-mgmt Cluster

Single-node k3s cluster running Rancher, cert-manager, and rancher-backup.

| Property     | Value                              |
| ------------ | ---------------------------------- |
| Node         | 1x s-4vcpu-8gb, Ubuntu 24.04, nyc3 |
| k3s version  | v1.34.4+k3s1                       |
| Pod CIDR     | 10.40.0.0/16                       |
| Service CIDR | 10.41.0.0/16                       |
| Rancher      | v2.13.2                            |
| Tailscale    | ops-k3s-mgmt-subnet                |

### 1.1 Provision DigitalOcean Droplet

1. Use existing VPC: `ops-vpc-k3s-nyc3` in nyc3
2. Create droplet:
   - Size: `s-4vcpu-8gb`
   - Image: Ubuntu 24.04
   - Region: nyc3
   - VPC: `ops-vpc-k3s-nyc3`
   - Tag: `mgmt_k3s`
3. Install Tailscale using existing playbook:
   ```bash
   ansible-playbook -i inventory/digitalocean.yml play-tailscale--0-install.yml \
     -e variable_host=mgmt_k3s
   ```

### 1.2 Populate Ansible Vault

Ensure vault password file exists:

```bash
# One-time setup (if not done already)
openssl rand -base64 32 > ~/.vault-password-fcc-infra
chmod 600 ~/.vault-password-fcc-infra
```

Edit vault secrets:

```bash
cd /Users/mrugesh/DEV/fCC/infra/ansible
ansible-vault edit vars/vault-k3s.yml
```

Required values:

- `vault_do_spaces_access_key` — DO Spaces access key
- `vault_do_spaces_secret_key` — DO Spaces secret key
- `vault_tailscale_oauth_client_id` — Tailscale OAuth client ID (tag: tag:k8s)
- `vault_tailscale_oauth_client_secret` — Tailscale OAuth client secret
- `vault_rancher_bootstrap_password` — generate with `openssl rand -hex 16`

### 1.3 Deploy ops-mgmt Cluster

One command deploys everything: k3s, security hardening, Rancher, Tailscale operator, and fetches kubeconfig.

```bash
cd /Users/mrugesh/DEV/fCC/infra/ansible
source .venv/bin/activate
ansible-playbook -i inventory/digitalocean.yml play-k3s--ops-mgmt.yml \
  -e variable_host=mgmt_k3s
```

This playbook (7 plays):

1. Validates VPC + Tailscale + vault secrets, creates DO firewall
2. Installs system prerequisites
3. Deploys k3s v1.34.4 with security hardening (secrets-encryption, PSS, audit logging)
4. Configures Traefik + Gateway API CRDs v1.4.1
5. Installs cert-manager, Rancher v2.13.2, rancher-backup operator + schedule
6. Installs Tailscale operator + ProxyClass (MTU fix) + Connector (subnet router)
7. Fetches kubeconfig to `k3s/ops-mgmt/.kubeconfig.yaml` (Tailscale IP)

### 1.4 Verify

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-mgmt && export $(cat .env | xargs)

# Cluster health
kubectl get nodes
kubectl get pods -A

# Security
ssh root@<node> "k3s secrets-encrypt status"
# Expected: Encryption Status: Enabled

ssh root@<node> "ls -la /var/log/k3s/audit.log"
# Expected: file exists

# Firewall
doctl compute firewall list --format Name,Status
# Expected: ops-fw-k3s-mgmt, succeeded

# Rancher
curl -sk https://rancher.ops-mgmt.ts.net | head -c 100

# Tailscale
kubectl get connector cluster-subnet-router
# Check tailnet admin for ops-k3s-mgmt-subnet

# Backups
kubectl get backups.resources.cattle.io -n cattle-resources-system
ssh root@<node> "k3s etcd-snapshot list"
```

### 1.5 Post-Install (Manual)

1. Open Rancher UI: `https://rancher.ops-mgmt.ts.net`
2. Set permanent admin password on first login
3. Navigate to: Cluster Management > Cloud Credentials > Create
4. Type: DigitalOcean
5. Paste `DO_API_TOKEN`

### Phase 1 Checklist

- [ ] k3s node shows `Ready`
- [ ] Rancher UI accessible at `https://rancher.ops-mgmt.ts.net`
- [ ] cert-manager pods running in `cert-manager` namespace
- [ ] rancher-backup operator running in `cattle-resources-system` namespace
- [ ] Tailscale Connector `ops-k3s-mgmt-subnet` visible in tailnet admin
- [ ] etcd S3 snapshots present in DO Spaces (`etcd/ops-mgmt/`)
- [ ] DO cloud credential configured in Rancher
- [ ] DO Firewall `ops-fw-k3s-mgmt` active (SSH + API via Tailscale only)
- [ ] k3s secrets-encryption enabled
- [ ] Audit log active at `/var/log/k3s/audit.log`
- [ ] PSS baseline enforced (check with: `kubectl get ns default -o yaml | grep pod-security`)

---

## Phase 2: ops-backoffice Cluster (via Rancher)

Rancher-provisioned 3-node k3s cluster for Appsmith workloads.

| Property     | Value                              |
| ------------ | ---------------------------------- |
| Nodes        | 3x s-4vcpu-8gb, Ubuntu 24.04, nyc3 |
| k3s version  | v1.34.4                            |
| Pod CIDR     | 10.42.0.0/16                       |
| Service CIDR | 10.43.0.0/16                       |
| Tailscale    | ops-k3s-backoffice-subnet          |
| Longhorn     | Default StorageClass, 2 replicas   |

### 2.1 Create Cluster in Rancher UI

1. Rancher UI > Cluster Management > Create
2. Provider: DigitalOcean
3. Settings:
   - **Cluster name**: `ops-backoffice`
   - **Kubernetes version**: k3s v1.34.4
   - **Machine pools**: 3x `s-4vcpu-8gb`, nyc3, same VPC as ops-mgmt
4. Advanced > Cluster Configuration:
   - `cluster-cidr`: `10.42.0.0/16`
   - `service-cidr`: `10.43.0.0/16`
   - etcd S3 backup:
     - Enable
     - Endpoint: `nyc3.digitaloceanspaces.com`
     - Bucket: `net.freecodecamp.ops-k3s-backups`
     - Folder: `etcd/ops-backoffice`
     - Region: `nyc3`
     - Access key / secret key: DO Spaces credentials

### 2.2 Wait for Cluster Ready

Rancher will provision 3 droplets and install k3s. This takes ~5-10 minutes.

1. Download kubeconfig from Rancher UI: ops-backoffice > Download KubeConfig
2. Save to `k3s/ops-backoffice/.kubeconfig.yaml`

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)

kubectl get nodes    # All 3 should show Ready
```

### 2.3 Apply Traefik HelmChartConfig

Rancher-provisioned clusters get default Traefik (LoadBalancer, random NodePorts). Apply the shared config to set fixed NodePorts (30080/30443) required for the DO Load Balancer.

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)

# Copy shared Traefik config as a HelmChartConfig manifest
# On any control-plane node:
scp ../shared/traefik-config.yaml root@<ops-backoffice-node-1>:/var/lib/rancher/k3s/server/manifests/traefik-config.yaml

# Verify Traefik restarts with new config
kubectl rollout status daemonset/traefik -n kube-system --timeout=120s
kubectl get svc traefik -n kube-system
# Should show NodePort with 30080 and 30443
```

### 2.4 Install Gateway API CRDs

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

### 2.5 Install Longhorn via Rancher

1. Rancher UI > ops-backoffice > Apps > Charts
2. Search "Longhorn", install with defaults
3. Set replicas to 2 (see `k3s/ops-backoffice/cluster/longhorn/README.md`)

```bash
kubectl get storageclass longhorn    # Verify StorageClass exists
```

### 2.6 Install Tailscale Operator

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)

helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update

helm install tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale --create-namespace \
  -f cluster/tailscale/operator-values.yaml \
  --set oauth.clientId=<YOUR_TS_CLIENT_ID> \
  --set oauth.clientSecret=<YOUR_TS_CLIENT_SECRET>

# Apply ProxyClass (MTU 1200 fix)
kubectl apply -f cluster/tailscale/proxyclass.yaml

# Apply Connector (advertise 10.42.0.0/16 + 10.43.0.0/16 to tailnet)
kubectl apply -f cluster/tailscale/connector.yaml
```

Verify:

```bash
kubectl get pods -n tailscale
# Check tailnet admin for ops-k3s-backoffice-subnet device
```

### 2.7 Deploy Appsmith

Appsmith v1.95 with Kustomize-managed secrets.

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)

# Copy secrets from existing cluster
cp ../ops-backoffice-tools/apps/appsmith/manifests/base/secrets/.secrets.env \
   apps/appsmith/manifests/base/secrets/.secrets.env
cp ../ops-backoffice-tools/apps/appsmith/manifests/base/secrets/tls.crt \
   apps/appsmith/manifests/base/secrets/tls.crt
cp ../ops-backoffice-tools/apps/appsmith/manifests/base/secrets/tls.key \
   apps/appsmith/manifests/base/secrets/tls.key
```

Required secrets (see `apps/appsmith/manifests/base/secrets/.secrets.env.sample`):

- `APPSMITH_ENCRYPTION_PASSWORD` -- generate with `openssl rand -hex 32`
- `APPSMITH_ENCRYPTION_SALT` -- generate with `openssl rand -hex 32`
- `APPSMITH_SUPERVISOR_PASSWORD`
- `APPSMITH_DB_URL` -- MongoDB Atlas connection string

Decrypt secrets (if using SOPS-encrypted secrets):

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s
just decrypt ops-backoffice/apps/appsmith
```

Deploy:

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)
kubectl apply -k apps/appsmith/manifests/base/
```

### 2.8 Verify Appsmith

```bash
# Wait for pod ready (may take ~2 minutes, liveness probe starts at 120s)
kubectl get pods -n appsmith
kubectl wait --for=condition=Ready pod -l app=appsmith -n appsmith --timeout=300s

# Check service
kubectl get svc -n appsmith
kubectl get gateway -n appsmith

# Port-forward to test locally
kubectl port-forward -n appsmith svc/appsmith 8080:80
# Open http://localhost:8080 -- verify Appsmith loads
```

Gateway is configured for `appsmith.freecodecamp.net` on ports 8443 (HTTPS, TLS terminated) and 8000 (HTTP).

### 2.9 Create DO Load Balancer

Create a DigitalOcean Load Balancer targeting ops-backoffice nodes.

1. Create LB via DO console or API:
   - **Region**: nyc3
   - **VPC**: same as ops-backoffice nodes
   - **Forwarding rules**:
     - HTTP: 80 -> 30080 (HTTP)
     - HTTPS: 443 -> 30443 (TCP passthrough)
   - **Health check**: TCP on port 30080
   - **Target droplets**: all 3 ops-backoffice nodes
2. Note the LB's external IP address.

```bash
# Verify LB is healthy
curl -sI http://<LB_EXTERNAL_IP>
```

### 2.10 Update Cloudflare DNS

Update the DNS record for `appsmith.freecodecamp.net` to point to the new LB.

1. **Record the current DNS value for rollback**:
   ```bash
   dig appsmith.freecodecamp.net +short
   # Save this IP/hostname -- needed if rollback is required
   ```
2. In Cloudflare dashboard (or via API), update the record for `appsmith.freecodecamp.net`:
   - **Type**: A (if using IP) or CNAME (if using hostname)
   - **Value**: LB external IP or hostname
   - **TTL**: 1 minute (set low during cutover)
   - **Proxy**: as appropriate for your setup

```bash
# Verify DNS propagation
dig appsmith.freecodecamp.net +short
# Should return the new LB IP
```

### 2.11 Verify Live Traffic

```bash
curl -sI https://appsmith.freecodecamp.net
# Should return HTTP 200

# Verify TLS cert is valid
curl -svI https://appsmith.freecodecamp.net 2>&1 | grep 'subject:'
```

Open `https://appsmith.freecodecamp.net` in a browser and confirm Appsmith loads correctly.

### 2.12 Remove Appsmith from Old Cluster

Once live traffic is confirmed on the new cluster, remove Appsmith from the old `ops-backoffice-tools` cluster.

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice-tools && export $(cat .env | xargs)

kubectl delete -k apps/appsmith/manifests/base/
```

> **Note**: `kubectl delete -k` removes deployments, services, and secrets but Longhorn PVCs with `Retain` reclaim policy will survive. Verify with `kubectl get pvc -n appsmith` after deletion. If rollback is needed after this step, `kubectl apply -k` will re-create the deployment and bind to the existing PVC. If PVCs were also deleted, restore from Longhorn backup instead.

Keep the secrets/TLS files in the repo (they are gitignored and serve as backup).

### Phase 2 Checklist

- [ ] 3 nodes show `Ready` in Rancher UI and `kubectl get nodes`
- [ ] Longhorn `StorageClass` available
- [ ] Tailscale Connector `ops-k3s-backoffice-subnet` visible in tailnet admin
- [ ] Appsmith pod `Running` and `Ready` in namespace `appsmith`
- [ ] Appsmith accessible via `kubectl port-forward` at `http://localhost:8080`
- [ ] PVC `appsmith-data` bound to Longhorn volume
- [ ] DO LB created and healthy
- [ ] DNS updated -- `appsmith.freecodecamp.net` resolves to new LB
- [ ] Live traffic verified -- HTTPS 200 from `appsmith.freecodecamp.net`
- [ ] Appsmith removed from old `ops-backoffice-tools` cluster

---

## Phase 3: DR Test

Validates that ops-backoffice continues operating independently when ops-mgmt (Rancher) goes down. Since Appsmith is now serving live traffic, this tests real production resilience.

### 3.1 Pre-DR Baseline

Record the current state from both clusters.

```bash
# ops-mgmt
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-mgmt && export $(cat .env | xargs)
kubectl get nodes
kubectl get pods -n cattle-system

# ops-backoffice
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)
kubectl get nodes
kubectl get pods -n appsmith
kubectl get pvc -n appsmith

# Verify live traffic baseline
curl -sI https://appsmith.freecodecamp.net
```

### 3.2 Simulate ops-mgmt Failure

SSH to the ops-mgmt node and stop k3s:

```bash
ssh root@<ops-mgmt-node-ip>
sudo systemctl stop k3s
```

### 3.3 Verify ops-backoffice Survives

**Important**: Use the ops-backoffice kubeconfig directly from your workstation. Do NOT rely on Rancher proxy.

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice && export $(cat .env | xargs)

kubectl get nodes              # All 3 should show Ready
kubectl get pods -n appsmith   # Should show Running

# Verify live traffic still works (ops-backoffice is independent of ops-mgmt)
curl -sI https://appsmith.freecodecamp.net
# Should return HTTP 200
```

### 3.4 Verify from Different Network

If possible, verify `https://appsmith.freecodecamp.net` is accessible from a different network or device (e.g., mobile data, a colleague's machine) to confirm it is not a cached/local result.

### 3.5 Verify Rancher is Down

```bash
# This should fail/timeout
curl -sk --max-time 10 https://rancher.ops-mgmt.ts.net
# Expected: connection refused or timeout
```

### 3.6 Restore ops-mgmt

```bash
ssh root@<ops-mgmt-node-ip>
sudo systemctl start k3s
```

Wait ~2-3 minutes for Rancher to recover.

### 3.7 Verify Recovery

```bash
# Rancher UI should be accessible again
curl -sk --max-time 10 https://rancher.ops-mgmt.ts.net | head -c 100
# Should return HTML, not an error

# ops-backoffice should re-appear in Rancher UI
# Check Rancher backup ran successfully
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-mgmt && export $(cat .env | xargs)
kubectl get backups.resources.cattle.io -n cattle-resources-system
```

### Phase 3 Checklist

- [ ] ops-backoffice nodes stayed `Ready` during ops-mgmt outage
- [ ] `appsmith.freecodecamp.net` remained accessible during outage (HTTP 200)
- [ ] Verified from a different network/device (if possible)
- [ ] `kubectl` commands against ops-backoffice worked with direct kubeconfig
- [ ] Rancher recovered after `systemctl start k3s`
- [ ] ops-backoffice re-appeared in Rancher UI
- [ ] Actual recovery time: \_\_\_ minutes

---

## Rollback Plan

If Appsmith on the new cluster fails, the old `ops-backoffice-tools` cluster still has all infrastructure in place to re-deploy.

### Step 1: Re-deploy Appsmith on Old Cluster

```bash
cd /Users/mrugesh/DEV/fCC/infra/k3s/ops-backoffice-tools && export $(cat .env | xargs)

kubectl apply -k apps/appsmith/manifests/base/
```

### Step 2: Revert Cloudflare DNS

Update the CNAME/A record for `appsmith.freecodecamp.net` back to the old LB IP/hostname in Cloudflare.

### Step 3: Verify Old Cluster Serves Traffic

```bash
curl -sI https://appsmith.freecodecamp.net
# Should return HTTP 200 served by old cluster
```

### Step 4: Tear Down New Cluster Resources (Optional)

Remove new cluster resources via Rancher UI if rollback is permanent.

**RTO**: ~5 minutes

### Full Teardown (if rollback needed)

```bash
# 1. Delete ops-backoffice cluster via Rancher UI
#    Rancher UI > Cluster Management > ops-backoffice > Delete
#    This automatically destroys the 3 DO droplets

# 2. Delete ops-mgmt droplet
ssh root@<ops-mgmt-node-ip>
sudo systemctl stop k3s

# Then delete the droplet via DO console or API
```

### Cost Estimate

| Resource            | Spec           | Monthly Cost |
| ------------------- | -------------- | ------------ |
| ops-mgmt            | 1x s-4vcpu-8gb | $48          |
| ops-backoffice      | 3x s-4vcpu-8gb | $144         |
| DO Spaces (storage) | ~1 GB          | ~$5          |
| **Total**           |                | **~$197/mo** |

Prorate for actual testing duration. A 1-week spike costs ~$50.

> After Appsmith migration, the old cluster frees ~500m CPU / 2Gi memory. Remaining apps (Outline, Grafana, n8n, Prometheus) continue on the old cluster until migrated incrementally.

---

## Results Template

Fill this in during spike execution.

| #   | Test                                    | Expected                                                      | Actual         | Pass/Fail |
| --- | --------------------------------------- | ------------------------------------------------------------- | -------------- | --------- |
| 1   | ops-mgmt k3s deploys                    | 1 node Ready                                                  |                |           |
| 2   | Rancher UI accessible                   | Via Tailscale at `rancher.ops-mgmt.ts.net`                    |                |           |
| 3   | etcd S3 backup (ops-mgmt)               | Snapshots in `etcd/ops-mgmt/` on DO Spaces                    |                |           |
| 4   | Rancher backup works                    | Backups in `rancher-backup/` on DO Spaces                     |                |           |
| 5   | ops-backoffice provisioned via Rancher  | 3 nodes Ready                                                 |                |           |
| 6   | Longhorn installed                      | `longhorn` StorageClass available                             |                |           |
| 7   | Tailscale Connector (ops-mgmt)          | `ops-k3s-mgmt-subnet` in tailnet                              |                |           |
| 8   | Tailscale Connector (ops-backoffice)    | `ops-k3s-backoffice-subnet` in tailnet                        |                |           |
| 9   | Appsmith deploys on new cluster         | Pod Ready in `appsmith` namespace                             |                |           |
| 10  | Appsmith accessible                     | Via port-forward on `http://localhost:8080`                   |                |           |
| 11  | ops-backoffice survives ops-mgmt outage | Nodes + pods stay Ready, Appsmith serves                      |                |           |
| 12  | Rancher recovers after restart          | UI accessible, cluster visible                                |                |           |
| 13  | Recovery time                           | < 5 minutes                                                   | \_\_\_ minutes |           |
| 14  | DO LB created                           | LB external IP reachable on 443                               |                |           |
| 15  | DNS cutover                             | `appsmith.freecodecamp.net` resolves to new LB                |                |           |
| 16  | Live traffic                            | HTTPS 200 from `appsmith.freecodecamp.net` via new cluster    |                |           |
| 17  | Old cluster cleanup                     | Appsmith pods removed from ops-backoffice-tools               |                |           |
| 18  | DR: live traffic survives               | `appsmith.freecodecamp.net` accessible during ops-mgmt outage |                |           |

---

## File Reference

All spike-related files in this repo:

| File                                                        | Purpose                                              |
| ----------------------------------------------------------- | ---------------------------------------------------- |
| `ansible/play-k3s--ops-mgmt.yml`                            | Ansible playbook for ops-mgmt k3s cluster            |
| `k3s/ops-mgmt/apps/rancher/install.sh`                      | Rancher + cert-manager + backup operator install     |
| `k3s/ops-mgmt/apps/rancher/backup-schedule.yaml`            | Rancher backup CRD (6h schedule, 20 retention)       |
| `k3s/ops-mgmt/cluster/tailscale/operator-values.yaml`       | Tailscale operator Helm values                       |
| `k3s/ops-mgmt/cluster/tailscale/connector.yaml`             | Subnet router: 10.40/10.41                           |
| `k3s/ops-mgmt/cluster/tailscale/proxyclass.yaml`            | MTU 1200 fix                                         |
| `k3s/ops-mgmt/README.md`                                    | ops-mgmt cluster reference                           |
| `k3s/ops-backoffice/apps/appsmith/manifests/base/`          | Appsmith v1.95 Kustomize manifests                   |
| `k3s/ops-backoffice/cluster/tailscale/connector.yaml`       | Subnet router: 10.42/10.43                           |
| `k3s/ops-backoffice/cluster/tailscale/operator-values.yaml` | Tailscale operator Helm values                       |
| `k3s/ops-backoffice/cluster/tailscale/proxyclass.yaml`      | MTU 1200 fix                                         |
| `k3s/ops-backoffice/cluster/longhorn/README.md`             | Longhorn install notes                               |
| `ansible/vars/vault-k3s.yml`                                | Ansible Vault: DO Spaces, Tailscale, Rancher secrets |
| `.sops.yaml`                                                | SOPS encryption config                               |
| `k3s/justfile`                                              | Just commands (decrypt, etc.)                        |
