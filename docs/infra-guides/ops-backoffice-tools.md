# ops-backoffice-tools

Internal tools cluster on k3s with Longhorn storage.

Run every command on this page from the repository root.

## Access

```bash
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl get nodes
```

## Applications

| App      | Namespace | URL                               |
| -------- | --------- | --------------------------------- |
| Appsmith | appsmith  | https://appsmith.freecodecamp.net |
| Outline  | outline   | https://outline.freecodecamp.net  |

## Storage

- **Longhorn**: Replicas=2, daily backups to DO Spaces
- **Backup Target**: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`

______________________________________________________________________

## Tailscale Operator

Gives tailnet access to the cluster services. It is the only Tailscale device the repository defines ([`tailscale.md`](./tailscale.md)).

`read -rs` takes the OAuth client secret without echo, so it stays out of the shell history.

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

______________________________________________________________________

## Deployment Pattern

All apps use Kustomize:

```bash
# Deploy: decrypt the secrets and TLS, apply, then delete the plaintext
APP=<app>
ENC=../infra-secrets/k3s/ops-backoffice-tools
SEC=k3s/ops-backoffice-tools/apps/$APP/manifests/base/secrets
sops decrypt --input-type dotenv --output-type dotenv "$ENC/$APP.secrets.env.enc" > "$SEC/.secrets.env" &&
  sops decrypt "$ENC/$APP.tls.crt.enc" > "$SEC/tls.crt" &&
  sops decrypt "$ENC/$APP.tls.key.enc" > "$SEC/tls.key" &&
  KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl apply -k "k3s/ops-backoffice-tools/apps/$APP/manifests/base/"
rm -f "$SEC/.secrets.env" "$SEC/tls.crt" "$SEC/tls.key"

# Check
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl get all -n <app>

# Logs
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl logs -n <app> deploy/<app>
```

### Secrets Structure

```
apps/<app>/manifests/base/secrets/
├── .secrets.env         # Variables (gitignored)
├── .secrets.env.sample  # Template (committed)
├── tls.crt              # Certificate (gitignored)
└── tls.key              # Private key (gitignored)
```

______________________________________________________________________

## Troubleshooting

### Tailscale Connectivity

```bash
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl logs -n tailscale deploy/operator
```

### PVC Stuck Pending

```bash
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl get volumes.longhorn.io -n longhorn-system
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl describe pvc -n <namespace> <pvc-name>
```

### Longhorn UI

```bash
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```
