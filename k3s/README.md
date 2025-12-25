# k3s Stack (Self-hosted)

Self-hosted k3s clusters on DigitalOcean for internal tools and logging.

## Clusters

| Cluster              | Purpose             | Apps                       |
| -------------------- | ------------------- | -------------------------- |
| ops-backoffice-tools | Internal tools      | Appsmith, Outline, Grafana |
| ops-logs-clickhouse  | Centralized logging | ClickHouse                 |

## Structure

```
k3s/
├── README.md
├── nginx-logs-schema.md
├── grafana-nginx-dashboard.md
├── shared/
│   └── traefik-config.yaml
├── ops-backoffice-tools/
│   ├── README.md
│   ├── cluster/longhorn/
│   ├── cluster/tailscale/
│   ├── apps/appsmith/manifests/base/
│   ├── apps/outline/manifests/base/
│   ├── apps/grafana/manifests/base/
│   ├── .kubeconfig.yaml
│   └── .env
└── ops-logs-clickhouse/
    ├── cluster/charts/tailscale-operator/
    ├── apps/clickhouse/
    │   ├── manifests/base/
    │   │   ├── secrets/users-secret.yaml.sample
    │   │   └── *.yaml
    │   └── schemas/*.sql
    ├── .kubeconfig.yaml
    └── .env
```

---

## Phase 1: DigitalOcean Resources

Create all resources in DO console before running Ansible.

### VPC

| Property | Value              |
| -------- | ------------------ |
| Name     | ops-vpc-k3s-nyc3   |
| Region   | nyc3               |
| IP Range | 10.108.0.0/20      |

### Droplets

| Cluster | Name Pattern              | Count | Specs                | Tags                   |
| ------- | ------------------------- | ----- | -------------------- | ---------------------- |
| tools   | ops-vm-tools-k3s-nyc3-0X  | 3     | 4 vCPU, 8GB, 160GB   | k3s, tools_k3s         |
| logs    | ops-vm-logs-k3s-nyc3-0X   | 3     | 4 vCPU, 8GB, 160GB   | k3s, logs_k3s          |

All droplets attach to VPC (eth1 gets 10.108.0.x IP).

### Volumes (logs cluster only)

| Name Pattern                    | Size  | Attached To               |
| ------------------------------- | ----- | ------------------------- |
| ops-vol-logs-k3s-nyc3-0X        | 100GB | ops-vm-logs-k3s-nyc3-0X   |

Mount to `/mnt/ops-vol-logs-k3s-nyc3-0X` on each node.

### Load Balancers

| Name                  | Cluster | Target Tag | VPC              |
| --------------------- | ------- | ---------- | ---------------- |
| ops-lb-tools-k3s-nyc3 | tools   | tools_k3s  | ops-vpc-k3s-nyc3 |

Logs cluster uses Tailscale for private access (no public LB).

**Forwarding Rules:**

| Entry      | Entry Port | Target     | Target Port | TLS         |
| ---------- | ---------- | ---------- | ----------- | ----------- |
| HTTP       | 80         | HTTP       | 30080       | -           |
| HTTPS      | 443        | HTTPS      | 30443       | Passthrough |

**Health Check:** TCP on port 30443

### Firewalls

| Name              | Applied To |
| ----------------- | ---------- |
| ops-fw-k3s-nyc3   | tag: k3s   |

**Inbound Rules:**

| Protocol | Ports      | Source                |
| -------- | ---------- | --------------------- |
| TCP/UDP  | All        | VPC (10.108.0.0/20)   |
| ICMP     | -          | VPC (10.108.0.0/20)   |
| TCP      | 22         | Restricted IPs        |
| TCP      | 30080,30443| Load Balancer         |

**Outbound:** All traffic allowed

---

## Phase 2: Ansible Setup

Prerequisites: Droplets hardened and Tailscale installed.

### Deploy Clusters

```bash
cd ansible

# Tools cluster
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--cluster.yml -e variable_host=tools_k3s

# Logs cluster
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--cluster.yml -e variable_host=logs_k3s
```

### Install Longhorn (tools cluster)

```bash
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml -e variable_host=tools_k3s
```

### ClickHouse Tuning (logs cluster)

Requires volumes attached and mounted.

```bash
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--clickhouse.yml -e variable_host=logs_k3s
```

Applies: sysctl tuning, THP disable, I/O scheduler, `/data/clickhouse` symlink, local-path provisioner patch.

### Fetch Kubeconfig

```bash
# Tools cluster
uv run ansible -i inventory/digitalocean.yml tools_k3s -m fetch -a "src=/etc/rancher/k3s/k3s.yaml dest=/tmp/k3s-tools-{{ inventory_hostname }}.yaml flat=yes" -b

# Update server URLs to Tailscale IPs
for f in /tmp/k3s-tools-*.yaml; do
  HOST=$(basename "$f" .yaml | sed 's/k3s-tools-//')
  TS_IP=$(tailscale status | grep "$HOST" | awk '{print $1}')
  sed -i '' "s|127.0.0.1|$TS_IP|g; s|default|$HOST|g" "$f"
done

# Merge
kubectl konfig merge /tmp/k3s-tools-*.yaml > ../k3s/ops-backoffice-tools/.kubeconfig.yaml
```

