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
| n8n      | n8n       | https://n8n.freecodecamp.net      |

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

## n8n

### Deploy

```bash
kubectl apply -k apps/n8n/manifests/base/
```

### Secrets

File: `apps/n8n/manifests/base/secrets/.secrets.env`

| Variable           | Description               |
| ------------------ | ------------------------- |
| N8N_ENCRYPTION_KEY | `openssl rand -hex 32`    |
| JWT_SECRET         | `openssl rand -hex 32`    |
| POSTGRES_PASSWORD  | `openssl rand -base64 24` |

### Architecture

- **n8n-main**: UI, API, webhooks (1 replica)
- **n8n-worker**: Execution (2 replicas)
- **n8n-postgres**: Database (20Gi)
- **n8n-redis**: Queue

### Scale Workers

```bash
kubectl scale deploy/n8n-worker -n n8n --replicas=3
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
