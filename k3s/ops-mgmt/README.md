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

## Setup

1. **Provision node and install k3s** via Ansible playbook:

   ```bash
   ansible-playbook -i inventory/digitalocean.yml play-k3s--cluster.yml \
     -e '{"variable_host": "mgmt_k3s"}'
   ```

2. **Install Tailscale operator**:

   ```bash
   helm repo add tailscale https://pkgs.tailscale.com/helmcharts
   helm install tailscale-operator tailscale/tailscale-operator \
     --namespace tailscale --create-namespace \
     -f cluster/tailscale/operator-values.yaml \
     --set oauth.clientId=<ID> --set oauth.clientSecret=<SECRET>
   kubectl apply -f cluster/tailscale/connector.yaml
   kubectl apply -f cluster/tailscale/proxyclass.yaml
   ```

3. **Install Rancher + cert-manager + backup operator**:

   ```bash
   ./apps/rancher/install.sh
   ```

4. **Configure backup storage** (requires S3 credentials secret):
   ```bash
   kubectl create secret generic rancher-backup-s3-creds \
     -n cattle-resources-system \
     --from-literal=accessKey=<KEY> \
     --from-literal=secretKey=<SECRET>
   kubectl apply -f apps/rancher/backup-schedule.yaml
   ```

## Disaster Recovery

- **rancher-backup operator** takes snapshots every 6 hours to DO Spaces (`net.freecodecamp.ops-k3s-backups/rancher-backup`)
- Retains last 20 backups
- Downstream clusters continue operating independently if ops-mgmt is lost
- Restore: deploy fresh k3s + Rancher, then `kubectl apply -f` a Restore CR pointing to the backup
