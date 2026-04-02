# Observability Stack Teardown Runbook

Teardown of the self-hosted observability stack (ClickHouse, Grafana, Prometheus) and Vector log shipping as part of the Universe platform re-alignment.

**Date:** 2026-03-31
**Reason:** Simplifying internal tooling footprint. ClickHouse will be redeployed later as a general-purpose datalake. Grafana and Prometheus will return as part of Universe observability strategy.

---

## Prerequisites

- SSH access to oldeworld proxy nodes via Tailscale
- DigitalOcean console/API access (`doctl`)
- Tailscale admin console access
- Cloudflare DNS access

---

## Phase 1: Stop Vector Log Shipping (oldeworld)

Vector runs on oldeworld proxy nodes shipping NGINX access logs to ClickHouse. Must be stopped before ClickHouse teardown.

> **Note:** Ad-hoc ansible commands use `ansible` (not `ansible-playbook`).
> The host group is a positional argument, not passed via `-e variable_host`.

### 1.1 Stop and disable Vector on staging proxy — DONE

```bash
cd ansible
uv run ansible stg_oldeworld_pxy -i inventory/linode.yml \
  -m ansible.builtin.systemd -a "name=vector state=stopped enabled=false" --become
```

### 1.2 Stop and disable Vector on production proxy — DONE

```bash
uv run ansible prd_oldeworld_pxy -i inventory/linode.yml \
  -m ansible.builtin.systemd -a "name=vector state=stopped enabled=false" --become
```

### 1.3 Verify Vector is stopped — DONE

```bash
uv run ansible "stg_oldeworld_pxy:prd_oldeworld_pxy" -i inventory/linode.yml \
  -m ansible.builtin.command -a "systemctl is-active vector" --become
# Expected: all hosts return "inactive" (rc=3 is normal)
```

### 1.4 Purge Vector package and clean up (optional, can be done later)

```bash
# Remove package
uv run ansible "stg_oldeworld_pxy:prd_oldeworld_pxy" -i inventory/linode.yml \
  -m ansible.builtin.apt -a "name=vector state=absent purge=true" --become

# Remove config, data, and systemd override
uv run ansible "stg_oldeworld_pxy:prd_oldeworld_pxy" -i inventory/linode.yml \
  -m ansible.builtin.file -a "path=/etc/vector state=absent" --become

uv run ansible "stg_oldeworld_pxy:prd_oldeworld_pxy" -i inventory/linode.yml \
  -m ansible.builtin.file -a "path=/var/lib/vector state=absent" --become

uv run ansible "stg_oldeworld_pxy:prd_oldeworld_pxy" -i inventory/linode.yml \
  -m ansible.builtin.file -a "path=/etc/systemd/system/vector.service.d state=absent" --become

# Remove APT repository
uv run ansible "stg_oldeworld_pxy:prd_oldeworld_pxy" -i inventory/linode.yml \
  -m ansible.builtin.apt_repository \
  -a "repo='deb [signed-by=/usr/share/keyrings/datadog-archive-keyring.gpg] https://apt.vector.dev/ stable vector-0' state=absent filename=vector" --become
```

---

## Phase 2: Teardown ops-logs-clickhouse Cluster — DONE

The logs cluster kubeconfig was lost during repo cleanup, so kubectl teardown was skipped. Resources were destroyed directly via DigitalOcean.

### 2.1 Destroy DigitalOcean resources — DONE

Destroyed via DO console/API:

| Resource      | Name                                      | Size          |
| ------------- | ----------------------------------------- | ------------- |
| Load balancer | `ops-lb-logs-k3s-nyc3` (tag: `logs-k3s`)  | -             |
| Volume        | `ops-vol-logs-k3s-nyc3-01`                | 250 GiB       |
| Volume        | `ops-vol-logs-k3s-nyc3-02`                | 250 GiB       |
| Volume        | `ops-vol-logs-k3s-nyc3-03`                | 250 GiB       |
| Droplet       | `ops-vm-logs-k3s-nyc3-01` (ID: 539109026) | 4 vCPU / 8 GB |
| Droplet       | `ops-vm-logs-k3s-nyc3-02` (ID: 539109028) | 4 vCPU / 8 GB |
| Droplet       | `ops-vm-logs-k3s-nyc3-03` (ID: 539109024) | 4 vCPU / 8 GB |

**VPC `ops-vpc-k3s-nyc3` kept** — shared with tools cluster.

### 2.2 Remove Tailscale devices from tailnet

Go to https://login.tailscale.com/admin/machines and remove:

