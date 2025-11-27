# K3s Infrastructure Documentation

> Last updated: 2025-11-27

## Overview

Self-hosted k3s cluster on DigitalOcean for internal tools (Appsmith, etc.).

| Component | Value |
|-----------|-------|
| Region | NYC3 |
| Nodes | 3 (HA control plane) |
| K3s Version | v1.33.6+k3s1 |
| Container Runtime | containerd 2.1.5 |
| OS | Ubuntu 24.04.3 LTS |

---

## DigitalOcean Resources

### VPC

| Property | Value |
|----------|-------|
| Name | `ops-vpc-tools-k3s-nyc3` |
| ID | Get via: `doctl vpcs list \| grep k3s` |
| IP Range | `10.108.0.0/20` |
| Region | nyc3 |

### Droplets

| Name | Private IP | Specs |
|------|-----------:|-------|
| ops-vm-tools-k3s-nyc3-01 | 10.108.0.4 | 4 vCPU, 8GB RAM, 160GB |
| ops-vm-tools-k3s-nyc3-02 | 10.108.0.5 | 4 vCPU, 8GB RAM, 160GB |
| ops-vm-tools-k3s-nyc3-03 | 10.108.0.6 | 4 vCPU, 8GB RAM, 160GB |

All tagged: `tools-k3s`

### Load Balancer

| Property | Value |
|----------|-------|
| Name | `ops-lb-tools-k3s-nyc3-01` |
| IP | Get via: `doctl compute load-balancer list \| grep k3s` |
| VPC | `ops-vpc-tools-k3s-nyc3` |
| Target Droplets | All 3 k3s nodes |

**Forwarding Rules:**

| Entry Protocol | Entry Port | Target Protocol | Target Port | TLS |
|----------------|------------|-----------------|-------------|-----|
| HTTP | 80 | HTTP | 30080 | - |
| HTTPS | 443 | HTTPS | 30443 | Passthrough |

**Health Check:**
- Protocol: TCP
- Port: 30443
- Interval: 10s
- Timeout: 5s
- Healthy threshold: 5
- Unhealthy threshold: 3

### Firewall

| Property | Value |
|----------|-------|
| Name | `tools-fw-nyc3` |
| ID | Get via: `doctl compute firewall list \| grep tools` |

**Inbound Rules:**

| Protocol | Ports | Source |
|----------|-------|--------|
| ICMP | - | VPC (10.108.0.0/20) |
| TCP | All | VPC (10.108.0.0/20) |
| UDP | All | VPC (10.108.0.0/20) |
| TCP | 22 | 0.0.0.0/0 (SSH) |
| TCP | 30080 | Load Balancer only |
| TCP | 30443 | Load Balancer only |

**Outbound Rules:** All traffic allowed (TCP/UDP/ICMP to 0.0.0.0/0)

---

## Kubernetes Cluster

### Control Plane

All 3 nodes are control-plane/etcd/master (HA configuration):

```
┌─────────────────────────────────────────────────────────────┐
│                    K3s HA Cluster                           │
├─────────────────┬─────────────────┬─────────────────────────┤
│     Node 01     │     Node 02     │        Node 03          │
│   10.108.0.4    │   10.108.0.5    │      10.108.0.6         │
├─────────────────┼─────────────────┼─────────────────────────┤
│ control-plane   │ control-plane   │ control-plane           │
│ etcd            │ etcd            │ etcd                    │
│ master          │ master          │ master                  │
├─────────────────┼─────────────────┼─────────────────────────┤
│ coredns         │ traefik         │ appsmith                │
│ metrics-server  │ longhorn        │ longhorn                │
│ longhorn        │                 │                         │
├─────────────────┴─────────────────┴─────────────────────────┤
│          Longhorn Replicated Storage (2 replicas)           │
└─────────────────────────────────────────────────────────────┘
```

### API Server Access

