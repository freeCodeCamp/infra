# ops-backoffice-tools K3s Cluster

Internal tools cluster running on K3s with Longhorn storage.

## Prerequisites

- kubectl configured with cluster access
- Helm 3.x
- Access to Tailscale admin console

## Cluster Access

```bash
cd k3s/ops-backoffice-tools
export KUBECONFIG=$(pwd)/.kubeconfig.yaml
kubectl get nodes
```

## Components

### Storage: Longhorn

Distributed block storage with automatic backups to DO Spaces.

- **Replicas:** 2 (survives 1 node failure)
- **Backup:** Daily at 2 AM UTC, 7 day retention
- **Target:** `s3://net.freecodecamp.ops-k3s-backups@nyc3/`

### Applications

| App | Namespace | URL | Description |
|-----|-----------|-----|-------------|
| Appsmith | appsmith | https://appsmith.freecodecamp.net | Low-code app builder |
| Outline | outline | https://outline.freecodecamp.net | Knowledge base wiki |
| Grafana | grafana | https://grafana.freecodecamp.net | Log analytics dashboard |
| n8n | n8n | https://n8n.freecodecamp.net | Workflow automation platform |
| Prometheus | prometheus | (internal + Tailscale) | Metrics collection and alerting |

---

## Tailscale Operator Setup

Required for Grafana to access ClickHouse on the ops-logs-clickhouse cluster.

### 1. Create OAuth Client

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Create new OAuth client:
   - **Description:** `ops-backoffice-tools k8s operator`
   - **Tags:** `tag:k8s`
   - **Scopes:** `devices:write`
3. Save the Client ID and Client Secret

### 2. Install Tailscale Operator

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update

helm install tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --create-namespace \
  --set oauth.clientId=<CLIENT_ID> \
  --set oauth.clientSecret=<CLIENT_SECRET>
```

### 3. Verify Installation

```bash
kubectl get pods -n tailscale
# Should show operator pod running
```

---

## Grafana Deployment

Log analytics dashboard connected to ClickHouse via Tailscale FQDN.

### 1. Create Secrets

```bash
cd apps/grafana/manifests/base/secrets

# Copy sample and fill in values
cp .secrets.env.sample .secrets.env

# Edit .secrets.env:
# - GRAFANA_ADMIN_USER: admin username
# - GRAFANA_ADMIN_PASSWORD: generate secure password
# - GRAFANA_GOOGLE_CLIENT_ID: Google OAuth client ID
# - GRAFANA_GOOGLE_CLIENT_SECRET: Google OAuth client secret
# - GRAFANA_GOOGLE_ALLOWED_DOMAIN: freecodecamp.org
# - CLICKHOUSE_GRAFANA_PASSWORD: from ClickHouse setup
```

### 2. Add TLS Certificate

Obtain Cloudflare origin certificate for `grafana.freecodecamp.net`:

```bash
# Save certificate and key
# secrets/tls.crt - Certificate
# secrets/tls.key - Private key
```

### 3. Deploy Grafana

```bash
# Apply Kustomize base (namespace, secrets, gateway, httproutes)
kubectl apply -k apps/grafana/manifests/base/

# Install Grafana via Helm
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana -n grafana -f apps/grafana/charts/grafana/values.yaml
```

### 4. Configure DNS

Add A record in Cloudflare:
- **Name:** `grafana`
- **Content:** Load balancer IP (run `kubectl get nodes -o wide` for node IPs)
- **Proxy:** Orange cloud (proxied)

### 5. Verify Deployment

```bash
# Check pods
kubectl get pods -n grafana

# Check ClickHouse connection (via Tailscale FQDN)
curl -s http://ops-k3s-clickhouse-logs.batfish-ray.ts.net:8123/ping
```

### 6. Access Grafana

1. Navigate to https://grafana.freecodecamp.net
2. Login with admin credentials from `.secrets.env`
3. Verify ClickHouse datasource in Configuration > Data Sources

---

## n8n Deployment

Workflow automation platform with queue mode for ops automation, team tooling, and data pipelines.

### 1. Prerequisites

**Tailscale Operator** (for ClickHouse access) - see Tailscale Operator Setup section above.

**DNS Records (Cloudflare):**
- `n8n.freecodecamp.net` -> tools LB IP (proxied)
- `n8n-wh.freecodecamp.net` -> tools LB IP (proxied)

### 2. Create Secrets

```bash
cd apps/n8n/manifests/base/secrets

# Copy sample and fill in values
cp .secrets.env.sample .secrets.env

# Generate secrets
openssl rand -hex 32  # for N8N_ENCRYPTION_KEY
openssl rand -hex 32  # for JWT_SECRET
openssl rand -base64 24  # for POSTGRES_PASSWORD

