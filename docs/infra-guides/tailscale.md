# Tailscale Infrastructure Inventory

Master inventory of all Tailscale devices across the infrastructure.

## Architecture

```
                      Tailscale Network (batfish-ray.ts.net)
                                    |
                    +---------------+---------------+
                    |                               |
                    v                               v
          +-------------------+          +------------------+
          | backoffice-tools  |          | Docker Swarm     |
          | k3s cluster       |          | (13 nodes)       |
          |                   |          |                  |
          | - operator        |          | Host Tailscale   |
          +-------------------+          +------------------+
```

## Device Inventory

| Device                        | Cluster          | Type     | FQDN |
| ----------------------------- | ---------------- | -------- | ---- |
| `ops-k3s-backoffice-operator` | backoffice-tools | Operator | -    |

**Total: 1 device**

## Naming Convention

| Pattern                       | Example                        | Purpose             |
| ----------------------------- | ------------------------------ | ------------------- |
| `ops-k3s-<cluster>-operator`  | `ops-k3s-backoffice-operator`  | Kubernetes operator |
| `ops-k3s-<cluster>-<service>` | `ops-k3s-backoffice-<service>` | Service ingress     |

## Configuration

| Cluster          | Path                                          |
| ---------------- | --------------------------------------------- |
| backoffice-tools | `k3s/ops-backoffice-tools/cluster/tailscale/` |

## Management

**Admin Console:** https://login.tailscale.com/admin/machines

**Upgrade Operators:**

```bash
helm upgrade tailscale-operator tailscale/tailscale-operator \
  -n tailscale -f cluster/tailscale/operator-values.yaml \
  --set oauth.clientId=<ID> --set oauth.clientSecret=<SECRET>
```