Repeat for logs cluster with `logs_k3s` and appropriate paths.

---

## Phase 3: Backup Configuration

Backups to DO Spaces: `net.freecodecamp.ops-k3s-backups`

### Longhorn Backup Setup

```bash
cd ../k3s/ops-backoffice-tools

# Create credentials secret
kubectl -n longhorn-system create secret generic do-spaces-backup --from-literal=AWS_ACCESS_KEY_ID=<key> --from-literal=AWS_SECRET_ACCESS_KEY=<secret> --from-literal=AWS_ENDPOINTS=nyc3.digitaloceanspaces.com

# Apply backup target and recurring job
kubectl apply -k cluster/longhorn/
```

**Manifests applied:**
- `cluster/longhorn/backup-target.yaml` - Configures `default` BackupTarget with S3 URL
- `cluster/longhorn/recurring-backup.yaml` - Daily backup at 2 AM UTC, retain 7

### Manual Backup Test

```bash
# Trigger backup for a volume
kubectl -n longhorn-system create -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  generateName: manual-test-
  labels:
    longhornvolume: <volume-name>
spec:
  snapshotName: ""
EOF

# Check backup status
kubectl get backups.longhorn.io -n longhorn-system
```

---

## Phase 4: App Deployment

### Tools Cluster

```bash
cd ../k3s/ops-backoffice-tools

kubectl apply -k apps/appsmith/manifests/base/
kubectl apply -k apps/outline/manifests/base/

# Grafana (requires Tailscale operator first - see ops-backoffice-tools/README.md)
kubectl apply -k apps/grafana/manifests/base/
helm install grafana grafana/grafana -n grafana -f apps/grafana/charts/grafana/values.yaml
```

### Logs Cluster

**Tailscale OAuth Prerequisites:**
1. Create OAuth client at https://login.tailscale.com/admin/settings/oauth
   - Scopes: `Devices Core` (write), `Auth Keys` (write), `Services` (write)
   - Tag: `tag:k8s-operator`
2. Add tags in ACL policy: `tag:k8s-operator` (owner of `tag:k8s`), `tag:k8s`

**Create User Secret:**
```bash
cd ../k3s/ops-logs-clickhouse

# Generate passwords and hashes
openssl rand -base64 32                              # Generate password
echo -n "your_password" | sha256sum | cut -d' ' -f1  # Generate hash

# Create secret from template (3 users: admin, vector, grafana)
cp apps/clickhouse/manifests/base/secrets/users-secret.yaml.sample \
   apps/clickhouse/manifests/base/secrets/users-secret.yaml
# Edit with your hashes, then apply
kubectl apply -f apps/clickhouse/manifests/base/secrets/users-secret.yaml
```

**Deploy:**
```bash
# Install ClickHouse operator
helm repo add altinity https://docs.altinity.com/clickhouse-operator-helm
helm repo update
helm upgrade clickhouse-operator altinity/altinity-clickhouse-operator --namespace clickhouse --create-namespace --install

# Deploy Tailscale operator
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm upgrade tailscale-operator tailscale/tailscale-operator --namespace tailscale --create-namespace --install -f cluster/charts/tailscale-operator/values.yaml --set oauth.clientId=<id> --set oauth.clientSecret=<secret>

# Deploy ClickHouse
kubectl apply -k apps/clickhouse/manifests/base/

# Create schemas (staging and production databases)
kubectl exec -i -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client < apps/clickhouse/schemas/002-logs-nginx-stg.sql
kubectl exec -i -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client < apps/clickhouse/schemas/003-logs-nginx-prd.sql
```

**ClickHouse Users:**

| User | Access | Use Case |
|------|--------|----------|
| `admin` | Full | Administration |
| `vector` | Write `logs_*` | Log ingestion |
| `grafana` | Read-only | Dashboards |

**ClickHouse Access (Tailscale only):**
- Hostname: `clickhouse-logs.<tailnet>.ts.net`
- Port 8123: HTTP interface (queries, Play UI)
- Port 9000: Native TCP (clickhouse-client)

See [nginx-logs-schema.md](nginx-logs-schema.md) for log format mapping and sample queries.

### DNS (Cloudflare)

| Record                      | Type | Value     |
| --------------------------- | ---- | --------- |
| appsmith.freecodecamp.net   | A    | tools LB  |
| outline.freecodecamp.net    | A    | tools LB  |
| grafana.freecodecamp.net    | A    | tools LB  |

ClickHouse uses Tailscale for private access (no public DNS).

