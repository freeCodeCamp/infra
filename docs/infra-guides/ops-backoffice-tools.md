# ops-backoffice-tools

Internal tools cluster on k3s with Longhorn storage.

Run every command on this page from the repository root.

## Access

```bash
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml get nodes
```

## Applications

| App      | Namespace | URL                       |
| -------- | --------- | ------------------------- |
| Appsmith | appsmith  | `https://<appsmith-host>` |
| Outline  | outline   | `https://<outline-host>`  |

The hostnames are in the Cloudflare DNS dashboard.

## Storage

- **Longhorn**: Replicas=2, daily backups to DO Spaces
- **Backup Target**: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`

---

## Tailscale Operator

Gives tailnet access to the cluster services. It is the only Tailscale device the repository defines ([`tailscale.md`](./tailscale.md)).

`read -rs` takes the OAuth client secret without echo, so it stays out of the shell history.

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
(
  printf 'OAuth client secret: '
  read -rs TS_OAUTH_CLIENT_SECRET; echo
  helm --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml upgrade tailscale-operator tailscale/tailscale-operator \
    --namespace tailscale --create-namespace --install \
    -f k3s/ops-backoffice-tools/cluster/tailscale/operator-values.yaml \
    --set oauth.clientId=<CLIENT_ID> \
    --set-file oauth.clientSecret=<(printf %s "$TS_OAUTH_CLIENT_SECRET")
)
```

---

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
  kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml apply -k "k3s/ops-backoffice-tools/apps/$APP/manifests/base/"
rm -f "$SEC/.secrets.env" "$SEC/tls.crt" "$SEC/tls.key"

# Check
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml get all -n <app>

# Logs
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml logs -n <app> deploy/<app>
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
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml logs -n tailscale deploy/operator
```

### PVC Stuck Pending

```bash
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml get volumes.longhorn.io -n longhorn-system
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml describe pvc -n <namespace> <pvc-name>
```

### Longhorn UI

```bash
kubectl --kubeconfig k3s/ops-backoffice-tools/.kubeconfig.yaml port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```
