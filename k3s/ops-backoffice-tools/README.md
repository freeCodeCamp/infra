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

### 4. Apply ClickHouse Egress Proxy

```bash
kubectl apply -f cluster/tailscale/clickhouse-egress.yaml
```

This creates a service that allows pods to reach ClickHouse via:
- `http://clickhouse-egress.tailscale.svc.cluster.local:8123`

---

## Grafana Deployment

Log analytics dashboard connected to ClickHouse via Tailscale egress.

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

# Check ClickHouse connection
kubectl exec -n grafana deploy/grafana -- \
  curl -s http://clickhouse-egress.tailscale.svc.cluster.local:8123/ping
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

### Tailscale Egress Not Working

```bash
# Check operator logs
kubectl logs -n tailscale deploy/operator

# Verify egress service
kubectl get svc -n tailscale clickhouse-egress -o yaml

# Test connectivity from a pod
kubectl run test --rm -it --image=busybox -- \
  wget -qO- http://clickhouse-egress.tailscale.svc.cluster.local:8123/ping
```

### Grafana ClickHouse Connection Failed

```bash
# Verify Tailscale egress is working
kubectl exec -n grafana deploy/grafana -- \
  curl -v http://clickhouse-egress.tailscale.svc.cluster.local:8123/

# Check Grafana logs
kubectl logs -n grafana deploy/grafana | grep -i clickhouse

# Test with credentials
kubectl exec -n grafana deploy/grafana -- \
  curl -u grafana:PASSWORD \
  'http://clickhouse-egress.tailscale.svc.cluster.local:8123/?query=SELECT%201'
```

### PVC Stuck in Pending

```bash
# Check Longhorn status
kubectl get volumes.longhorn.io -n longhorn-system

# Check storage class
kubectl get sc longhorn -o yaml
```