# Edit .secrets.env with generated values
# SMTP can be configured later in n8n UI (Settings > Email)
```

### 3. Add TLS Certificate

Obtain Cloudflare origin certificate covering both domains:

```bash
# Certificate for n8n.freecodecamp.net and n8n-wh.freecodecamp.net
# Save as: secrets/tls.crt and secrets/tls.key
```

### 4. Deploy n8n

```bash
kubectl apply -k apps/n8n/manifests/base/
```

### 5. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n n8n

# Check PVCs are bound
kubectl get pvc -n n8n

# Check gateways and routes
kubectl get gateway,httproute -n n8n

# View logs
kubectl logs -n n8n deploy/n8n-main
kubectl logs -n n8n deploy/n8n-worker
```

### 6. Initial Setup

1. Navigate to https://n8n.freecodecamp.net
2. Create first user (becomes instance owner) - use @freecodecamp.org email
3. Configure credentials for integrations

### n8n Architecture

- **n8n-main**: UI, API, webhook receiver (1 replica)
- **n8n-worker**: Workflow execution (2 replicas, scalable)
- **n8n-postgres**: Database (20Gi)
- **n8n-redis**: Queue backend

### Scaling Workers

```bash
# Edit worker deployment
kubectl edit deploy/n8n-worker -n n8n
# Change replicas: 2 to desired count
```

### TBD: System SMTP Configuration

System emails (user invites, password resets) require SMTP environment variables.

Add to `apps/n8n/manifests/base/secrets/.secrets.env`:

```bash
N8N_EMAIL_MODE=smtp
N8N_SMTP_HOST=email-smtp.us-east-1.amazonaws.com
N8N_SMTP_PORT=587
N8N_SMTP_USER=<ses-smtp-user>
N8N_SMTP_PASS=<ses-smtp-password>
N8N_SMTP_SENDER=n8n@freecodecamp.org
N8N_SMTP_SSL=false
```

Then redeploy:

```bash
kubectl apply -k apps/n8n/manifests/base/
kubectl rollout restart deployment/n8n-main -n n8n
```

**Note:** Workflow emails use Send Email node credentials configured in n8n UI.

---

## Prometheus Deployment

Metrics collection and alerting for k3s workloads.

### 1. Deploy Prometheus

```bash
# Apply Kustomize manifests (namespace + tailscale ingress)
kubectl apply -k apps/prometheus/manifests/base/

# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n prometheus \
  -f apps/prometheus/charts/kube-prometheus-stack/values.yaml
```

### 2. Verify

```bash
kubectl get pods -n prometheus
```

### Upgrading

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n prometheus \
  -f apps/prometheus/charts/kube-prometheus-stack/values.yaml
```

### Architecture

- **Prometheus**: Metrics storage (50GB Longhorn, 7-day retention)
- **Alertmanager**: Routes alerts to n8n webhooks
- **Node Exporter**: k3s host metrics
- **Kube State Metrics**: k3s workload metrics

### Access

| Method | URL |
|--------|-----|
| Grafana | Internal datasource (no direct access needed) |
| Tailscale | `ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090` |

### Adding External Targets

Edit `apps/prometheus/charts/kube-prometheus-stack/values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'external-node'
        static_configs:
          - targets: ['10.0.0.1:9100']
            labels:
              cluster: my-cluster
```

Then upgrade helm release.

### Remote Write (for external agents)

External Prometheus agents can push metrics:

```yaml
remote_write:
  - url: http://ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090/api/v1/write
```

Requires Tailscale connectivity.

---

## Application Deployment Pattern

All apps follow Kustomize pattern:

```bash
# Deploy
kubectl apply -k apps/<app-name>/manifests/base/

# Check status
kubectl get all -n <app-name>

# View logs
kubectl logs -n <app-name> deploy/<app-name>
```

### Secrets Management

- Secrets stored in `apps/<app>/manifests/base/secrets/`
- `.secrets.env` - Environment variables (gitignored)
- `.secrets.env.sample` - Template (committed)
- `tls.crt`, `tls.key` - TLS certificates (gitignored)

---

## Longhorn Backup Configuration

### Manual Backup

```bash
kubectl apply -f cluster/longhorn/recurring-backup.yaml
```

### Restore from Backup

1. Access Longhorn UI: `kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80`
2. Navigate to Backup > Select backup > Restore
3. Create PVC from restored volume

---

## Troubleshooting

### Tailscale Connectivity Issues

```bash
# Check operator logs
kubectl logs -n tailscale deploy/operator

# Test ClickHouse FQDN (from any Tailscale node)
curl -s http://ops-k3s-clickhouse-logs.batfish-ray.ts.net:8123/ping

# Test Prometheus FQDN
curl -s http://ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090/-/healthy
```

### Grafana ClickHouse Connection Failed

```bash
# Check Grafana logs
kubectl logs -n grafana deploy/grafana | grep -i clickhouse

# Test ClickHouse connectivity (from Tailscale network)
curl -u grafana:PASSWORD \
  'http://ops-k3s-clickhouse-logs.batfish-ray.ts.net:8123/?query=SELECT%201'
```

### PVC Stuck in Pending

```bash
# Check Longhorn status
kubectl get volumes.longhorn.io -n longhorn-system

# Check storage class
kubectl get sc longhorn -o yaml
```
