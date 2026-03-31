# k3s Clusters

Self-hosted k3s clusters on DigitalOcean.

## Clusters

| Cluster              | Purpose        | Apps                   |
| -------------------- | -------------- | ---------------------- |
| ops-backoffice-tools | Internal tools | Appsmith, Outline, n8n |

## Quick Access

```bash
# Tools cluster
cd k3s/ops-backoffice-tools && export KUBECONFIG=$(pwd)/.kubeconfig.yaml
```

## Structure

```
k3s/
├── archive/                       # Archived configs (historical reference)
├── ops-backoffice-tools/
│   ├── apps/
│   │   ├── appsmith/
│   │   ├── n8n/
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

| Cluster | Name Pattern             | Count | Specs              | Tags           |
| ------- | ------------------------ | ----- | ------------------ | -------------- |
| tools   | ops-vm-tools-k3s-nyc3-0X | 3     | 4 vCPU, 8GB, 160GB | k3s, tools_k3s |

### Load Balancer

| Name                  | Target Tag | Ports                             |
| --------------------- | ---------- | --------------------------------- |
| ops-lb-tools-k3s-nyc3 | tools_k3s  | 80→30080, 443→30443 (passthrough) |

---

## Ansible Deployment

```bash
cd ansible

# Deploy cluster
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--cluster.yml \
  -e variable_host=tools_k3s

# Longhorn storage
uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--longhorn.yml \
  -e variable_host=tools_k3s
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

| Record                    | Type | Value    |
| ------------------------- | ---- | -------- |
| appsmith.freecodecamp.net | A    | tools LB |
| outline.freecodecamp.net  | A    | tools LB |
| n8n.freecodecamp.net      | A    | tools LB |
| n8n-wh.freecodecamp.net   | A    | tools LB |

---

## Maintenance

### Longhorn UI

```bash
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### Update Apps

```bash
kubectl apply -k apps/<app>/manifests/base/
```

---

## Architecture

### ops-backoffice-tools

```
Internet → Cloudflare → DO LB → Traefik (NodePort) → Gateway API → Apps
                                                            │
                                              ┌─────────────┼─────────────┐
                                              ↓             ↓             ↓
                                          Appsmith       Outline         n8n
                                              │             │        (queue mode)
                                              └─────────────┴─────────────┘
                                                           │
                                                      Longhorn
                                                   (2 replicas)
```

| App      | Replicas           | Storage     | Database           |
| -------- | ------------------ | ----------- | ------------------ |
| Appsmith | 1                  | 10Gi        | Embedded           |
| Outline  | 1                  | 10Gi + 10Gi | PostgreSQL sidecar |
| n8n      | 1 main + 2 workers | 10Gi + 20Gi | PostgreSQL sidecar |

---

## Playbooks Reference

| Playbook               | Purpose                  |
| ---------------------- | ------------------------ |
| play-k3s--cluster.yml  | Deploy k3s HA cluster    |
| play-k3s--longhorn.yml | Install Longhorn storage |
