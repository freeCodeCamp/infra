# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose           | Apps                             |
| -------------------- | ----------------- | -------------------------------- |
| ops-backoffice-tools | Internal tools    | Appsmith, Outline                |
| gxy-management       | Universe platform | Windmill, ArgoCD, Zot (deferred) |
| gxy-static           | Static hosting    | Caddy                            |

## Quick Access

```bash
# Tools cluster
cd k3s/ops-backoffice-tools && export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Galaxy management cluster
cd k3s/gxy-management && export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Galaxy static cluster
cd k3s/gxy-static && export KUBECONFIG=$(pwd)/.kubeconfig.yaml
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
├── gxy-static/
│   ├── apps/
│   │   └── caddy/
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

| Cluster        | Name Pattern              | Count | Specs               | Tags           |
| -------------- | ------------------------- | ----- | ------------------- | -------------- |
| tools          | ops-vm-tools-k3s-nyc3-0X  | 3     | 4 vCPU, 8GB, 160GB  | tools_k3s      |
| gxy-management | gxy-vm-management-k3s-{1,2,3}   | 3     | 8 vCPU, 16GB, 320GB | gxy-management-k3s   |
| gxy-static     | gxy-vm-static-k3s-{1,2,3} | 3     | 4 vCPU, 8GB, 160GB  | gxy-static-k3s |

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

# Deploy gxy-management galaxy
just play k3s--bootstrap gxy_management_k3s

# Deploy gxy-static galaxy
just play k3s--bootstrap gxy_static_k3s
```

---

## Tailscale Network

Tailscale on nodes for SSH/kubectl access only (under review).

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

| Record                    | Type | Value                   | SSL Mode                 |
| ------------------------- | ---- | ----------------------- | ------------------------ |
| appsmith.freecodecamp.net | A    | tools LB                | Full (Strict)            |
| outline.freecodecamp.net  | A    | tools LB                | Full (Strict)            |
| windmill.freecodecamp.net | A    | gxy-management node IPs | Full (Strict)            |
| argocd.freecodecamp.net   | A    | gxy-management node IPs | Full (Strict)            |
| registry.freecodecamp.net | A    | gxy-management node IPs | Full (Strict) (deferred) |
| freecode.camp             | A    | gxy-static node IPs     | Flexible                 |
| \*.freecode.camp          | A    | gxy-static node IPs     | Flexible                 |

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
Internet → Cloudflare (Full Strict) → Node Public IPs → Traefik (hostNetwork) → Gateway API → Apps
                                                                                       │
                                                                         ┌─────────────┘
                                                                         ↓
                                                                     Windmill, ArgoCD

CNI: Cilium    Storage: local-path    SSH/kubectl: Tailscale
```

| App      | Replicas            | Access | Notes              |
| -------- | ------------------- | ------ | ------------------ |
| Windmill | 1 server, 2 workers | Direct | CF Access deferred |
| ArgoCD   | 1 (single replica)  | Direct | CF Access deferred |
| Zot      | deferred            | —      | Phase 1            |

### gxy-static

```
Internet → Cloudflare (Flexible) → Node Public IPs → Traefik (hostNetwork) → Gateway API → Caddy
                                                                                              │
                                                                              ┌───────────────┘
                                                                              ↓
                                                                    Local SSD ← rclone ← R2

CNI: Cilium    Storage: emptyDir    SSH/kubectl: Tailscale
```

| App   | Replicas | Domain        | Notes                                |
| ----- | -------- | ------------- | ------------------------------------ |
| Caddy | 3        | freecode.camp | R2 bucket gxy-static-1, apex→fcc.org |

---

## Playbooks Reference

| Playbook                | Purpose                                               |
| ----------------------- | ----------------------------------------------------- |
| play-k3s--cluster.yml   | Deploy k3s HA cluster                                 |
| play-k3s--longhorn.yml  | Install Longhorn storage                              |
| play-k3s--bootstrap.yml | Deploy any Universe galaxy (K3s + Cilium + Tailscale) |
