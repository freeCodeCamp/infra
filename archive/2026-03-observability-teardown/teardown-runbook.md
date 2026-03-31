# Observability Stack Teardown Runbook

Teardown of the self-hosted observability stack (ClickHouse, Grafana, Prometheus) and Vector log shipping as part of the Universe platform re-alignment.

**Date:** 2026-03-31
**Reason:** Simplifying internal tooling footprint. ClickHouse will be redeployed later as a general-purpose datalake. Grafana and Prometheus will return as part of Universe observability strategy.

---

## Prerequisites

- SSH access to oldeworld proxy nodes via Tailscale
- kubectl access to both k3s clusters (kubeconfigs in repo)
- DigitalOcean console/API access
- Tailscale admin console access

---

## Phase 1: Stop Vector Log Shipping (oldeworld)

Vector runs on oldeworld proxy nodes shipping NGINX access logs to ClickHouse. Must be stopped before ClickHouse teardown.

### 1.1 Stop and uninstall Vector on staging proxy

```bash
cd ansible

# Stop, disable, and remove Vector
uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.systemd -a "name=vector state=stopped enabled=false" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.apt -a "name=vector state=absent purge=true" --become

# Clean up config and data
uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.file -a "path=/etc/vector state=absent" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.file -a "path=/var/lib/vector state=absent" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.file -a "path=/etc/systemd/system/vector.service.d state=absent" --become
```

### 1.2 Stop and uninstall Vector on production proxy

```bash
# Same commands with prd target
uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.systemd -a "name=vector state=stopped enabled=false" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.apt -a "name=vector state=absent purge=true" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.file -a "path=/etc/vector state=absent" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.file -a "path=/var/lib/vector state=absent" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.file -a "path=/etc/systemd/system/vector.service.d state=absent" --become
```

### 1.3 Clean up APT repository

```bash
# Remove Vector apt repo from both stg and prd
uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.apt_repository -a "repo='deb [signed-by=/usr/share/keyrings/datadog-archive-keyring.gpg] https://apt.vector.dev/ stable vector-0' state=absent filename=vector" --become

uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.apt_repository -a "repo='deb [signed-by=/usr/share/keyrings/datadog-archive-keyring.gpg] https://apt.vector.dev/ stable vector-0' state=absent filename=vector" --become
```

### 1.4 Verify Vector is gone

```bash
uv run ansible-playbook -i inventory/linode.yml -e variable_host=stg_oldeworld_pxy \
  -m ansible.builtin.command -a "systemctl status vector" --become
# Expected: "Unit vector.service could not be found"

uv run ansible-playbook -i inventory/linode.yml -e variable_host=prd_oldeworld_pxy \
  -m ansible.builtin.command -a "systemctl status vector" --become
# Expected: "Unit vector.service could not be found"
```

---

## Phase 2: Teardown ops-logs-clickhouse Cluster

### 2.1 Delete ClickHouse resources

```bash
cd k3s/ops-logs-clickhouse
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Delete ClickHouse resources via kustomize
kubectl delete -k apps/clickhouse/manifests/base/

# Verify namespace is terminating/gone
kubectl get namespaces
# clickhouse namespace should be gone or Terminating
```

### 2.2 Uninstall Tailscale operator

```bash
# Remove Tailscale operator Helm release
helm list -n tailscale
helm uninstall tailscale-operator -n tailscale
kubectl delete namespace tailscale
```

### 2.3 Uninstall Traefik

```bash
# Traefik is installed by k3s but configured via HelmChartConfig
# It will be destroyed with the cluster nodes
```

### 2.4 Remove Tailscale devices from tailnet

Go to https://login.tailscale.com/admin/machines and remove:

- `ops-k3s-clickhouse-operator`
- `ops-k3s-clickhouse-logs`

### 2.5 Destroy DigitalOcean resources

