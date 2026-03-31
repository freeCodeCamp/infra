# ops-mgmt k3s Cluster

Rancher management cluster for provisioning and managing downstream Kubernetes clusters.

## Specifications

- **Node**: 1x s-4vcpu-8gb (DigitalOcean, nyc3)
- **Pod CIDR**: 10.40.0.0/16
- **Service CIDR**: 10.41.0.0/16
- **Tailscale hostname**: ops-k3s-mgmt-subnet

## Quick Access

```bash
cd k3s/ops-mgmt && export $(cat .env | xargs)
kubectl get nodes
```

## Deployment

Everything is managed by a single Ansible playbook (8 plays):

```bash
cd ansible/
ansible-playbook -i inventory/digitalocean.yml play-k3s--ops-mgmt.yml \
  -e variable_host=mgmt_k3s \
  --vault-password-file <(op read "op://Service-Automation/Ansible-Vault-Password/Ansible-Vault-Password")
```

The playbook handles: k3s install, security hardening (secrets-encryption, PSS, audit logging),
cert-manager, Rancher, rancher-backup + schedule, Tailscale operator + Connector,
kubeconfig fetch, and DO firewall lockdown.

Prerequisites: VM provisioned with Tailscale installed, Ansible Vault populated.

## Re-runs

After first run, the DO firewall restricts SSH to Tailscale only. Re-run via Tailscale IP:

```bash
ansible-playbook -i inventory/digitalocean.yml play-k3s--ops-mgmt.yml \
  -e variable_host=mgmt_k3s \
  -e ansible_host=<tailscale_ip> \
  --vault-password-file <(op read "op://Service-Automation/Ansible-Vault-Password/Ansible-Vault-Password")
```

## Disaster Recovery

- **rancher-backup operator** takes snapshots every 6 hours to DO Spaces (`net.freecodecamp.ops-k3s-backups/rancher-backup`)
- **etcd snapshots** every 6 hours to DO Spaces (`net.freecodecamp.ops-k3s-backups/etcd/ops-mgmt`)
- Downstream clusters continue operating independently if ops-mgmt is lost
- Restore: deploy fresh k3s + Rancher, then `kubectl apply -f` a Restore CR pointing to the backup
