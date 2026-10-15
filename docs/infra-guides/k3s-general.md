# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose                                              | Apps                              |
| -------------------- | ---------------------------------------------------- | --------------------------------- |
| ops-backoffice-tools | Internal tools (legacy)                              | Appsmith, Outline                 |
| ops-o11y             | Observability, seed of the bare-metal `mgmt` cluster | Grafana, VictoriaMetrics, Argo CD |

## Quick Access

```bash
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl get nodes
KUBECONFIG=k3s/ops-o11y/.kubeconfig.yaml kubectl get nodes
```

## Structure

```
k3s/
├── ops-backoffice-tools/             # legacy
│   ├── apps/
│   │   ├── appsmith/
│   │   └── outline/
│   └── cluster/
│       ├── charts/
│       ├── longhorn/
│       └── tailscale/
├── ops-o11y/
│   ├── apps/
│   ├── argocd/
│   ├── cluster/
│   ├── flux-system/
│   ├── ops/
│   └── platform/
└── shared/
    └── traefik-config.yaml
```

Retired chart trees (argocd, zot, woodpecker) tracked in [`../architecture/retired-stacks.md`](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/docs/infra/architecture/retired-stacks.md).

______________________________________________________________________

## DigitalOcean Resources

### Droplets

| Cluster | Name Pattern             | Count | Specs              | Tags      |
| ------- | ------------------------ | ----- | ------------------ | --------- |
| tools   | ops-vm-tools-k3s-nyc3-0X | 3     | 4 vCPU, 8GB, 160GB | tools_k3s |

### Load Balancer

| Name                  | Target Tag | Ports                             |
| --------------------- | ---------- | --------------------------------- |
| ops-lb-tools-k3s-nyc3 | tools_k3s  | 80→30080, 443→30443 (passthrough) |

______________________________________________________________________

## Ansible Deployment

```bash
# Longhorn storage (tools)
cd ansible && ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml -e variable_host=tools_k3s

# Deploy a new cluster (k3s + Cilium + Tailscale)
cd ansible && ansible-playbook -i inventory/digitalocean.yml play-k3s--bootstrap.yml -e variable_host=<group>
```

______________________________________________________________________

## Tailscale Network

Tailscale on nodes for SSH/kubectl access only (under review).

See [`tailscale.md`](./tailscale.md) for device inventory.

______________________________________________________________________

## Storage

| Class    | Provisioner        | Replicas | Use For                       |
| -------- | ------------------ | -------- | ----------------------------- |
| longhorn | driver.longhorn.io | 2        | Stateful apps (tools cluster) |

### Longhorn Backups

- Target: `s3://net.freecodecamp.ops-k3s-backups@nyc3/`
- Schedule: Daily 2 AM UTC
- Retention: 7 days

______________________________________________________________________

## DNS (Cloudflare)

| Record                    | Type | Value             | SSL Mode      |
| ------------------------- | ---- | ----------------- | ------------- |
| appsmith.freecodecamp.net | A    | tools LB (legacy) | Full (Strict) |
| outline.freecodecamp.net  | A    | tools LB (legacy) | Full (Strict) |

______________________________________________________________________

## Maintenance

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### Update Apps

On ops-backoffice-tools, use the deployment pattern in [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#deployment-pattern). On ops-o11y, Flux deploys the apps (runbook 14).

______________________________________________________________________

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

______________________________________________________________________

## Playbooks Reference

| Playbook                | Purpose                                         |
| ----------------------- | ----------------------------------------------- |
| play-k3s--longhorn.yml  | Install Longhorn storage                        |
| play-k3s--bootstrap.yml | Deploy a k3s cluster (K3s + Cilium + Tailscale) |

## Cross-refs

- [`cilium-multi-nic.md`](./archive/2026-10-14/cilium-multi-nic.md) — MTU + device pinning on multi-NIC nodes (every Universe galaxy ships eth0/eth1/tailscale0).
- [`cilium-cnp.md`](./archive/2026-10-14/cilium-cnp.md) — CiliumNetworkPolicy patterns and the DNS L7 trap.
- [`traefik-hostnetwork.md`](./archive/2026-10-14/traefik-hostnetwork.md) — Traefik DaemonSet pitfalls (updateStrategy, runAsUser:0, Gateway port match, CRDs bundled).
- [`chart-pre-merge-checklist.md`](./chart-pre-merge-checklist.md) — five-point gate every new chart clears before merge.
