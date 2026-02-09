# ops-backoffice-tools

Internal tools cluster on k3s with Longhorn storage.

## Access

```bash
cd k3s/ops-backoffice-tools
export KUBECONFIG=$(pwd)/.kubeconfig.yaml
kubectl get nodes
```

## Applications

| App      | Namespace | URL                               |
| -------- | --------- | --------------------------------- |
| Appsmith | appsmith  | https://appsmith.freecodecamp.net |
| Outline  | outline   | https://outline.freecodecamp.net  |
| Grafana  | grafana   | https://grafana.freecodecamp.net  |

## Storage

- **Longhorn**: Replicas=2, daily backups to DO Spaces
- **Backup Target**: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`

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

| Variable                      | Description                |
| ----------------------------- | -------------------------- |
| GRAFANA_ADMIN_USER            | Admin username             |
| GRAFANA_ADMIN_PASSWORD        | Admin password             |
| GRAFANA_GOOGLE_CLIENT_ID      | Google OAuth client ID     |
| GRAFANA_GOOGLE_CLIENT_SECRET  | Google OAuth client secret |
| GRAFANA_GOOGLE_ALLOWED_DOMAIN | freecodecamp.org           |

### Datasources

| Datasource | Configuration                              |
| ---------- | ------------------------------------------ |
| Prometheus | Provisioned via Helm values                |
| ClickHouse | UI-configured (Connections > Data sources) |

#### ClickHouse Datasource Setup (Grafana UI)

| Field            | Value                                      |
| ---------------- | ------------------------------------------ |
| Host             | ops-k3s-clickhouse-logs.batfish-ray.ts.net |
| Port             | 9000                                       |
| Protocol         | Native                                     |
| Username         | grafana                                    |
| Password         | (from ClickHouse cluster)                  |
| Default Database | (leave empty)                              |

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
