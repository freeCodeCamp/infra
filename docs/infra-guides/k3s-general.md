# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose                 | Apps              | Guide                                                  |
| -------------------- | ----------------------- | ----------------- | ------------------------------------------------------ |
| ops-backoffice-tools | Internal tools (legacy) | Appsmith, Outline | [`ops-backoffice-tools.md`](./ops-backoffice-tools.md) |

The `ops-o11y` cluster was retired in November 2026. Its replacement, `ops-o11y-vultr`, runs on Vultr ([runbook 19](../runbooks/19-o11y-alerts.md)).

## Quick Access

```bash
KUBECONFIG=k3s/ops-backoffice-tools/.kubeconfig.yaml kubectl get nodes
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
└── shared/
    └── traefik-config.yaml
```

Retired Universe chart trees (zot, woodpecker, the Universe Argo CD) are tracked in [`retired-stacks.md`](https://github.com/freeCodeCamp-Universe/Architecture/blob/main/docs/infra/architecture/retired-stacks.md).

---

## DigitalOcean Resources

### Droplets

| Cluster              | Name Pattern             | Count | Specs              | Tags      |
| -------------------- | ------------------------ | ----- | ------------------ | --------- |
| ops-backoffice-tools | ops-vm-tools-k3s-nyc3-0X | 3     | 4 vCPU, 8GB, 160GB | tools_k3s |

### Load Balancer

| Name                  | Target Tag | Ports                             |
| --------------------- | ---------- | --------------------------------- |
| ops-lb-tools-k3s-nyc3 | tools_k3s  | 80→30080, 443→30443 (passthrough) |

---

## Ansible Deployment

```bash
# Longhorn storage (ops-backoffice-tools)
cd ansible && ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml -e variable_host=tools_k3s
```

---

## Tailscale Network

Tailscale on nodes for SSH/kubectl access. See [`tailscale.md`](./tailscale.md) for device inventory.

---

## Storage

| Class    | Provisioner        | Use For                               |
| -------- | ------------------ | ------------------------------------- |
| longhorn | driver.longhorn.io | Stateful apps on ops-backoffice-tools |

Longhorn replicas and backups: [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#storage).

---

## DNS (Cloudflare)

| Record                | Type | Value             | SSL Mode      |
| --------------------- | ---- | ----------------- | ------------- |
| `<appsmith-hostname>` | A    | tools LB (legacy) | Full (Strict) |
| `<outline-hostname>`  | A    | tools LB (legacy) | Full (Strict) |

The hostnames are in the Cloudflare DNS dashboard. This guide does not list them.

---

## Update Apps

On ops-backoffice-tools, use the deployment pattern in [`ops-backoffice-tools.md`](./ops-backoffice-tools.md#deployment-pattern).

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

---

## Playbooks Reference

See [`ansible.md`](./ansible.md#digitalocean-k3s-plays).