```yaml
server: https://ops-vm-tools-k3s-nyc3-01:6443
```

Kubeconfig uses hostname resolution (likely via `/etc/hosts` or Tailscale).

### Resource Usage (as of inspection)

| Node | CPU | Memory |
|------|-----|--------|
| node-01 | 92m (2%) | 1497Mi (18%) |
| node-02 | 78m (1%) | 817Mi (10%) |
| node-03 | 58m (1%) | 1978Mi (24%) |

**Total Capacity per Node:** 4 CPU, 8GB RAM

---

## Networking

### Traffic Flow

```
Internet
    │
    ▼
┌──────────────────────────────────┐
│       DO Load Balancer            │
│  - HTTP:80 → NodePort:30080      │
│  - HTTPS:443 → NodePort:30443    │
└──────────────────────────────────┘
    │
    ▼ (VPC: 10.108.0.0/20)
┌──────────────────────────────────┐
│  Firewall (tools-fw-nyc3)        │
│  - Only LB can reach 30080/30443 │
│  - SSH open (consider limiting)  │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│  Traefik (NodePort Service)      │
│  - 30080 → web (HTTP)            │
│  - 30443 → websecure (HTTPS)     │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│  Gateway API                     │
│  - GatewayClass: traefik         │
│  - Gateway per namespace         │
│  - HTTPRoutes for routing        │
└──────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────┐
│  Application Services (ClusterIP)│
│  - appsmith:80                   │
└──────────────────────────────────┘
```

### Traefik Configuration

Located at: `cluster/charts/traefik/values.yaml`

Key settings:
- **Service Type:** NodePort (for DO LB compatibility)
- **NodePorts:** 30080 (HTTP), 30443 (HTTPS)
- **Gateway API:** Enabled
- **TLS Passthrough:** Yes (terminates at app Gateway)
- **Access Logs:** Enabled

### Pod Network

- CIDR: `10.42.0.0/16` (default k3s)
- Service CIDR: `10.43.0.0/16`
- DNS: CoreDNS at `10.43.0.10`

---

## Storage

### Longhorn (Primary)

Distributed block storage with cross-node replication.

| Property | Value |
|----------|-------|
| Version | v1.10.1 |
| Provisioner | `driver.longhorn.io` |
| Default Replicas | 2 (survives 1 node failure) |
| Data Path | `/var/lib/longhorn/` |
| Config | `cluster/charts/longhorn/values.yaml` |

**Failover Tested:** Pod reschedules to healthy node, mounts replica, continues working.

```bash
# Longhorn UI (port-forward)
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Check volumes
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get replicas.longhorn.io -n longhorn-system -o wide
```

### Local Path (Legacy)

Still available for non-critical workloads. Single-node, no replication.

| Property | Value |
|----------|-------|
| Provisioner | `rancher.io/local-path` |
| Storage Path | `/var/lib/rancher/k3s/storage/` |

### Storage Classes

| Name | Provisioner | Replicas | Use For |
|------|-------------|----------|---------|
| `longhorn` | driver.longhorn.io | 2 | Databases, stateful apps |
| `local-path` (default) | rancher.io/local-path | 1 | Ephemeral, non-critical |

---

## Installed Components

### System (kube-system)

| Component | Purpose |
|-----------|---------|
| CoreDNS | Cluster DNS |
| Traefik | Ingress/Gateway controller |
| Local Path Provisioner | Legacy storage |
| Metrics Server | Resource metrics |

### Longhorn (longhorn-system)

| Component | Replicas |
|-----------|----------|
| longhorn-manager | 3 (DaemonSet) |
| longhorn-driver-deployer | 1 |
| longhorn-csi-plugin | 3 (DaemonSet) |
| longhorn-ui | 1 |
| csi-attacher/provisioner/resizer/snapshotter | 2 each |

### Gateway API CRDs

- `gatewayclasses.gateway.networking.k8s.io`
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `grpcroutes.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`

