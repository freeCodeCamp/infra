# ops-backoffice-tools

Internal tools cluster on k3s with Longhorn storage.

## Access

```bash
cd k3s/ops-backoffice-tools
export KUBECONFIG=$(pwd)/.kubeconfig.yaml
kubectl get nodes
```

## Applications

| App | Namespace | URL |
|-----|-----------|-----|
| Appsmith | appsmith | https://appsmith.freecodecamp.net |
| Outline | outline | https://outline.freecodecamp.net |
| Grafana | grafana | https://grafana.freecodecamp.net |
| n8n | n8n | https://n8n.freecodecamp.net |
| Prometheus | prometheus | Tailscale: `ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090` |

## Storage

- **Longhorn**: Replicas=2, daily backups to DO Spaces
- **Backup Target**: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`

---

## Tailscale Operator

Required for cross-cluster communication.

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
helm upgrade tailscale-operator tailscale/tailscale-operator \
  -n tailscale --create-namespace --install \
  -f cluster/tailscale/operator-values.yaml \
  --set oauth.clientId=<CLIENT_ID> \
  --set oauth.clientSecret=<CLIENT_SECRET>
```

---

## Grafana

### Deploy

```bash
# Namespace, gateway, secrets
kubectl apply -k apps/grafana/manifests/base/

# Helm chart
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana -n grafana \
  -f apps/grafana/charts/grafana/values.yaml
```

### Upgrade

```bash
helm upgrade grafana grafana/grafana -n grafana \
  -f apps/grafana/charts/grafana/values.yaml
```

### Secrets

File: `apps/grafana/manifests/base/secrets/.secrets.env`

| Variable | Description |
|----------|-------------|
| GRAFANA_ADMIN_USER | Admin username |
| GRAFANA_ADMIN_PASSWORD | Admin password |
| GRAFANA_GOOGLE_CLIENT_ID | Google OAuth client ID |
| GRAFANA_GOOGLE_CLIENT_SECRET | Google OAuth client secret |
| GRAFANA_GOOGLE_ALLOWED_DOMAIN | freecodecamp.org |

### Datasources

| Datasource | Configuration |
|------------|---------------|
| Prometheus | Provisioned via Helm values |
| ClickHouse | UI-configured (Connections > Data sources) |

#### ClickHouse Datasource Setup (Grafana UI)

| Field | Value |
|-------|-------|
| Host | ops-k3s-clickhouse-logs.batfish-ray.ts.net |
| Port | 9000 |
| Protocol | Native |
| Username | grafana |
| Password | (from ClickHouse cluster) |
| Default Database | (leave empty) |

---

## n8n

### Deploy

```bash
kubectl apply -k apps/n8n/manifests/base/
```

### Secrets

File: `apps/n8n/manifests/base/secrets/.secrets.env`

| Variable | Description |
|----------|-------------|
| N8N_ENCRYPTION_KEY | `openssl rand -hex 32` |
| JWT_SECRET | `openssl rand -hex 32` |
| POSTGRES_PASSWORD | `openssl rand -base64 24` |

### Architecture

- **n8n-main**: UI, API, webhooks (1 replica)
- **n8n-worker**: Execution (2 replicas)
- **n8n-postgres**: Database (20Gi)
- **n8n-redis**: Queue

### Scale Workers

```bash
kubectl scale deploy/n8n-worker -n n8n --replicas=3
```

---

## Prometheus

### Deploy

```bash
# Namespace + Tailscale ingress
kubectl apply -k apps/prometheus/manifests/base/

# Helm chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n prometheus \
  -f apps/prometheus/charts/kube-prometheus-stack/values.yaml
```

### Upgrade

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n prometheus \
  -f apps/prometheus/charts/kube-prometheus-stack/values.yaml
```

### Components

| Component | Storage | Retention |
|-----------|---------|-----------|
| Prometheus | 50Gi Longhorn | 7 days |
| Alertmanager | 10Gi Longhorn | - |

### Alertmanager Webhooks

Alerts route to n8n:
- Default: `https://n8n-wh.freecodecamp.net/webhook/alerts/default`
- Critical: `https://n8n-wh.freecodecamp.net/webhook/alerts/critical`
- Custom: `https://n8n-wh.freecodecamp.net/webhook/alerts/custom`

### Access

| Method | URL |
|--------|-----|
| Grafana | Datasource configured internally |
| Tailscale | `ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090` |

---

## Deployment Pattern

All apps use Kustomize:

```bash
# Deploy
kubectl apply -k apps/<app>/manifests/base/

# Check
kubectl get all -n <app>

# Logs
kubectl logs -n <app> deploy/<app>
```

### Secrets Structure

```
apps/<app>/manifests/base/secrets/
├── .secrets.env         # Variables (gitignored)
├── .secrets.env.sample  # Template (committed)
├── tls.crt              # Certificate (gitignored)
└── tls.key              # Private key (gitignored)
```

---

## Troubleshooting

### Tailscale Connectivity

```bash
kubectl logs -n tailscale deploy/operator

# Test ClickHouse
curl -s http://ops-k3s-clickhouse-logs.batfish-ray.ts.net:8123/ping

# Test Prometheus
curl -s http://ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090/-/healthy
```

### Grafana ClickHouse Errors

```bash
kubectl logs -n grafana deploy/grafana | grep -i clickhouse
```

Common issues:
- `readonly mode`: ClickHouse user profile needs `readonly=2`
- `Database X does not exist`: Leave default database empty in datasource config

### PVC Stuck Pending

```bash
kubectl get volumes.longhorn.io -n longhorn-system
kubectl describe pvc -n <namespace> <pvc-name>
```

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```
