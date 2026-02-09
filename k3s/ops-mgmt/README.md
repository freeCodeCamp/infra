# ops-mgmt

| Property | Value                             |
| -------- | --------------------------------- |
| Purpose  | Cluster API management            |
| Region   | nyc3                              |
| Nodes    | 3x s-2vcpu-4gb                    |
| VPC      | ops-vpc-mgmt-nyc3 (10.109.0.0/20) |
| Access   | Tailscale only (no public LB)     |

---

## Components

| Component                       | Version  | Purpose                              |
| ------------------------------- | -------- | ------------------------------------ |
| CAPI Core Controller            | v1.10.10 | Manages Cluster/Machine resources    |
| CAPI k3s Bootstrap Provider     | v0.3.0   | Generates k3s cloud-init             |
| CAPI k3s Control Plane Provider | v0.3.0   | Manages k3s control planes           |
| CAPDO                           | v1.6.0   | DigitalOcean infrastructure provider |

---

## Quick Start

```bash
cd k3s/ops-mgmt
export $(cat .env | xargs)
kubectl get nodes
kubectl get pods -A | grep -E "(capi|capdo)"
kubectl get clusters -n clusters
```

---

## Managing Workload Clusters

### Create a cluster

```bash
# Copy and customize the sample manifest
cp clusters/ops-backoffice.yaml.sample clusters/ops-backoffice.yaml
# Edit to replace placeholders (<YOUR-DO-SSH-KEY-ID>, <YOUR-TAILSCALE-AUTH-KEY>)

# Apply the manifest
kubectl apply -f clusters/ops-backoffice.yaml

# Monitor provisioning
clusterctl describe cluster ops-backoffice -n clusters
kubectl get machines -n clusters -w
```

### Scale a cluster

```bash
# Edit the KThreesControlPlane replicas field
kubectl edit kthreescontrolplane ops-backoffice-control-plane -n clusters
```

### Delete a cluster

```bash
kubectl delete cluster ops-backoffice -n clusters
```

---

## Maintenance

### CAPI Upgrade

```bash
# Check available upgrades
clusterctl upgrade plan

# Apply upgrade (all providers must support the target contract)
clusterctl upgrade apply --contract v1beta1
```

### etcd Backup

```bash
# Take a manual snapshot
sudo k3s etcd-snapshot save --name capi-backup-$(date +%Y%m%d)

# List snapshots
sudo k3s etcd-snapshot ls
```

---

## Troubleshooting

### CAPI Controller Logs

```bash
# Core controller
kubectl logs -n capi-system deploy/capi-controller-manager -f

# Bootstrap provider
kubectl logs -n capi-k3s-bootstrap-system deploy/capi-k3s-bootstrap-controller-manager -f

# Control plane provider
kubectl logs -n capi-k3s-control-plane-system deploy/capi-k3s-control-plane-controller-manager -f

# Infrastructure provider
kubectl logs -n capdo-system deploy/capdo-controller-manager -f
```

### Cluster Stuck Provisioning

```bash
# Check cluster status and conditions
clusterctl describe cluster <cluster-name> -n clusters

# Check machine status
kubectl get machines -n clusters -o wide

# Check infrastructure resources
kubectl get doclusters,domachines -n clusters

# Check events for errors
kubectl get events -n clusters --sort-by='.lastTimestamp' | tail -20
```

---

## Version Compatibility

All providers use the **v1beta1** contract. When providers release v1beta2 support, upgrade to CAPI v1.12+.
