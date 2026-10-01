# Flight Manual — gxy-launchbase

Standby galaxy. **Currently decommissioned (2026-07-07) — pending rebuild.** The 3 DO droplets were deleted 2026-07-07 as part of the Windmill-retirement consolidation pass (the cluster was idle: CNPG operator only, zero workload, zero `Cluster` CRs — nothing was orphaned by the teardown). This is **not** a retirement — gxy-launchbase returns on the next Universe buildout. The chapter below is the rebuild manual: replay §A→§B from a clean DO account state to bring it back. Reactivation candidate location for Apollo MVP preview constellations (spike-plan §"Galaxy placement map"). Woodpecker CI is **retired** — do not deploy; full rationale, last-live commit, and resurrection path in [`../architecture/retired-stacks.md`](../architecture/retired-stacks.md) §woodpecker.

| Field             | Value                                                                          |
| ----------------- | ------------------------------------------------------------------------------ |
| Role              | Standby (CNPG operator only); future preview constellations                    |
| Status            | **Decommissioned 2026-07-07, pending rebuild** (droplets deleted; not retired) |
| Provider          | DigitalOcean FRA1 (Hetzner pivot post-M5, parked)                              |
| Pod CIDR          | `10.6.0.0/16`                                                                  |
| Service CIDR      | `10.16.0.0/16`                                                                 |
| Cilium cluster ID | `3`                                                                            |
| TLS posture       | n/a (no public ingress at present)                                             |
| Last rehearsed    | 2026-05-10 (post universe-master-audit; Phase 16-18 retired)                   |

> **Read first:** [`UNIVERSE.md`](UNIVERSE.md) §0 prereqs, §1 DNS, §2 secrets, §3 shared infra. Not repeated here.
>
> **Working-directory rule (post-`cd3b3a32`):** run `just <verb> gxy-launchbase <app>` from repo root; recipes self-export `KUBECONFIG`. `cd k3s/gxy-launchbase/` is only required for raw `kubectl` / `helm` invocations shown explicitly below.
>
> **Idempotency:** every state-changing step has a "skip-if-already-done" guard.

This chapter intentionally does NOT cover Woodpecker (retired; see [`../architecture/retired-stacks.md`](../architecture/retired-stacks.md) §woodpecker). If a future sprint re-establishes a CI plane, write a fresh chapter or runbook — do not resurrect the old.

## §A — k3s bootstrap

### A.1 Pre-flight (galaxy-specific files)

`infra-secrets/k3s/gxy-launchbase/` is **empty** (no chart at this galaxy needs sealed values today; the prior woodpecker envelope retired with the stack — see [`../architecture/retired-stacks.md`](../architecture/retired-stacks.md) §woodpecker). When CNPG-managed Postgres clusters land for preview constellations, secrets follow the per-app pattern from gxy-management.

`infra-secrets/global/tls/freecodecamp-net.{crt,key}.enc` — CF Origin wildcard reused if any future ingress lands on this galaxy on the `freecodecamp.net` zone.

```bash
cd ~/DEV/fCC/infra
just verify-secrets
```

### A.2 DigitalOcean infrastructure

3× `s-4vcpu-8gb-amd` in FRA1, named `gxy-vm-launchbase-k3s-{1,2,3}`, tag `gxy-launchbase-k3s`, image Ubuntu 24.04, VPC `universe-vpc-fra1`. Cloud Firewall: add tag `gxy-launchbase-k3s` to existing `gxy-fw-fra1`.

Idempotency:

```bash
test "$(doctl compute droplet list --tag-name gxy-launchbase-k3s --format ID --no-header | wc -l)" -eq 3 \
  && echo "✓ 3 launchbase droplets present" \
  || echo "↻ provision via DO dashboard"
```

### A.3 Tailscale + cluster bootstrap

```bash
cd ~/DEV/fCC/infra
just bootstrap tailscale--0-install gxy_launchbase_k3s
just bootstrap tailscale--1b-up-with-ssh gxy_launchbase_k3s

cd k3s/gxy-launchbase
just bootstrap k3s--bootstrap gxy_launchbase_k3s
```

Per-galaxy config in `ansible/inventory/group_vars/gxy_launchbase_k3s.yml` (CIDRs above, `cilium_cluster_id: 3`). etcd snapshots land in `s3://net-freecodecamp-universe-backups/etcd/gxy-launchbase/` every 6h, 20 retained.

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
  || just release gxy-launchbase cnpg-system
```

Chart at `k3s/gxy-launchbase/apps/cnpg-system/charts/`. Cluster-scoped: installs CRDs (`Cluster`, `ScheduledBackup`, `Pooler`, `Backup`, etc.) and the controller in namespace `cnpg-system`.

### B.2 Verify

```bash
cd ~/DEV/fCC/infra/k3s/gxy-launchbase
export KUBECONFIG=$(pwd)/.kubeconfig.yaml

kubectl get pods -n cnpg-system
# cnpg-controller-manager Running

just inspect-crds gxy-launchbase cnpg
# postgresql.cnpg.io CRDs present (Cluster, ScheduledBackup, etc.)
```

No `Cluster` CR was present before the 2026-07-07 decommission — the operator ran idle, waiting for its first workload (preview constellation Postgres when Apollo MVP expands). Re-verify this on rebuild; nothing today depends on a migrated-PG scenario, since gxy-management's Windmill (the one hypothetical source) retired 2026-07-07 rather than migrating.

## §C — Standby state (what's intentionally not here)

| Component         | Status                                                                                                                                                                            |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Woodpecker CI     | **RETIRED**. **Do not deploy.** Full park rationale, DNS-deletion state, last-live commit → [`../architecture/retired-stacks.md`](../architecture/retired-stacks.md) §woodpecker. |
| CNPG `Cluster` CR | none in tree (no workload yet; operator idle — see §B)                                                                                                                            |
| Public DNS        | none active                                                                                                                                                                       |
| TLS secrets       | no per-app sealed values envelope at this level                                                                                                                                   |
| Future workloads  | Apollo MVP preview constellations (per spike-plan §Phase 0); not scheduled                                                                                                        |

If a future sprint reactivates a CI plane, the new design must be captured in a fresh ADR or runbook and a new chapter section here — do not paste the retired Phase 16-18 back in.

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

Destructive. Not blocking on workload state today (no `Cluster` CR in tree). Already executed 2026-07-07 (full teardown — cluster + all 3 VMs); kept here as the reference procedure for the next teardown after this galaxy is rebuilt.

### Cluster only (preserves VMs)

```bash
cd ~/DEV/fCC/infra
just bootstrap k3s--teardown gxy_launchbase_k3s
```

### Full teardown (VMs too)

```bash
cd ~/DEV/fCC/infra
just bootstrap k3s--teardown gxy_launchbase_k3s
doctl compute droplet delete \
  gxy-vm-launchbase-k3s-1 gxy-vm-launchbase-k3s-2 gxy-vm-launchbase-k3s-3 \
  --force
```

VPC, firewall, DO Spaces, R2 buckets persist (shared infra — see `UNIVERSE.md §3`). No DNS hygiene is owed by this chapter (the retired woodpecker record is tracked in [`../architecture/retired-stacks.md`](../architecture/retired-stacks.md) §woodpecker).
