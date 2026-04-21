# Sprint 2026-04-21 — Deep Cluster Audit

Research-only inventory of live Universe galaxies. Sources: `doctl compute`
(2026-04-21), repo apps-dirs, HANDOFF.md §Galaxy state. Informs task #22
(rename exec) and task #23 (MASTER sprint plan).

**Scope:** gxy-management, gxy-static, gxy-launchbase, gxy-cassiopeia.
Legacy `ops-*` excluded.

## TL;DR

- 12 k3s droplets across 4 galaxies, all DO FRA1, single-AZ. Monthly
  compute cost: **$720/mo** ($8,640/yr).
- HA: all galaxies 3-node (etcd quorum OK). DR posture weak — single-AZ,
  no cross-region replica, no snapshot automation documented.
- Autoscaling: **none**. All nodes static; scaling = manual ansible
  reprovision. No horizontal pod autoscaler configured (unverified per
  cluster; TODO). No cluster autoscaler available on self-managed k3s.
- Drift: **Zot declared in `k3s/gxy-management/apps/zot/` but not
  deployed** (per HANDOFF helm-list snapshot). Other galaxies in sync.
- Rename partial-state: repo-dir already `gxy-management`, but ansible
  group_vars + DO droplet tags + droplet names still `gxy-mgmt`. Task
  #22 scope unchanged — ansible + DO layer still to flip.
- Firewall: single `gxy-fw-fra1` covers all droplets; 80/443 open to
  `0.0.0.0/0` (Q4 recommended narrowing to CF IPs — pending).
- No Load Balancers, Reserved IPs, Block Volumes, DOKS clusters, or
  custom VPCs — flat setup.

## Cost inventory

Pricing via `doctl compute size list` (2026-04-21).

| Galaxy         | Droplets | Size         | vCPU | RAM  | Disk  | $/droplet | $/galaxy | $/yr       |
| -------------- | -------- | ------------ | ---- | ---- | ----- | --------- | -------- | ---------- |
| gxy-management | 3        | s-8vcpu-16gb | 8    | 16GB | 320GB | $96.00    | $288.00  | $3,456.00  |
| gxy-static     | 3        | s-4vcpu-8gb  | 4    | 8GB  | 160GB | $48.00    | $144.00  | $1,728.00  |
| gxy-launchbase | 3        | s-4vcpu-8gb  | 4    | 8GB  | 160GB | $48.00    | $144.00  | $1,728.00  |
| gxy-cassiopeia | 3        | s-4vcpu-8gb  | 4    | 8GB  | 160GB | $48.00    | $144.00  | $1,728.00  |
| **Total**      | **12**   |              |      |      |       |           | **$720** | **$8,640** |

Size slug inference — `doctl compute droplet list` returned `<nil>` for
Size column; inferred from Memory/VCPUs/Disk against `doctl compute
size list`. Confirm slug via `doctl compute droplet get <id> --format
Size` before any resize.

**Cost line items not billed on droplets:**

- Firewalls, VPCs, DO DNS — free.
- Bandwidth: 4 TB/mo included per droplet; overage $0.01/GiB.
- No snapshots / backups configured (DO snapshot add-on ~$0.06/GiB/mo
  when enabled — currently off).
- R2 bucket `universe-static-apps-01` — Cloudflare line item (not DO);
  $0.015/GB-mo + class-A/B ops.

**Retirement recoveries:**

