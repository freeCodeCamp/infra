# Flight Manual — gxy-launchbase

Standby galaxy. CNPG operator running, no workload. Reactivation
candidate location for Apollo MVP preview constellations
(spike-plan §"Galaxy placement map"). Woodpecker CI is **retired**
(2026-05-03, no consumer post-D016 pivot) — chart artifacts are
slated for archive in P5 of the universe-master-audit.

| Field             | Value                                                        |
| ----------------- | ------------------------------------------------------------ |
| Role              | Standby (CNPG operator only); future preview constellations  |
| Provider          | DigitalOcean FRA1 (Hetzner pivot post-M5, parked)            |
| Pod CIDR          | `10.6.0.0/16`                                                |
| Service CIDR      | `10.16.0.0/16`                                               |
| Cilium cluster ID | `3`                                                          |
| TLS posture       | n/a (no public ingress at present)                           |
| Last rehearsed    | 2026-05-10 (post universe-master-audit; Phase 16-18 retired) |

> **Read first:** [`UNIVERSE.md`](UNIVERSE.md) §0 prereqs, §1 DNS, §2
> secrets, §3 shared infra. Not repeated here.
>
> **Working-directory rule (HARD):** `cd k3s/gxy-launchbase/` before any
> cluster-touching recipe.
>
> **Idempotency:** every state-changing step has a "skip-if-already-done"
> guard.

This chapter intentionally does NOT cover Woodpecker. The chart at
`k3s/gxy-launchbase/apps/woodpecker/` is dead weight scheduled for
archival; do not bring it up. If a future sprint re-establishes a CI
plane, write a fresh chapter or runbook — do not resurrect the old.

## §A — k3s bootstrap

### A.1 Pre-flight (galaxy-specific files)

`infra-secrets/k3s/gxy-launchbase/` after the woodpecker archive
sweep is **empty** (no chart at this galaxy needs sealed values
today). When CNPG-managed Postgres clusters land for preview
constellations, secrets follow the per-app pattern from gxy-management.

`infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` — CF Origin
wildcard reused if any future ingress lands on this galaxy on the
`freecodecamp.net` zone.

```bash
cd ~/DEV/fCC/infra
just secret-verify-all
```

### A.2 DigitalOcean infrastructure

3× `s-4vcpu-8gb-amd` in FRA1, named `gxy-vm-launchbase-k3s-{1,2,3}`,
tag `gxy-launchbase-k3s`, image Ubuntu 24.04, VPC `universe-vpc-fra1`.
Cloud Firewall: add tag `gxy-launchbase-k3s` to existing
`gxy-fw-fra1`.

Idempotency:

```bash
test "$(doctl compute droplet list --tag-name gxy-launchbase-k3s --format ID --no-header | wc -l)" -eq 3 \
  && echo "✓ 3 launchbase droplets present" \
  || echo "↻ provision via DO dashboard"
```

### A.3 Tailscale + cluster bootstrap

```bash
cd ~/DEV/fCC/infra
just play tailscale--0-install gxy_launchbase_k3s
just play tailscale--1b-up-with-ssh gxy_launchbase_k3s

cd k3s/gxy-launchbase
just play k3s--bootstrap gxy_launchbase_k3s
```

Per-galaxy config in
`ansible/inventory/group_vars/gxy_launchbase_k3s.yml` (CIDRs above,
`cilium_cluster_id: 3`). etcd snapshots land in
`s3://net-freecodecamp-universe-backups/etcd/gxy-launchbase/` every
6h, 20 retained.

### A.4 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-launchbase
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get nodes -o wide
# All 3 Ready, InternalIP = VPC IPs (10.110.0.x)

kubectl get pods -n kube-system
# All Running, no CrashLoopBackOff
```

## §B — CloudNativePG operator

### B.1 Install

```bash
cd ~/DEV/fCC/infra

helm get values -n cnpg-system cnpg-system >/dev/null 2>&1 \
  && echo "✓ cnpg-system release present" \
  || just helm-upgrade gxy-launchbase cnpg-system
```

Chart at `k3s/gxy-launchbase/apps/cnpg-system/charts/`. Cluster-scoped:
installs CRDs (`Cluster`, `ScheduledBackup`, `Pooler`, `Backup`, etc.)
and the controller in namespace `cnpg-system`.

### B.2 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-launchbase
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get pods -n cnpg-system
# cnpg-controller-manager Running

just crds-grep gxy-launchbase cnpg
# postgresql.cnpg.io CRDs present (Cluster, ScheduledBackup, etc.)
```

No `Cluster` CR exists today — the operator runs idle, waiting for
its first workload (preview constellation Postgres when Apollo MVP
expands; or migrated Windmill PG if CNPG-on-management lands first).

## §C — Standby state (what's intentionally not here)

| Component                            | Status                                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------------------ |
| Woodpecker CI server + agents        | **RETIRED 2026-05-03**. Chart at `apps/woodpecker/` slated for archive. **Do not deploy.** |
| `woodpecker-postgres` CNPG `Cluster` | retired with woodpecker; no `Cluster` CR in tree                                           |
| Public DNS                           | none active. `woodpecker.freecodecamp.net` deletion queued (operator-side ClickOps).       |
| TLS secrets                          | no per-app sealed values envelope at this level (post-woodpecker)                          |
| Future workloads                     | Apollo MVP preview constellations (per spike-plan §Phase 0); not scheduled                 |

If a future sprint reactivates a CI plane, the new design must be
captured in a fresh ADR or runbook and a new chapter section here —
do not paste the retired Phase 16-18 back in.

## §D — Smoke

Standby galaxy smoke is minimal:

```bash
cd ~/DEV/fCC/infra/k3s/gxy-launchbase
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

# Cluster up
kubectl get nodes -o wide

# Operator healthy
kubectl get pods -n cnpg-system

# CRDs registered (workload-ready)
kubectl get crd | grep -i cnpg.io
```

Acceptance: nodes Ready, operator pod Running, 7+ CNPG CRDs present.

## §E — Teardown

Destructive. Not blocking on workload state today (no `Cluster` CR
in tree).

### Cluster only (preserves VMs)

```bash
cd ~/DEV/fCC/infra
just play k3s--teardown gxy_launchbase_k3s
```

### Full teardown (VMs too)

```bash
cd ~/DEV/fCC/infra
just play k3s--teardown gxy_launchbase_k3s
doctl compute droplet delete \
  gxy-vm-launchbase-k3s-1 gxy-vm-launchbase-k3s-2 gxy-vm-launchbase-k3s-3 \
  --force
```

VPC, firewall, DO Spaces, R2 buckets persist (shared infra — see
`UNIVERSE.md §3`). When woodpecker DNS deletion lands, no further DNS
hygiene is owed by this chapter.