### Verify

```bash
kubectl get pods -A
kubectl get pvc -A
kubectl get gateway,httproute -A
kubectl -n longhorn-system get backuptargets
kubectl -n longhorn-system get recurringjobs

curl -I https://appsmith.freecodecamp.net
curl -I https://outline.freecodecamp.net
```

---

## Architecture

### Traffic Flow

```
Internet → Cloudflare → DO Load Balancer → Firewall → Traefik (NodePort 30443) → Gateway API → App Service
```

### Networking

| Component      | Value                    |
| -------------- | ------------------------ |
| VPC CIDR       | 10.108.0.0/20            |
| Pod CIDR       | 10.42.0.0/16             |
| Service CIDR   | 10.43.0.0/16             |
| CoreDNS        | 10.43.0.10               |
| Flannel iface  | eth1 (VPC)               |

### Cluster Components

| Component       | Version      |
| --------------- | ------------ |
| K3s             | v1.32.11+k3s1|
| OS              | Ubuntu 24.04 |
| Traefik         | 3.5.x        |
| Longhorn        | 1.10.1       |
| Gateway API     | v1.4.0       |

### Storage

| Class        | Provisioner            | Replicas | Use For                    |
| ------------ | ---------------------- | -------- | -------------------------- |
| longhorn     | driver.longhorn.io     | 2        | Databases, stateful apps   |
| local-path   | rancher.io/local-path  | 1        | Ephemeral, non-critical    |

---

## Maintenance

### Update Apps

```bash
# Edit deployment.yaml with new image version
kubectl apply -k apps/<app>/manifests/base/
```

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### ClickHouse Access

**Via Tailscale (preferred):**
```bash
# Web UI
open http://clickhouse-logs.<tailnet>.ts.net:8123/play

# CLI (requires clickhouse-client installed)
clickhouse-client --host clickhouse-logs.<tailnet>.ts.net --user admin --password
```

**Via kubectl:**
```bash
cd k3s/ops-logs-clickhouse

# Interactive shell
KUBECONFIG=.kubeconfig.yaml kubectl exec -it -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client

# Run query
KUBECONFIG=.kubeconfig.yaml kubectl exec -it -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client -q "SHOW DATABASES"

# Run SQL file (example: staging schema)
KUBECONFIG=.kubeconfig.yaml kubectl exec -i -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client < apps/clickhouse/schemas/002-logs-nginx-stg.sql
```

### Useful Commands

```bash
# Cluster health
kubectl get nodes -o wide
kubectl top nodes

# Storage
kubectl get pv,pvc -A
kubectl get volumes.longhorn.io -n longhorn-system

# DO resources
doctl compute droplet list | grep k3s
doctl compute load-balancer list | grep k3s
```

### Expand Block Storage (logs cluster)

1. Resize volume in DO dashboard
2. SSH to node: `sudo resize2fs /dev/disk/by-id/scsi-0DO_Volume_<name>`

---

## Disaster Recovery (tools cluster)

### Failure Scenarios

| Scenario              | Recovery                                 |
| --------------------- | ---------------------------------------- |
| Single node failure   | Automatic - k3s HA (3 nodes)             |
| Single volume failure | Automatic - Longhorn replicas (2 copies) |
| Complete cluster loss | Manual restore (see below)               |

### Complete Cluster Restore

**Prerequisites:** New droplets tagged `k3s` + `tools_k3s`, VPC/LB/FW configured, Tailscale installed.

```bash
cd ansible

# Deploy cluster
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--cluster.yml -e variable_host=tools_k3s
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml -e variable_host=tools_k3s

# Fetch kubeconfig (see Phase 2)
```

```bash
cd ../k3s/ops-backoffice-tools

# Configure backup target
kubectl -n longhorn-system create secret generic do-spaces-backup --from-literal=AWS_ACCESS_KEY_ID=<key> --from-literal=AWS_SECRET_ACCESS_KEY=<secret> --from-literal=AWS_ENDPOINTS=nyc3.digitaloceanspaces.com
kubectl apply -f cluster/longhorn/recurring-backup.yaml
```

Restore via Longhorn UI: **Backup** > select backup > **Restore** (use same volume names).

```bash
kubectl apply -k apps/appsmith/manifests/base/
kubectl apply -k apps/outline/manifests/base/
```

---

## Ansible Playbooks

| Playbook                   | Purpose                                          |
| -------------------------- | ------------------------------------------------ |
| play-k3s--cluster.yml      | Deploy k3s HA cluster with Traefik + Gateway API |
| play-k3s--longhorn.yml     | Install Longhorn distributed storage             |
| play-k3s--clickhouse.yml   | ClickHouse node tuning + storage setup           |
| play-o11y--vector.yml      | Deploy Vector log shipper to NGINX nodes         |

All playbooks use `-e variable_host=<group>` to target inventory groups.
