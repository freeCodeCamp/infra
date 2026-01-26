# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster | Purpose | Apps |
|---------|---------|------|
| ops-backoffice-tools | Internal tools | Appsmith, Outline, Grafana, n8n, Prometheus |
| ops-logs-clickhouse | Centralized logging | ClickHouse |

## Quick Access

```bash
# Tools cluster
cd k3s/ops-backoffice-tools && export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Logs cluster
cd k3s/ops-logs-clickhouse && export KUBECONFIG=$(pwd)/.kubeconfig.yaml
```

## Structure

```
k3s/
├── dashboards/                    # Grafana dashboards (manual import)
│   ├── clickhouse-monitoring.json
│   └── nginx-access-logs.json
├── ops-backoffice-tools/
│   ├── apps/
│   │   ├── appsmith/
│   │   ├── grafana/
│   │   ├── n8n/
│   │   ├── outline/
│   │   └── prometheus/
│   └── cluster/
│       ├── longhorn/
│       └── tailscale/
└── ops-logs-clickhouse/
    ├── apps/clickhouse/
    │   ├── manifests/
    │   └── schemas/
    └── cluster/tailscale/
```

---

## DigitalOcean Resources

### VPC

| Property | Value |
|----------|-------|
| Name | ops-vpc-k3s-nyc3 |
| Region | nyc3 |
| IP Range | 10.108.0.0/20 |

### Droplets

| Cluster | Name Pattern | Count | Specs | Tags |
|---------|--------------|-------|-------|------|
| tools | ops-vm-tools-k3s-nyc3-0X | 3 | 4 vCPU, 8GB, 160GB | k3s, tools_k3s |
| logs | ops-vm-logs-k3s-nyc3-0X | 3 | 4 vCPU, 8GB, 160GB | k3s, logs_k3s |

### Volumes (logs cluster)

| Name Pattern | Size | Mount Point |
|--------------|------|-------------|
| ops-vol-logs-k3s-nyc3-0X | 100GB | /mnt/ops-vol-logs-k3s-nyc3-0X |

### Load Balancer (tools cluster only)

| Name | Target Tag | Ports |
|------|------------|-------|
| ops-lb-tools-k3s-nyc3 | tools_k3s | 80→30080, 443→30443 (passthrough) |

Logs cluster uses Tailscale only (no public LB).

---

## Ansible Deployment

```bash
cd ansible

# Deploy cluster
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--cluster.yml \
  -e variable_host=tools_k3s  # or logs_k3s

# Longhorn storage (tools only)
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml \
  -e variable_host=tools_k3s

# ClickHouse tuning (logs only)
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--clickhouse.yml \
  -e variable_host=logs_k3s
```

---

## Tailscale Network

All inter-cluster communication via Tailscale.

| Device | Cluster | FQDN | Ports |
|--------|---------|------|-------|
| ops-k3s-backoffice-prometheus | tools | ops-k3s-backoffice-prometheus.batfish-ray.ts.net | 9090 |
| ops-k3s-clickhouse-logs | logs | ops-k3s-clickhouse-logs.batfish-ray.ts.net | 8123, 9000 |

See `tailscale/README.md` (repo root) for full device inventory.

---

## ClickHouse

### Users

| User | Profile | Access |
|------|---------|--------|
| admin | default | Full access |
| vector | default | Write to logs_nginx_* |
| grafana | readonly | Read-only (readonly=2 allows query settings) |

### Databases

| Database | Purpose |
|----------|---------|
| logs_nginx_stg | Staging nginx logs |
| logs_nginx_prd | Production nginx logs |

### Access

```bash
# Via Tailscale
clickhouse-client --host ops-k3s-clickhouse-logs.batfish-ray.ts.net \
  --user grafana --password

# Via kubectl
cd k3s/ops-logs-clickhouse
kubectl exec -it -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client
```

### Deploy Schema Changes

```bash
kubectl exec -i -n clickhouse chi-logs-logs-0-0-0 -- clickhouse-client \
  < apps/clickhouse/schemas/<file>.sql
```

---

## Grafana Dashboards

Import manually via Grafana UI (Dashboards > Import).

| Dashboard | File | Datasource |
|-----------|------|------------|
| ClickHouse Monitoring | `dashboards/clickhouse-monitoring.json` | ClickHouse (UI-configured) |
| NGINX Access Logs | `dashboards/nginx-access-logs.json` | ClickHouse (UI-configured) |

### ClickHouse Datasource (UI Configuration)

| Field | Value |
|-------|-------|
| Host | ops-k3s-clickhouse-logs.batfish-ray.ts.net |
| Port | 9000 |
| Protocol | Native |
| Username | grafana |
| Default Database | (leave empty) |

