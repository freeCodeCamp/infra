# ops-mgmt Cluster

CAPI management cluster for provisioning and managing workload clusters.

## Overview

| Property | Value |
|----------|-------|
| Purpose | Cluster API management |
| Region | nyc3 |
| Nodes | 3x s-2vcpu-4gb |
| VPC | ops-vpc-mgmt-nyc3 (10.109.0.0/20) |
| Access | Tailscale only (no public LB) |

## Components

- **CAPI Core Controller** - Manages Cluster/Machine resources
- **CAPI k3s Bootstrap Provider** - Generates k3s cloud-init
- **CAPI k3s Control Plane Provider** - Manages k3s control planes
- **CAPDO** - DigitalOcean infrastructure provider

## Quick Start

```bash
cd k3s/ops-mgmt
source .env  # or use direnv

# Check cluster health
kubectl get nodes

# Check CAPI controllers
kubectl get pods -A | grep -E "(capi|capdo)"

# List managed clusters
kubectl get clusters -n clusters
```

## Managing Workload Clusters

### Create a Cluster

```bash
# Apply cluster manifest
kubectl apply -f ../../clusters/<cluster-name>.yaml

# Watch provisioning
clusterctl describe cluster <cluster-name> -n clusters

# Get kubeconfig when ready
clusterctl get kubeconfig <cluster-name> -n clusters > ~/.kube/<cluster-name>.yaml
```

### Scale a Cluster

```bash
# Scale workers
kubectl patch machinedeployment <cluster>-workers -n clusters \
  -p '{"spec":{"replicas":5}}' --type=merge
```

### Delete a Cluster

```bash
kubectl delete cluster <cluster-name> -n clusters
```

## Maintenance

### Upgrade CAPI

```bash
# Check available upgrades
clusterctl upgrade plan

# Apply upgrade
clusterctl upgrade apply --contract v1beta1
```

### Backup etcd

```bash
# SSH to any node via Tailscale
ssh ops-vm-mgmt-k3s-nyc3-01

# Create snapshot
sudo k3s etcd-snapshot save --name capi-backup-$(date +%Y%m%d)

# List snapshots
sudo k3s etcd-snapshot ls
```

### Recovery

If management cluster fails:

1. Rebuild k3s cluster via Ansible
2. Restore etcd snapshot
3. Or: Re-initialize CAPI and re-apply cluster manifests from Git

## Troubleshooting

### CAPI Controller Logs

```bash
kubectl logs -n capi-system deployment/capi-controller-manager -f
kubectl logs -n capdo-system deployment/capdo-controller-manager -f
```

### Cluster Stuck Provisioning

```bash
# Check events
kubectl get events -n clusters --sort-by='.lastTimestamp'

# Describe cluster
clusterctl describe cluster <name> -n clusters --show-conditions=all
```

## Related

- [RFC-001: Multi-Cluster k3s Architecture](../../.claude/RFC/RFC-001-k3s-multi-cluster-capi.md)