- `ops-k3s-clickhouse-operator`
- `ops-k3s-clickhouse-logs`

### 2.3 Verify — DONE

```bash
doctl compute droplet list --format ID,Name,Tags,Status | grep -i logs
# Expected: empty

doctl compute volume list --format ID,Name,Size,Region | grep -i logs
# Expected: empty

doctl compute load-balancer list --format ID,Name,Tag,Status | grep -i logs
# Expected: empty
```

---

## Phase 3: Teardown Grafana and Prometheus (ops-backoffice-tools)

### 3.1 Delete Grafana

```bash
cd k3s/ops-backoffice-tools
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Uninstall Grafana Helm release
helm list -n grafana
helm uninstall grafana -n grafana

# Delete namespace (catches all remaining resources)
kubectl delete namespace grafana
```

### 3.2 Delete Prometheus stack

```bash
# Uninstall kube-prometheus-stack Helm release
helm list -n prometheus
helm uninstall prometheus -n prometheus

# Delete namespace
kubectl delete namespace prometheus

# Clean up CRDs from kube-prometheus-stack
kubectl get crd | grep monitoring.coreos.com
kubectl get crd | grep monitoring.coreos.com | awk '{print $1}' | xargs kubectl delete crd
```

### 3.3 Remove Tailscale device

Go to https://login.tailscale.com/admin/machines and remove:

- `ops-k3s-backoffice-prometheus`

### 3.4 Remove Cloudflare DNS record

Remove the A record for `grafana.freecodecamp.net` from Cloudflare DNS.

Other records remain: appsmith, outline, n8n, n8n-wh.

### 3.5 Verify cleanup

```bash
# Confirm namespaces gone
kubectl get namespace grafana prometheus
# Expected: NotFound

# Confirm no monitoring CRDs remain
kubectl get crd | grep monitoring.coreos.com
# Expected: empty

# Confirm PVCs released
kubectl get pvc -A | grep -E "grafana|prometheus"
# Expected: empty

# Confirm Longhorn volumes reclaimed
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Visit localhost:8080, verify no orphaned volumes
```

---

## Phase 4: Verification Checklist

- [x] Vector stopped and disabled on stg proxy nodes (3 hosts)
- [x] Vector stopped and disabled on prd proxy nodes (3 hosts)
- [ ] Vector package purged and configs removed (optional cleanup)
- [x] DO load balancer destroyed: `ops-lb-logs-k3s-nyc3`
- [x] DO volumes destroyed: 3x 250 GiB (`ops-vol-logs-k3s-nyc3-01/02/03`)
- [x] DO droplets destroyed: 3x (`ops-vm-logs-k3s-nyc3-01/02/03`)
- [x] VPC `ops-vpc-k3s-nyc3` still exists (shared with tools cluster)
- [ ] Tailscale devices removed: `ops-k3s-clickhouse-operator`, `ops-k3s-clickhouse-logs`
- [ ] Grafana Helm release uninstalled
- [ ] Grafana namespace deleted
- [ ] Prometheus Helm release uninstalled
- [ ] Prometheus namespace deleted
- [ ] Prometheus CRDs cleaned up
- [ ] Tailscale device removed: `ops-k3s-backoffice-prometheus`
- [ ] Cloudflare DNS: `grafana.freecodecamp.net` removed
- [ ] Longhorn: no orphaned volumes from grafana/prometheus PVCs
- [ ] Remaining apps on tools cluster work: Appsmith, Outline, n8n

---

## Cost Savings

| Resource                         | Monthly Cost | Status    |
| -------------------------------- | ------------ | --------- |
| 3x DO droplets (logs cluster)    | ~$144/mo     | Destroyed |
| 3x DO volumes (250 GiB each)     | ~$75/mo      | Destroyed |
| 1x DO load balancer              | ~$12/mo      | Destroyed |
| Grafana PVC (5Gi Longhorn)       | included     | Pending   |
| Prometheus PVC (50Gi Longhorn)   | included     | Pending   |
| Alertmanager PVC (10Gi Longhorn) | included     | Pending   |
| **Total savings**                | **~$231/mo** |           |

---

## Rollback

If any service needs to be restored before the Universe observability stack is ready:

1. Archived configs are in `archive/2026-03-observability-teardown/`
2. ClickHouse would need new DO droplets + volume provisioning + k3s install + manifest apply
3. Grafana/Prometheus can be redeployed to the tools cluster from archived Helm values
4. Vector can be redeployed via the archived playbook

This is NOT a quick rollback — plan for 2-4 hours to restore any component.