---

## Prometheus & Alerting

### Components

| Component | Purpose |
|-----------|---------|
| Prometheus | Metrics storage (50GB, 7-day retention) |
| Alertmanager | Routes to n8n webhooks |
| Node Exporter | Host metrics |
| Kube State Metrics | Workload metrics |

### Alert Webhooks

| Receiver | URL |
|----------|-----|
| n8n-default | https://n8n-wh.freecodecamp.net/webhook/alerts/default |
| n8n-critical | https://n8n-wh.freecodecamp.net/webhook/alerts/critical |
| n8n-custom | https://n8n-wh.freecodecamp.net/webhook/alerts/custom |

---

## Storage

| Class | Provisioner | Replicas | Use For |
|-------|-------------|----------|---------|
| longhorn | driver.longhorn.io | 2 | Stateful apps (tools cluster) |
| local-path | rancher.io/local-path | 1 | ClickHouse (logs cluster) |

### Longhorn Backups

- Target: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`
- Schedule: Daily 2 AM UTC
- Retention: 7 days

---

## DNS (Cloudflare)

| Record | Type | Value |
|--------|------|-------|
| appsmith.freecodecamp.net | A | tools LB |
| outline.freecodecamp.net | A | tools LB |
| grafana.freecodecamp.net | A | tools LB |
| n8n.freecodecamp.net | A | tools LB |
| n8n-wh.freecodecamp.net | A | tools LB |

ClickHouse/Prometheus: Tailscale only (no public DNS).

---

## Maintenance

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### Update Apps

```bash
kubectl apply -k apps/<app>/manifests/base/
```

### Helm Releases

```bash
# Grafana
helm upgrade grafana grafana/grafana -n grafana \
  -f apps/grafana/charts/grafana/values.yaml

# Prometheus
helm upgrade prometheus prometheus-community/kube-prometheus-stack -n prometheus \
  -f apps/prometheus/charts/kube-prometheus-stack/values.yaml
```

---

## Architecture

### ops-backoffice-tools

```
Internet → Cloudflare → DO LB → Traefik (NodePort) → Gateway API → Apps
                                                            │
                                              ┌─────────────┼─────────────┐
                                              ↓             ↓             ↓
                                          Appsmith      Grafana        n8n
                                          Outline     Prometheus    (queue mode)
                                              │             │             │
                                              └─────────────┴─────────────┘
                                                           │
                                                      Longhorn
                                                   (2 replicas)
                                                         │
                                              Tailscale ←─┘
                                                  │
                                                  ↓
                                          ops-logs-clickhouse
```

| App | Replicas | Storage | Database |
|-----|----------|---------|----------|
| Appsmith | 1 | 10Gi | Embedded |
| Outline | 1 | 10Gi + 10Gi | PostgreSQL sidecar |
| Grafana | 1 | 5Gi | Embedded SQLite |
| n8n | 1 main + 2 workers | 10Gi + 20Gi | PostgreSQL sidecar |
| Prometheus | 1 | 50Gi | TSDB |
| Alertmanager | 1 | 10Gi | - |

### ops-logs-clickhouse

```
                    Tailscale Only (no public LB)
                              │
                              ↓
                     ClickHouse Cluster
              ┌───────────────┼───────────────┐
              ↓               ↓               ↓
         chi-logs-0-0    chi-logs-0-1    chi-logs-0-2
           (80Gi)          (80Gi)          (80Gi)
              │               │               │
              └───────────────┼───────────────┘
                              │
                              ↓
                    ClickHouse Keeper
              ┌───────────────┼───────────────┐
              ↓               ↓               ↓
         keeper-0-0      keeper-0-1      keeper-0-2
           (5Gi)           (5Gi)           (5Gi)
```

| Component | Replicas | Storage | Class |
|-----------|----------|---------|-------|
| ClickHouse | 3 | 80Gi each | local-path |
| Keeper | 3 | 5Gi each | local-path |

### Design Strengths

- **Cluster separation**: Tools vs Logs isolates workloads
- **HA ClickHouse**: 3 replicas with Keeper consensus
- **Tailscale private mesh**: No public exposure of ClickHouse/Prometheus
- **Gateway API**: Modern ingress with Traefik
- **Longhorn backups**: Daily to DO Spaces, 7-day retention
- **n8n queue mode**: Scalable workers for workflow execution

---

## Playbooks Reference

| Playbook | Purpose |
|----------|---------|
| play-k3s--cluster.yml | Deploy k3s HA cluster |
| play-k3s--longhorn.yml | Install Longhorn storage |
| play-k3s--clickhouse.yml | ClickHouse node tuning |
| play-o11y--vector.yml | Deploy Vector log shipper |