Via DigitalOcean console (https://cloud.digitalocean.com) or `doctl`:

```bash
# Detach and destroy volumes
doctl compute volume-action detach ops-vol-logs-k3s-nyc3-01
doctl compute volume-action detach ops-vol-logs-k3s-nyc3-02
doctl compute volume-action detach ops-vol-logs-k3s-nyc3-03
doctl compute volume delete ops-vol-logs-k3s-nyc3-01 --force
doctl compute volume delete ops-vol-logs-k3s-nyc3-02 --force
doctl compute volume delete ops-vol-logs-k3s-nyc3-03 --force

# Destroy droplets
doctl compute droplet delete ops-vm-logs-k3s-nyc3-01 --force
doctl compute droplet delete ops-vm-logs-k3s-nyc3-02 --force
doctl compute droplet delete ops-vm-logs-k3s-nyc3-03 --force
```

**DO NOT delete the VPC** (`ops-vpc-k3s-nyc3`) — it is shared with the tools cluster.

### 2.6 Verify logs cluster is fully destroyed

```bash
# Confirm droplets gone
doctl compute droplet list --tag-name logs_k3s
# Expected: empty

# Confirm volumes gone
doctl compute volume list | grep logs-k3s
# Expected: empty

# Confirm Tailscale devices removed (check admin console)
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

# Delete remaining resources (gateway, httproutes, secrets)
kubectl delete -k apps/grafana/manifests/base/

# Delete namespace (catches any remaining resources)
kubectl delete namespace grafana
```

### 3.2 Delete Prometheus stack

```bash
# Uninstall kube-prometheus-stack Helm release
helm list -n prometheus
helm uninstall prometheus -n prometheus

# Delete remaining resources (longhorn servicemonitor, tailscale ingress)
kubectl delete -k apps/prometheus/manifests/base/

# Delete namespace
kubectl delete namespace prometheus

# Note: CRDs from kube-prometheus-stack may linger. Clean up:
kubectl get crd | grep monitoring.coreos.com
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com \
  alertmanagers.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  probes.monitoring.coreos.com \
  prometheusagents.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  scrapeconfigs.monitoring.coreos.com \
  servicemonitors.monitoring.coreos.com \
  thanosrulers.monitoring.coreos.com
```

### 3.3 Remove Tailscale device

Go to https://login.tailscale.com/admin/machines and remove:

- `ops-k3s-backoffice-prometheus`

### 3.4 Remove Cloudflare DNS record

Remove the A record for `grafana.freecodecamp.net` from Cloudflare DNS.

The n8n and other records remain.

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

# Confirm Longhorn volumes reclaimed (check Longhorn UI)
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Visit localhost:8080, check no orphaned volumes
```

---

## Phase 4: Verification Checklist

- [ ] Vector stopped and uninstalled on stg proxy nodes
- [ ] Vector stopped and uninstalled on prd proxy nodes
- [ ] ClickHouse namespace deleted from logs cluster
- [ ] Tailscale operator removed from logs cluster
- [ ] Tailscale devices removed: `ops-k3s-clickhouse-operator`, `ops-k3s-clickhouse-logs`
- [ ] DO volumes detached and destroyed (3x 100GB)
- [ ] DO droplets destroyed (3x ops-vm-logs-k3s-nyc3-0X)
- [ ] VPC `ops-vpc-k3s-nyc3` still exists (shared with tools cluster)
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
| 3x DO volumes (100GB each)       | ~$30/mo      | Destroyed |
| Grafana PVC (5Gi Longhorn)       | included     | Released  |
| Prometheus PVC (50Gi Longhorn)   | included     | Released  |
| Alertmanager PVC (10Gi Longhorn) | included     | Released  |
| **Total savings**                | **~$174/mo** |           |

---

## Rollback

If any service needs to be restored before the Universe observability stack is ready:

1. Archived configs are in `archive/2026-03-observability-teardown/`
2. ClickHouse would need new DO droplets + volume provisioning + k3s install + manifest apply
3. Grafana/Prometheus can be redeployed to the tools cluster from archived Helm values
4. Vector can be redeployed via the archived playbook

This is NOT a quick rollback — plan for 2-4 hours to restore any component.
