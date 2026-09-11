# 12 — Node drain / maintenance on gxy-management

**Audience:** operator. **Trigger:** kernel patch, DigitalOcean droplet resize, k3s upgrade, or any procedure needing a node drain on a `gxy-vm-management-k3s-*` node.

Read this before draining. Three workloads **block** the drain outright, and that is not visible from `kubectl get nodes`. One of the three is in the `valkey` namespace, so a survey of the `artemis` namespace alone does not find it. Which node carries which changes with scheduling — check placement first.

## Why this runbook exists

The `artemis` namespace holds three workloads with three different disruption postures. Discovered 2026-08-19 while verifying the 1.8.0 deploy; no prior runbook covered it.

| Workload | Replicas | Node | PDB | `disruptionsAllowed` | Drain behaviour |
| --- | --- | --- | --- | --- | --- |
| `artemis` (deploy proxy) | 3 | all three | `minAvailable: 2` | 1 | Drains cleanly, one node at a time |
| `artemis-postgresql` | 1 | k3s-2 | `minAvailable: 1` | **0** | **Blocks indefinitely** |
| `hatchet-engine` | 2 | two of three | `minAvailable: 1` | 1 | Drains cleanly, one node at a time (since 2026-08-31) |
| `artemis-pg` (CloudNativePG pair) | 2 | two of three | `artemis-pg-primary` | **0** | The standby's node drains cleanly. The primary's node **blocks**. |
| `valkey` (namespace `valkey`) | 1 | one of three | `minAvailable: 1` | **0** | **Blocks indefinitely** |

Confirm the live numbers before trusting the table:

```sh
export KUBECONFIG=~/DEV/fCC/infra/k3s/gxy-management/.kubeconfig.yaml
kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed
kubectl get pods -A --field-selector spec.nodeName=<node> -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name
```

Read the first command across all namespaces. Every PodDisruptionBudget at `disruptionsAllowed: 0` blocks the node that holds its pod. The second command names what the target node carries.

Pod placement is not pinned, so re-check which node holds Postgres, the engine and Valkey rather than assuming k3s-2 and k3s-3.

## Blast radius, per workload

**`artemis` deploy proxy** — no user impact. `minAvailable: 2` keeps a serving quorum; Traefik drops the drained endpoint.

**`artemis-postgresql`** — a single replica carrying both tenant databases (`artemis` and `hatchet`). Its PDB permits zero voluntary evictions, so the drain hangs rather than proceeding. This is deliberate: the alternative is an unscheduled control-plane outage. Serving is unaffected while it is down — `/readyz` returns `200 {"ready":true,"degraded":true}` and deploys still write to R2 — but GC, the index and the audit log stop. See [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md) for the rehearsed boundary.

**`hatchet-engine`** — the durable-execution substrate. At two replicas with `minAvailable: 1` it permits one voluntary eviction, so a drain rolls rather than hangs. Required anti-affinity keeps the two pods on different nodes, so a single drain never takes both. Losing one replica is a scheduling pause, not an outage: a clean shutdown hands the tenant over at once, an unclean loss waits up to 2 minutes (partition heartbeat 20 s, inactive at 60 s, rebalance every 60 s). The impact below applies only if both go, which needs two nodes down at once:

- **Not affected:** deploy init, upload, finalize, promote, rollback, and serving. Those paths write to R2 and Postgres directly and never touch Hatchet.
- **Affected:** the scheduled jobs — `tombstone-purge` (03:00 UTC), `drift-detect` (04:00 UTC), and the event-triggered `gc-site`.
- **Not lost:** work queued while it is down. Unpublished `outbox` rows persist and the relay retries them; a claim expires after 5 minutes, so a row claimed by a dying pod becomes re-claimable.
- **Visible symptom:** a *missed* Sentry cron check-in if the outage spans 03:00 or 04:00 UTC — as distinct from a *red* check-in, which means artemis ran the job and it failed.

The engine keeps no local state; its run history lives in the `hatchet` database on `artemis-postgresql-0`, so eviction risks scheduling continuity, not data.

**`valkey`** — a single replica in the `valkey` namespace. Its PDB permits zero voluntary evictions, so the drain hangs. Do not satisfy it by force. Valkey is the sites registry, and artemis `/readyz` returns 503 on a Valkey ping error, so evicting the pod takes `uploads.freecode.camp` out of service. Its volume is `local-path` as well, so the evicted pod cannot start on another node and stays `Pending` until the drained node returns. The same scale-to-zero procedure as `artemis-postgresql` applies, and it is a serving outage rather than a control-plane one.

