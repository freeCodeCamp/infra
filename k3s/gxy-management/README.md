# gxy-management

First Universe galaxy. Control plane brain — manages all galaxies.

## Specifications

- **Nodes**: 3× DigitalOcean s-8vcpu-16gb (nyc3)
- **CNI**: Cilium (eBPF, Hubble observability)
- **Pod CIDR**: 10.1.0.0/16
- **Service CIDR**: 10.11.0.0/16
- **Storage**: local-path (K3s default)
- **Ingress**: Traefik (Day 0), Cilium Gateway API (target)

## Applications

| App      | Purpose               | Access                          |
| -------- | --------------------- | ------------------------------- |
| Windmill | Workflow engine       | NodePort 30080 via Tailscale IP |
| ArgoCD   | GitOps (all galaxies) | NodePort 30443 via Tailscale IP |
| Zot      | Container registry    | NodePort 30500 via Tailscale IP |

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
