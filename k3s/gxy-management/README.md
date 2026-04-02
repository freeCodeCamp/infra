# gxy-management

First Universe galaxy. Control plane brain — manages all galaxies.

## Specifications

- **Nodes**: 3× DigitalOcean s-8vcpu-16gb (FRA1)
- **CNI**: Cilium (eBPF, Hubble observability)
- **Pod CIDR**: 10.1.0.0/16
- **Service CIDR**: 10.11.0.0/16
- **Storage**: local-path (K3s default)
- **Ingress**: Traefik (Day 0), Cilium Gateway API (target)

## Applications

| App      | Purpose               | Access                                    |
| -------- | --------------------- | ----------------------------------------- |
| Windmill | Workflow engine       | windmill.freecodecamp.net (all staff)     |
| ArgoCD   | GitOps (all galaxies) | argocd.freecodecamp.net (platform team)   |
| Zot      | Container registry    | registry.freecodecamp.net (platform team) |

## Quick Access

```bash
cd k3s/gxy-management && export KUBECONFIG=$(pwd)/.kubeconfig.yaml
kubectl get nodes
```

## Deploy

```bash
cd ansible
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--galaxy.yml \
  -e variable_host=gxy_mgmt_k3s \
  -e galaxy_name=gxy-management \
  --vault-password-file <(op read "op://Service-Automation/Ansible-Vault-Password/Ansible-Vault-Password")
```

## Deployment Runbook

### Pre-deployment (ClickOps)

1. Create 3x DO droplets (s-8vcpu-16gb) in FRA1 -- attach to VPC, configure firewall (80, 443, 6443 from VPC, 22 from Tailscale)
2. Create DO Spaces bucket `net.freecodecamp.universe-backups` in FRA1 (etcd snapshots)
3. Create DO Spaces bucket `net.freecodecamp.universe-registry` in FRA1 (Zot images)
4. Install Tailscale on all 3 nodes
5. Create Cloudflare origin certificate for `*.freecodecamp.net` (15-year, RSA)
6. Populate ansible-vault secrets (`vars/vault-k3s.yml`)
7. Populate app secrets (decrypt samples, fill values, encrypt)

### Helm Installations

After playbook completes, before app deploy:

```bash
helm install argocd argo-cd --repo https://argoproj.github.io/argo-helm -n argocd -f charts/argo-cd/values.yaml
helm install windmill windmill --repo https://windmill-labs.github.io/windmill-helm-charts/ -n windmill -f charts/windmill/values.yaml
helm install zot zot --repo https://zotregistry.dev/helm-charts/ -n zot -f charts/zot/values.yaml
```

**IMPORTANT: Helm release names must be exactly `argocd`, `windmill`, `zot`** -- the Gateway API HTTPRoute resources reference service names derived from these release names.

### Post-deployment (ClickOps)

1. Create DNS A records (proxied) for windmill/argocd/registry.freecodecamp.net pointing to all 3 node public IPs
2. Create Cloudflare Access policies for each service
3. Apply TLS secrets: `kubectl create secret tls <service>-tls-cloudflare --cert=tls.crt --key=tls.key -n <namespace>`
4. Apply kustomize manifests: `kubectl apply -k apps/<app>/manifests/base/ -n <ns>`

### Smoke Tests

1. `kubectl get nodes` -- all 3 Ready
2. `cilium status` -- all green
3. `curl -H "Host: windmill.freecodecamp.net" https://<node-ip> -k`
4. Verify Cloudflare Access gate
