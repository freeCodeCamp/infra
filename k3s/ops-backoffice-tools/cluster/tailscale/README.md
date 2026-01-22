# Tailscale Configuration - ops-backoffice-tools

Tailscale operator for the ops-backoffice-tools k3s cluster.

## Devices

| Device | Type | Purpose |
|--------|------|---------|
| `ops-k3s-backoffice-operator` | Operator | Manages Tailscale resources |
| `ops-k3s-backoffice-prometheus` | Ingress | Prometheus accessible via `ops-k3s-backoffice-prometheus.batfish-ray.ts.net` |

## Files

| File | Purpose |
|------|---------|
| `operator-values.yaml` | Helm values for Tailscale operator |

## Install/Upgrade Operator

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
helm upgrade tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale --create-namespace --install \
  -f cluster/tailscale/operator-values.yaml \
  --set oauth.clientId=<CLIENT_ID> \
  --set oauth.clientSecret=<CLIENT_SECRET>
```

## Accessing Services

External consumers reach services via Tailscale FQDN:
- Prometheus: `http://ops-k3s-backoffice-prometheus.batfish-ray.ts.net:9090`

## See Also

- Master inventory: `tailscale/README.md` (repo root)
- Prometheus ingress: `apps/prometheus/manifests/base/tailscale-ingress.yaml`
