# Tailscale Infrastructure Inventory

Tailscale devices that the repository defines in a file. Hosts also join the tailnet through `ansible/play-tailscale--1a-up.yml` (the Linode fleet), and the `ops-o11y` nodes use it for the API and NodePorts (`ansible/inventory/group_vars/ops_o11y.yml:6`). The admin console lists every device.

## Architecture

```
                      Tailscale Network (<tailnet>.ts.net)
                                    |
                    +---------------+---------------+
                    |                               |
                    v                               v
          +-------------------+          +------------------+
          | backoffice-tools  |          | Docker Swarm     |
          | k3s cluster       |          |                  |
          |                   |          |                  |
          | - operator        |          | Host Tailscale   |
          +-------------------+          +------------------+
```

## Device Inventory

| Device                        | Cluster          | Type     | FQDN |
| ----------------------------- | ---------------- | -------- | ---- |
| `ops-k3s-backoffice-operator` | backoffice-tools | Operator | -    |

**Defined in the repository: 1 device**

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

**Install or upgrade the operator:** [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#tailscale-operator).
