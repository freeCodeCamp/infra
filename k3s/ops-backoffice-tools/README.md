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
```

### PVC Stuck Pending

```bash
kubectl get volumes.longhorn.io -n longhorn-system
kubectl describe pvc -n <namespace> <pvc-name>
```

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```
