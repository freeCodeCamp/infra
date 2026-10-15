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

**Upgrade Operators:** run from the repository root. `read -rs` takes the OAuth client secret without echo, so it stays out of the shell history.

```bash
(
  printf 'OAuth client secret: '
  read -rs TS_OAUTH_CLIENT_SECRET; echo
  KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml helm upgrade tailscale-operator tailscale/tailscale-operator \
    -n tailscale -f k3s/ops-backoffice-tools/cluster/tailscale/operator-values.yaml \
    --set oauth.clientId=<ID> --set-file oauth.clientSecret=<(printf %s "$TS_OAUTH_CLIENT_SECRET")
)
```
