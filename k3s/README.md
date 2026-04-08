# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose           | Apps                  |
| -------------------- | ----------------- | --------------------- |
| ops-backoffice-tools | Internal tools    | Appsmith, Outline     |
| gxy-management       | Universe platform | Windmill, ArgoCD, Zot |

## Quick Access

```bash
# Tools cluster
cd k3s/ops-backoffice-tools && export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Galaxy management cluster
cd k3s/gxy-management && export KUBECONFIG=$(pwd)/.kubeconfig.yaml
```

## Structure

```
k3s/
├── archive/                       # Archived configs (historical reference)
├── gxy-management/
│   ├── apps/
│   │   ├── argocd/
│   │   ├── windmill/
│   │   └── zot/
│   └── cluster/
│       ├── cilium/
│       └── security/
├── ops-backoffice-tools/
│   ├── apps/
│   │   ├── appsmith/
│   │   └── outline/
│   └── cluster/
│       ├── longhorn/
│       └── tailscale/
└── shared/
    └── traefik-config.yaml
```

---

## DigitalOcean Resources

### VPC

| Property | Value            |
| -------- | ---------------- |
| Name     | ops-vpc-k3s-nyc3 |
| Region   | nyc3             |
| IP Range | 10.108.0.0/20    |

### Droplets

| Cluster        | Name Pattern                | Count | Specs               | Tags                |
| -------------- | --------------------------- | ----- | ------------------- | ------------------- |
| tools          | ops-vm-tools-k3s-nyc3-0X    | 3     | 4 vCPU, 8GB, 160GB  | k3s, tools_k3s      |
| gxy-management | ops-vm-gxy-mgmt-k3s-fra1-0X | 3     | 8 vCPU, 16GB, 320GB | k3s, \_gxy-mgmt-k3s |

### Load Balancer

| Name                  | Target Tag | Ports                             |
| --------------------- | ---------- | --------------------------------- |
| ops-lb-tools-k3s-nyc3 | tools_k3s  | 80→30080, 443→30443 (passthrough) |

---

## Ansible Deployment

```bash
# Deploy tools cluster
just play k3s--cluster tools_k3s

# Longhorn storage (tools)
just play k3s--longhorn tools_k3s

# Deploy gxy-management galaxy (decrypts vault vars automatically)
just play k3s--bootstrap gxy_mgmt_k3s
```

---

## Tailscale Network

All inter-cluster communication via Tailscale.

See `tailscale/README.md` (repo root) for device inventory.

---

## Storage

| Class    | Provisioner        | Replicas | Use For                       |
| -------- | ------------------ | -------- | ----------------------------- |
| longhorn | driver.longhorn.io | 2        | Stateful apps (tools cluster) |

### Longhorn Backups

- Target: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`
- Schedule: Daily 2 AM UTC
- Retention: 7 days

---

## DNS (Cloudflare)

| Record                    | Type | Value                   |
| ------------------------- | ---- | ----------------------- |
| appsmith.freecodecamp.net | A    | tools LB                |
| outline.freecodecamp.net  | A    | tools LB                |
| windmill.freecodecamp.net | A    | gxy-management node IPs |
| argocd.freecodecamp.net   | A    | gxy-management node IPs |
| registry.freecodecamp.net | A    | gxy-management node IPs |

---

## Maintenance

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### Update Apps

```bash
just deploy <cluster> <app>
```

---

## Architecture

### ops-backoffice-tools

```
Internet → Cloudflare → DO LB → Traefik (NodePort) → Gateway API → Apps
                                                            │
                                              ┌─────────────┼─────────────┐
                                              ↓             ↓             ↓
                                          Appsmith       Outline
                                              │             │
                                              └─────────────┘
                                                           │
                                                      Longhorn
                                                   (2 replicas)
```

| App      | Replicas | Storage     | Database           |
| -------- | -------- | ----------- | ------------------ |
| Appsmith | 1        | 10Gi        | Embedded           |
| Outline  | 1        | 10Gi + 10Gi | PostgreSQL sidecar |

### gxy-management

```
Internet → Cloudflare → Node Public IPs → Traefik (ServiceLB) → Gateway API → Apps
                (Access)                                               │
                                                         ┌─────────────┼─────────────┐
                                                         ↓             ↓             ↓
                                                     Windmill       ArgoCD         Zot

CNI: Cilium    Storage: local-path    SSH/kubectl: Tailscale
```

| App      | Replicas            | Access            | Notes      |
| -------- | ------------------- | ----------------- | ---------- |
| Windmill | 1 server, 2 workers | Cloudflare Access |            |
| ArgoCD   | 1 (single replica)  | Cloudflare Access |            |
| Zot      | 1 (single replica)  | Cloudflare Access | S3 backend |

---

## Playbooks Reference

| Playbook                | Purpose                                               |
| ----------------------- | ----------------------------------------------------- |
| play-k3s--cluster.yml   | Deploy k3s HA cluster                                 |
| play-k3s--longhorn.yml  | Install Longhorn storage                              |
| play-k3s--bootstrap.yml | Deploy any Universe galaxy (K3s + Cilium + Tailscale) |
