# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose                 | Apps                                               |
| -------------------- | ----------------------- | -------------------------------------------------- |
| ops-backoffice-tools | Internal tools (legacy) | Appsmith, Outline                                  |
| gxy-management       | Universe control plane  | Windmill, artemis (uploads.freecode.camp), valkey  |
| gxy-launchbase       | Standby (post-cutover)  | CNPG operator only (woodpecker retired 2026-05-03) |
| gxy-cassiopeia       | Static-serve plane      | Caddy-S3 fronting `*.freecode.camp` from R2        |

## Quick Access

```bash
# Tools cluster
cd k3s/ops-backoffice-tools && export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Galaxy management cluster
cd k3s/gxy-management && export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Galaxy cassiopeia cluster
cd k3s/gxy-cassiopeia && export KUBECONFIG=$(pwd)/.kubeconfig.yaml
```

## Structure

```
k3s/
├── gxy-management/
│   ├── apps/
│   │   ├── artemis/
│   │   ├── valkey/
│   │   └── windmill/
│   └── cluster/
│       ├── cilium/
│       └── security/
├── gxy-launchbase/
│   ├── apps/
│   │   └── cnpg-system/
│   └── cluster/
│       ├── cilium/
│       └── security/
├── gxy-cassiopeia/
│   ├── apps/
│   │   └── caddy/
│   └── cluster/
│       ├── cilium/
│       └── security/
├── ops-backoffice-tools/             # legacy
│   ├── apps/
│   │   ├── appsmith/
│   │   └── outline/
│   └── cluster/
│       ├── longhorn/
│       └── tailscale/
└── shared/
    └── traefik-config.yaml
```

Retired chart trees (argocd, zot, woodpecker) tracked in [`../architecture/retired-stacks.md`](../architecture/retired-stacks.md).

______________________________________________________________________

## DigitalOcean Resources

### VPC

| Property | Value             |
| -------- | ----------------- |
| Name     | universe-vpc-fra1 |
| Region   | fra1              |
| IP Range | 10.110.0.0/20     |

### Droplets

| Cluster        | Name Pattern                  | Count | Specs               | Tags               |
| -------------- | ----------------------------- | ----- | ------------------- | ------------------ |
| tools          | ops-vm-tools-k3s-nyc3-0X      | 3     | 4 vCPU, 8GB, 160GB  | tools_k3s          |
| gxy-management | gxy-vm-management-k3s-{1,2,3} | 3     | 8 vCPU, 16GB, 320GB | gxy-management-k3s |
| gxy-launchbase | gxy-vm-launchbase-k3s-{1,2,3} | 3     | 4 vCPU, 8GB, 160GB  | gxy-launchbase-k3s |
| gxy-cassiopeia | gxy-vm-cassiopeia-k3s-{1,2,3} | 3     | 4 vCPU, 8GB, 160GB  | gxy-cassiopeia-k3s |

### Load Balancer

| Name                  | Target Tag | Ports                             |
| --------------------- | ---------- | --------------------------------- |
| ops-lb-tools-k3s-nyc3 | tools_k3s  | 80→30080, 443→30443 (passthrough) |

______________________________________________________________________

## Ansible Deployment

```bash
# Deploy tools cluster
just bootstrap k3s--cluster tools_k3s

# Longhorn storage (tools)
just bootstrap k3s--longhorn tools_k3s

# Deploy any Universe galaxy (k3s + Cilium + Tailscale)
just bootstrap k3s--bootstrap gxy_management_k3s
just bootstrap k3s--bootstrap gxy_launchbase_k3s
just bootstrap k3s--bootstrap gxy_cassiopeia_k3s
```

______________________________________________________________________

## Tailscale Network

Tailscale on nodes for SSH/kubectl access only (under review).

See `tailscale/README.md` (repo root) for device inventory.

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

| Record                    | Type | Value                   | SSL Mode      |
| ------------------------- | ---- | ----------------------- | ------------- |
| appsmith.freecodecamp.net | A    | tools LB (legacy)       | Full (Strict) |
| outline.freecodecamp.net  | A    | tools LB (legacy)       | Full (Strict) |
| windmill.freecodecamp.net | A    | gxy-management node IPs | Full (Strict) |
| freecode.camp             | A    | gxy-cassiopeia node IPs | Flexible      |
| \*.freecode.camp          | A    | gxy-cassiopeia node IPs | Flexible      |
| uploads.freecode.camp     | A    | gxy-management node IPs | Flexible      |

______________________________________________________________________

## Maintenance

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### Update Apps

```bash
just release <cluster> <app>
```

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

### gxy-management

```
Internet → Cloudflare (Full Strict) → Node Public IPs → Traefik (hostNetwork) → Gateway API → Apps
                                                                                       │
                                                                         ┌─────────────┴─────────────┐
                                                                         ↓                           ↓
                                                                     Windmill                    artemis
                                                                                                     │
                                                                                                  Valkey (in-cluster registry)
                                                                                                     │
                                                                                                  R2 (universe-static-apps-01)

CNI: Cilium    Storage: local-path
```

| App      | Access                                      | Notes                                          |
| -------- | ------------------------------------------- | ---------------------------------------------- |
| Windmill | `windmill.freecodecamp.net` (staff)         | server + workers; CF Access deferred           |
| artemis  | `uploads.freecode.camp` (staff via GH team) | Deploy-proxy; Valkey-backed sites registry     |
| Valkey   | in-cluster only (`valkey.valkey.svc`)       | Single-replica; AOF; backs artemis sites + JWT |

### gxy-cassiopeia

```
Internet → Cloudflare (Flexible) → Node Public IPs → Traefik (hostNetwork) → Gateway API → Caddy
                                                                                              │
                                                                                              ↓
                                                                                R2 (caddy-s3 in-tree)

CNI: Cilium    Storage: emptyDir    SSH/kubectl: Tailscale
```

| App   | Replicas | Domain        | Notes                                                  |
| ----- | -------- | ------------- | ------------------------------------------------------ |
| Caddy | 3        | freecode.camp | R2 bucket `universe-static-apps-01`, alias-pinned read |

______________________________________________________________________

## Playbooks Reference

| Playbook                | Purpose                                               |
| ----------------------- | ----------------------------------------------------- |
| play-k3s--cluster.yml   | Deploy k3s HA cluster                                 |
| play-k3s--longhorn.yml  | Install Longhorn storage                              |
| play-k3s--bootstrap.yml | Deploy any Universe galaxy (K3s + Cilium + Tailscale) |

## Cross-refs

- [`cilium-multi-nic.md`](./cilium-multi-nic.md) — MTU + device pinning on multi-NIC nodes (every Universe galaxy ships eth0/eth1/tailscale0).
- [`cilium-cnp.md`](./cilium-cnp.md) — CiliumNetworkPolicy patterns and the DNS L7 trap.
- [`traefik-hostnetwork.md`](./traefik-hostnetwork.md) — Traefik DaemonSet pitfalls (updateStrategy, runAsUser:0, Gateway port match, CRDs bundled).
- [`chart-pre-merge-checklist.md`](./chart-pre-merge-checklist.md) — five-point gate every new chart clears before merge.