- `gxy-static` teardown at cutover (#26): −$144/mo / −$1,728/yr.
- Rename `gxy-mgmt` → `gxy-management` via reprovision (#22): **no net
  cost delta** if identical size; transient 2× during overlap.

## HA posture

| Galaxy         | Nodes | etcd quorum | AZ   | Notes                                         |
| -------------- | ----- | ----------- | ---- | --------------------------------------------- |
| gxy-management | 3/3   | OK          | fra1 | All control-plane workload (argocd, windmill) |
| gxy-static     | 3/3   | OK          | fra1 | Legacy; retires at #26                        |
| gxy-launchbase | 3/3   | OK          | fra1 | CNPG + Woodpecker                             |
| gxy-cassiopeia | 3/3   | OK          | fra1 | Caddy static-serve                            |

**Weaknesses:**

- All galaxies single-AZ (FRA1). DO regional outage = full platform
  down. No documented DR runbook (parked per ADR-012).
- No automated etcd-snapshot offload. k3s embedded-etcd snapshots land
  on-node by default; loss of all 3 nodes = data loss.
- No droplet backups enabled (+$28.80/mo/galaxy if enabled at 20%
  upcharge on $144/mo tier).
- `gxy-launchbase` hosts CNPG but no barman-cloud plugin yet (parked
  per HANDOFF). Any Postgres today = no PITR.

**HA gate for MVP:** acceptable. Cassiopeia serves static files from R2
(authoritative store); nodes = cache + router. Loss of all 3 cassiopeia
nodes ≠ data loss, only downtime until reprovision.

## Autoscaling gaps

| Layer           | State                   | Gap                                                                        |
| --------------- | ----------------------- | -------------------------------------------------------------------------- |
| Cluster nodes   | Static, 3/galaxy        | No cluster-autoscaler (unavailable on droplet k3s). Scale = manual ansible |
| Horizontal pods | Unverified              | HPA not audited per cluster; assume none unless helm values set it         |
| Vertical pods   | None                    | No VPA deployed                                                            |
| Bandwidth       | Included 4TB/mo/droplet | 12 TB/galaxy; plenty for MVP static traffic                                |

**Decision surface:**

- Static-apps MVP traffic fits comfortably in 3× s-4vcpu-8gb on
  cassiopeia (per ADR-007 sizing). Autoscaling not a blocker for MVP.
- Post-MVP dynamic hosting (gxy-triangulum) will need HPA + CNPG
  scaling — parked.

## Apps-dir vs deployed drift

Source of truth: `k3s/<galaxy>/apps/` vs HANDOFF helm-list snapshot
(2026-04-21).

| Galaxy         | Apps declared             | Helm releases (app ver)                       | Drift                        |
| -------------- | ------------------------- | --------------------------------------------- | ---------------------------- |
| gxy-management | argocd, windmill, **zot** | argocd (v3.3.6), windmill (1.686.0)           | **Zot missing** — deploy gap |
| gxy-static     | caddy                     | caddy (2.9)                                   | None                         |
| gxy-launchbase | cnpg-system, woodpecker   | cnpg-system (1.29.0), woodpecker (3.13.0)     | None                         |
| gxy-cassiopeia | caddy                     | caddy (0.1.0, in-tree r2_alias + caddy.fs.r2) | None                         |

**Zot gap:** `k3s/gxy-management/apps/zot/` present but no helm release.
Per HANDOFF: acceptable for static-apps MVP (no image ship); blocks
gxy-triangulum rollout (supply-chain chain requires zot + cosign +
Grype/Trivy + Kyverno verifyImages + SBOM — all parked).

Supply-chain apps directory — none exist yet anywhere. Full chain lands
with triangulum M5.

## Network + firewall surface

**Single DO firewall `gxy-fw-fra1`** attached to all 12 droplets.
Rules:

| Proto | Port       | Source          | Purpose                                                 |
| ----- | ---------- | --------------- | ------------------------------------------------------- |
| TCP   | 22         | `0.0.0.0/0`     | SSH (note: per ADR-011 should be Tailscale-only)        |
| TCP   | 80, 443    | `0.0.0.0/0`     | HTTP/HTTPS — **Q4 wants CF IP narrowing on cassiopeia** |
| TCP   | 2379-2380  | `10.110.0.0/20` | etcd peer (VPC-internal)                                |
| TCP   | 4240, 4244 | `10.110.0.0/20` | Cilium health + hubble                                  |
| TCP   | 5001       | `10.110.0.0/20` | (likely registry or probe)                              |
| TCP   | 6443       | `10.110.0.0/20` | k3s API                                                 |
| TCP   | 10250      | `10.110.0.0/20` | kubelet                                                 |
| UDP   | 8472       | `10.110.0.0/20` | VXLAN overlay                                           |
| UDP   | 41641      | `0.0.0.0/0`     | Tailscale direct-connect                                |

**Findings:**

- SSH port 22 open world-wide. ADR-011 mandates Tailscale-only admin
  plane; world-open 22 is a drift. Separate cleanup task warranted
  (not in current sprint scope; file as backlog).
- 80/443 world-open on **all** galaxies — acceptable today on
  gxy-static + gxy-cassiopeia (public static), but gxy-management and
  gxy-launchbase serve org-gated tooling and should not be reachable
  outside CF proxy. Current exposure likely relies on TLS + CF Access
  / OAuth gates, not network-layer ACL.
- Single-firewall-for-all limits per-galaxy policy. Q4 narrowing by
  CF IPs would need either per-galaxy firewall or tag-scoped rules.
  Prefer split: `gxy-fw-cassiopeia-public` + `gxy-fw-mgmt-orggate` +
  `gxy-fw-launchbase-orggate` post-MVP.
- No DO Load Balancers. Traffic hits node public IPs directly via CF
  DNS A-records pointing at all 3 droplet IPs. Acceptable while CF
  proxies; regional re-route on node failure relies on CF health
  checks (not configured — check CF load balancer / proxy settings).

## Rename partial-state (informs #22)

Repo already partially renamed. Current state across the three naming
forms (per HANDOFF §Naming conventions):

| Form               | Current value             | Renamed? |
| ------------------ | ------------------------- | -------- |
| Repo dir           | `k3s/gxy-management/`     | **Yes**  |
| Ansible group_vars | `gxy_mgmt_k3s.yml`        | **No**   |
| DO droplet tag     | `gxy-mgmt-k3s`            | **No**   |
| Droplet names      | `gxy-vm-mgmt-k3s-{1,2,3}` | **No**   |

Implication for #22: infra-facing rename is the larger half. Ansible
inventory references group → destroys referential integrity with
current group_vars file if touched piecemeal. Runbook #21 already
covers the atomic sequence; confirm runbook handles the repo-dir step
being pre-applied (idempotence).

## Recommendations

Numbered in sprint-execution order.

1. **#22 rename exec** — confirm runbook idempotent w.r.t. repo-dir
   already renamed. Execute when operator present.
2. **Zot deployment** — deploy `k3s/gxy-management/apps/zot/` as part
   of triangulum M5 gate, not MVP. Leave declared-but-undeployed;
   note in TODO-park.md if not already.
3. **Firewall rework** — post-MVP, split `gxy-fw-fra1` into
   per-galaxy firewalls; narrow 80/443 on cassiopeia to CF IP ranges
   per Q4 recommendation. Out of this sprint's scope.
4. **SSH/22 world-exposure** — open as separate backlog item
   (ADR-011 drift). Close via Tailscale-only SSH + firewall remove
   `0.0.0.0/0` on port 22.
5. **DR posture** — activate DO droplet backups on gxy-launchbase
   (CNPG data) and gxy-management (argocd + windmill state) before
   first production DB on launchbase. Cost: ~+$57.60/mo combined.
   Not MVP blocker.
6. **Etcd snapshot offload** — k3s has built-in s3-target snapshot
   config; point at R2 bucket. Ship with flight-manual doomsday
   rebuild procedure. Post-MVP task.
7. **Cross-AZ / cross-region DR** — parked (ADR-012). Re-evaluate
   after triangulum lands.

## Data captured for future diff

- Droplet inventory: 12 droplets, FRA1, sizes per table above.
- Firewall: `ebd1c524-ef60-4c03-90ba-b3ec913699d8` (`gxy-fw-fra1`).
- DO project: `Universe-Main` (`576771d3-6789-4668-aad4-8e8b580f6113`).
- No LBs, Reserved IPs, Volumes, DOKS clusters.
- Repo branch: `feat/k3s-universe`.
