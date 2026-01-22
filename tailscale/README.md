# Tailscale Infrastructure Inventory

Master inventory of all Tailscale devices across the infrastructure.

## Architecture

```
                      Tailscale Network (batfish-ray.ts.net)
                                    |
          +-------------------------+-------------------------+
          |                         |                         |
          v                         v                         v
+-------------------+    +--------------------+    +------------------+
| backoffice-tools  |    | logs-clickhouse    |    | Docker Swarm     |
| k3s cluster       |    | k3s cluster        |    | (13 nodes)       |
|                   |    |                    |    |                  |
| - operator        |    | - operator         |    | Host Tailscale   |
| - prometheus      |    | - clickhouse       |    |                  |
+-------------------+    +--------------------+    +------------------+
```

## Device Inventory

| Device | Cluster | Type | FQDN |
|--------|---------|------|------|
| `ops-k3s-backoffice-operator` | backoffice-tools | Operator | - |
| `ops-k3s-backoffice-prometheus` | backoffice-tools | Ingress | `ops-k3s-backoffice-prometheus.batfish-ray.ts.net` |
| `ops-k3s-clickhouse-operator` | logs-clickhouse | Operator | - |
| `ops-k3s-clickhouse-logs` | logs-clickhouse | Ingress | `ops-k3s-clickhouse-logs.batfish-ray.ts.net` |

**Total: 4 devices**

## Naming Convention

| Pattern | Example | Purpose |
|---------|---------|---------|
| `ops-k3s-<cluster>-operator` | `ops-k3s-backoffice-operator` | Kubernetes operator |
| `ops-k3s-<cluster>-<service>` | `ops-k3s-backoffice-prometheus` | Service ingress |

## Service Access

| Service | FQDN | Ports |
|---------|------|-------|
| Prometheus | `ops-k3s-backoffice-prometheus.batfish-ray.ts.net` | 9090 |
| ClickHouse | `ops-k3s-clickhouse-logs.batfish-ray.ts.net` | 8123 (HTTP), 9000 (Native) |

## Docker Swarm

Swarm nodes access k3s services via Tailscale FQDN:
- Prometheus Agent remote_write: `ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090`

## Configuration

| Cluster | Path |
|---------|------|
| backoffice-tools | `k3s/ops-backoffice-tools/cluster/tailscale/` |
| logs-clickhouse | `k3s/ops-logs-clickhouse/cluster/tailscale/` |

## Management

**Admin Console:** https://login.tailscale.com/admin/machines

**Upgrade Operators:**
```bash
helm upgrade tailscale-operator tailscale/tailscale-operator \
  -n tailscale -f cluster/tailscale/operator-values.yaml \
  --set oauth.clientId=<ID> --set oauth.clientSecret=<SECRET>
```