### Traefik CRDs

- `middlewares.traefik.io`
- `ingressroutes.traefik.io`
- `serverstransports.traefik.io`
- `tlsoptions.traefik.io`

---

## Applications

### Appsmith

| Property | Value |
|----------|-------|
| Namespace | `appsmith` |
| Domain | `appsmith.freecodecamp.net` |
| Gateway | `appsmith-gateway` |
| HTTPRoutes | `appsmith-route`, `http-redirect` |
| Storage | 10Gi PVC (longhorn, 2 replicas) |

### Outline

| Property | Value |
|----------|-------|
| Namespace | `outline` |
| Domain | `outline.freecodecamp.net` |
| Gateway | `outline-gateway` |
| HTTPRoutes | `outline-route`, `http-redirect` |
| Storage | 10Gi PostgreSQL + 10Gi data (longhorn) |
| Auth | Google OAuth |
| Components | Outline + PostgreSQL + Redis (single pod) |

---

## Security Considerations

1. **SSH Access:** Currently open to 0.0.0.0/0 - consider restricting to known IPs or Tailscale
2. **Firewall:** NodePorts only accessible via Load Balancer (good)
3. **TLS:** Passthrough to application Gateways (Cloudflare origin certs)
4. **API Server:** Accessible via hostname (requires VPN/hosts entry)

---

## DNS Configuration

| Domain | Type | Target |
|--------|------|--------|
| appsmith.freecodecamp.net | A | `<LB_IP>` |
| outline.freecodecamp.net | A | `<LB_IP>` |

DNS managed in Cloudflare (proxied or DNS-only based on requirements).

---

## Maintenance Commands

```bash
# Set kubeconfig (or use direnv)
cd k3s
export KUBECONFIG=./.kubeconfig.yaml

# Check cluster health
kubectl get nodes -o wide
kubectl top nodes

# Check all pods
kubectl get pods -A

# Check storage
kubectl get pv,pvc -A
kubectl get storageclass

# Check gateways
kubectl get gateway,httproute -A

# DO resources
doctl compute droplet list | grep k3s
doctl compute load-balancer list | grep k3s
doctl compute firewall list | grep tools
```

---

## Architecture Diagram

```
                                    ┌─────────────────────────────────┐
                                    │         Cloudflare              │
                                    │  appsmith.freecodecamp.net      │
                                    └───────────────┬─────────────────┘
                                                    │
                                                    ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                        DigitalOcean NYC3                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                    Load Balancer                                        │  │
│  │                    HTTP:80 → 30080, HTTPS:443 → 30443                   │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                    Firewall (tools-fw-nyc3)                             │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.108.0.0/20)                                  │  │
│  │  ┌─────────────────┬─────────────────┬─────────────────┐               │  │
│  │  │   Node 01       │   Node 02       │   Node 03       │               │  │
│  │  │  10.108.0.4     │  10.108.0.5     │  10.108.0.6     │               │  │
│  │  │                 │                 │                 │               │  │
│  │  │  ┌───────────┐  │  ┌───────────┐  │  ┌───────────┐  │               │  │
│  │  │  │ coredns   │  │  │ traefik   │  │  │ appsmith  │  │               │  │
│  │  │  │ metrics   │  │  │ longhorn  │  │  │ longhorn  │  │               │  │
│  │  │  │ longhorn  │  │  │           │  │  │           │  │               │  │
│  │  │  └───────────┘  │  └───────────┘  │  └───────────┘  │               │  │
│  │  │                 │                 │                 │               │  │
│  │  │  ════════════ Longhorn Replicated Storage ═══════════               │  │
│  │  │                 │                 │                 │               │  │
│  │  │  [etcd]         │  [etcd]         │  [etcd]         │               │  │
│  │  │  [api-server]   │  [api-server]   │  [api-server]   │               │  │
│  │  └─────────────────┴─────────────────┴─────────────────┘               │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘
```