## History — one blocking workload remains

**2026-08-23.** `just release gxy-management hatchet` took the release to revision 2 and applied `hatchet-engine` at `minAvailable: 1`. **`just release gxy-management artemis` does not release the hatchet chart** — the two charts are separate releases in one namespace. That is why the template sat unapplied from 2026-06-06. At one replica that PDB blocked a drain, which was the intended trade at the time: an outage the operator times beats one the scheduler picks.

**2026-08-31.** The engine went to two replicas with required anti-affinity, per ADR-022 §Prerequisite. That reverses the trade rather than refining it: the engine no longer blocks a drain and no longer needs the manual scale-to-zero step, because one replica always survives.

**2026-09-11.** The `artemis-pg` CloudNativePG pair went live. Two workloads now block a drain, not one. CloudNativePG builds a `-primary` PodDisruptionBudget at `disruptionsAllowed: 0` for every cluster, so the node holding the primary blocks. It builds a replicas PodDisruptionBudget only at three or more instances, so at two instances the standby's node drains cleanly. Move the primary first — see [15-artemis-pg-failover-drill.md](15-artemis-pg-failover-drill.md) §B — then drain. Do not scale the `Cluster` to zero; that is not the CloudNativePG path.

**2026-09-11, second entry.** A §C drill drain of `k3s-3` hung on `valkey-0` and retried every 5 seconds until the operator stopped it. This runbook had surveyed the `artemis` namespace only, so the third blocker was never recorded. `artemis-pg-1` evicted cleanly in the same drain and went `Pending` with `2 node(s) didn't match PersistentVolume's node affinity` — the `local-path` pin, measured rather than assumed. After `uncordon` the instance re-attached the same volume and the cluster returned to `2/2` in 17 seconds, with no re-clone and no restart.

Placement is not pinned. Re-check before every drain.

## Procedure

**Node holding only `artemis` replicas** — no special handling; the standard drain with `--ignore-daemonsets --delete-emptydir-data` completes on its own.

**Node holding `artemis-postgresql`** — the drain will hang. Do not reach for `--disable-eviction` or `--force`; both bypass the protection rather than satisfying it. Take the outage deliberately instead:

1. Announce the window. GC, the index and the audit log stop; serving and deploys continue.
2. Scale the statefulset to zero, which satisfies `minAvailable` by removing the pod from the PDB's scope.
3. Drain, do the maintenance, uncordon.
4. Scale back to 1 and verify per [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md) — `postgres.connected` in the artemis logs, `/readyz` no longer `degraded`, and the outbox backlog draining.

**Node holding `valkey`** — the drain will hang on `valkey-0`. Treat it as the `artemis-postgresql` case with one difference: this one stops serving, not just the control plane. Announce the window, scale the statefulset to zero, drain, uncordon, scale back to 1, then confirm `curl -sS https://uploads.freecode.camp/healthz` returns 200 and `/readyz` is not `degraded`.

**Node holding one `hatchet-engine` replica** — no special handling since 2026-08-31; `minAvailable: 1` at two replicas permits the eviction and the drain completes. Do NOT scale to zero: that step belonged to the single-replica posture and now causes an outage the PDB was about to prevent. Two cautions remain. Required anti-affinity means the evicted pod cannot reschedule until a node with no engine pod is free, so it stays `Pending` while the drained node is cordoned — expected, not a fault. And prefer a window outside 03:00–04:30 UTC so the nightly check-ins are not recorded as missed. Confirm the workers re-attach afterwards: the engine log reports `listing actions for workers` with a non-zero count.

## Verify after any drain

```sh
kubectl -n artemis get pods -o wide          # all Running, spread across the surviving nodes
kubectl get pdb -A                           # artemis AND hatchet-engine disruptionsAllowed back to 1
kubectl -n artemis get pods -o wide          # confirm PG's node, and that the two engine pods are on different nodes
curl -sS https://uploads.freecode.camp/healthz
```

Then confirm the next scheduled check-ins land: Sentry org `freecodecamp`, project `artemis`, monitors `tombstone-purge` and `drift-detect`.
