# Tailscale Configuration - ops-logs-clickhouse

Tailscale operator for the ops-logs-clickhouse k3s cluster.

## Devices

| Device | Type | Purpose |
|--------|------|---------|
| `ops-k3s-clickhouse-operator` | Operator | Manages Tailscale resources |
| `ops-k3s-clickhouse-logs` | Ingress | ClickHouse accessible via `ops-k3s-clickhouse-logs.batfish-ray.ts.net` |

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

## Accessing ClickHouse

External consumers reach ClickHouse via Tailscale FQDN:
- HTTP: `http://ops-k3s-clickhouse-logs.batfish-ray.ts.net:8123`
- Native: `ops-k3s-clickhouse-logs.batfish-ray.ts.net:9000`

## See Also

- Master inventory: `tailscale/README.md` (repo root)
- ClickHouse ingress: `apps/clickhouse/manifests/base/service-tailscale.yaml`
