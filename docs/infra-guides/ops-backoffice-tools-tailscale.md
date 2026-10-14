# Tailscale Configuration - ops-backoffice-tools

Tailscale operator for the ops-backoffice-tools k3s cluster.

## Devices

| Device                        | Type     | Purpose                     |
| ----------------------------- | -------- | --------------------------- |
| `ops-k3s-backoffice-operator` | Operator | Manages Tailscale resources |

## Files

| File                   | Purpose                            |
| ---------------------- | ---------------------------------- |
| `operator-values.yaml` | Helm values for Tailscale operator |

## Install/Upgrade Operator

Run from the repository root. `read -rs` takes the OAuth client secret without echo, so it stays out of the shell history.

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
(
  printf 'OAuth client secret: '
  read -rs TS_OAUTH_CLIENT_SECRET; echo
  KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml helm upgrade tailscale-operator tailscale/tailscale-operator \
    --namespace tailscale --create-namespace --install \
    -f k3s/ops-backoffice-tools/cluster/tailscale/operator-values.yaml \
    --set oauth.clientId=<CLIENT_ID> \
    --set-file oauth.clientSecret=<(printf %s "$TS_OAUTH_CLIENT_SECRET")
)
```

## See Also

- Master inventory: [`tailscale.md`](./tailscale.md)
