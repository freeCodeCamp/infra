# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose                 | Apps                              | Guide                                                  |
| -------------------- | ----------------------- | --------------------------------- | ------------------------------------------------------ |
| ops-backoffice-tools | Internal tools (legacy) | Appsmith, Outline                 | [`ops-backoffice-tools.md`](./ops-backoffice-tools.md) |
| ops-o11y             | Observability           | Grafana, VictoriaMetrics, Argo CD | [runbook 14](../runbooks/14-o11y-node-bringup.md)      |

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
│   ├── apps/                         # Argo CD reads apps/*/application.yaml
│   ├── argocd/                       # root app-of-apps
│   ├── cluster/
│   ├── flux-system/                  # target state, not deployed (runbook 14)
│   ├── ops/                          # target state, not deployed
│   └── platform/                     # target state, not deployed
└── shared/
    └── traefik-config.yaml
```

Retired Universe chart trees (zot, woodpecker, the Universe Argo CD) are tracked in [`retired-stacks.md`](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/docs/infra/architecture/retired-stacks.md).

______________________________________________________________________

## DigitalOcean Resources

### Droplets

| Cluster              | Name Pattern             | Count | Specs              | Tags      |
| -------------------- | ------------------------ | ----- | ------------------ | --------- |
| ops-backoffice-tools | ops-vm-tools-k3s-nyc3-0X | 3     | 4 vCPU, 8GB, 160GB | tools_k3s |
| ops-o11y             | ops-vm-o11y-k3s-fra1-0X  | 1     | 4 vCPU, 8GB, 160GB | ops-o11y  |

### Load Balancer

| Name                  | Target Tag | Ports                             |
| --------------------- | ---------- | --------------------------------- |
| ops-lb-tools-k3s-nyc3 | tools_k3s  | 80→30080, 443→30443 (passthrough) |

______________________________________________________________________

## Ansible Deployment

```bash
# Longhorn storage (ops-backoffice-tools)
cd ansible && ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml -e variable_host=tools_k3s

# k3s servers (ops-o11y)
cd ansible && ansible-playbook -i inventory/digitalocean.yml play-k3s--servers.yml -e variable_host=ops_o11y
```

______________________________________________________________________

## Tailscale Network

Tailscale on nodes for SSH/kubectl access. See [`tailscale.md`](./tailscale.md) for device inventory.

______________________________________________________________________

## Storage

| Class      | Provisioner           | Use For                                 |
| ---------- | --------------------- | --------------------------------------- |
| longhorn   | driver.longhorn.io    | Stateful apps on ops-backoffice-tools   |
| local-path | rancher.io/local-path | Grafana and VictoriaMetrics on ops-o11y |

Longhorn replicas and backups: [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#storage).

______________________________________________________________________

## DNS (Cloudflare)

| Record                    | Type | Value             | SSL Mode      |
| ------------------------- | ---- | ----------------- | ------------- |
| appsmith.freecodecamp.net | A    | tools LB (legacy) | Full (Strict) |
| outline.freecodecamp.net  | A    | tools LB (legacy) | Full (Strict) |

______________________________________________________________________

## Update Apps

On ops-backoffice-tools, use the deployment pattern in [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#deployment-pattern). On ops-o11y, Argo CD syncs the apps from `main`.

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

See [`ansible.md`](./ansible.md#digitalocean-k3s-plays).
