# 12 — Node drain / maintenance on gxy-management

**Audience:** operator. **Trigger:** kernel patch, DigitalOcean droplet resize, k3s upgrade, or any procedure needing a node drain on a `gxy-vm-management-k3s-*` node.

Read this before draining. Two workloads **block** the drain outright, and that is not visible from `kubectl get nodes`. A third, `valkey`, no longer blocks but goes down for the whole drain. One of the three is in the `valkey` namespace, so a survey of the `artemis` namespace alone does not find it. Which node carries which changes with scheduling — check placement first.

## Why this runbook exists

The `artemis` namespace holds three workloads with three different disruption postures. Discovered 2026-08-19 while verifying the 1.8.0 deploy; no prior runbook covered it.

| Workload | Replicas | Node | PDB | `disruptionsAllowed` | Drain behaviour |
| --- | --- | --- | --- | --- | --- |
| `artemis` (deploy proxy) | 3 | all three | `minAvailable: 2` | 1 | Drains cleanly, one node at a time |
| `artemis-postgresql` | 1 | k3s-2 | `minAvailable: 1` | **0** | **Blocks indefinitely** |
| `hatchet-engine` | 2 | two of three | `minAvailable: 1` | 1 | Drains cleanly, one node at a time (since 2026-08-31) |
| `artemis-pg` (CloudNativePG pair) | 2 | two of three | `artemis-pg-primary` | **0** | The standby's node drains cleanly. The primary's node **blocks**. |
| `valkey` (namespace `valkey`) | 1 | one of three | `maxUnavailable: 1` | 1 | Drains, but Valkey is down until the node returns |

Confirm the live numbers before trusting the table:

```sh
export KUBECONFIG=~/DEV/fCC/infra/k3s/gxy-management/.kubeconfig.yaml
kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed
kubectl get pods -A --field-selector spec.nodeName=<node> -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name
```

Read the first command across all namespaces. Every PodDisruptionBudget at `disruptionsAllowed: 0` blocks the node that holds its pod. The second command names what the target node carries.

Pod placement is not declared in any chart, so re-check which node holds Postgres, the engine and Valkey rather than assuming k3s-2 and k3s-3. A pod that already holds a `local-path` volume is a different case: its PersistentVolume carries a node affinity and the pod cannot start anywhere else. `valkey-0`, `artemis-pg-1` and `artemis-pg-2` are in that case.

## Blast radius, per workload

**`artemis` deploy proxy** — no user impact. `minAvailable: 2` keeps a serving quorum; Traefik drops the drained endpoint.

**`artemis-postgresql`** — a single replica carrying both tenant databases (`artemis` and `hatchet`). Its PDB permits zero voluntary evictions, so the drain hangs rather than proceeding. This is deliberate: the alternative is an unscheduled control-plane outage. Serving is unaffected while it is down — `/readyz` returns `200 {"ready":true,"degraded":true}` and deploys still write to R2 — but GC, the index and the audit log stop. See [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md) for the rehearsed boundary.

**`hatchet-engine`** — the durable-execution substrate. At two replicas with `minAvailable: 1` it permits one voluntary eviction, so a drain rolls rather than hangs. Required anti-affinity keeps the two pods on different nodes, so a single drain never takes both. Losing one replica is a scheduling pause, not an outage: a clean shutdown hands the tenant over at once, an unclean loss waits up to 2 minutes (partition heartbeat 20 s, inactive at 60 s, rebalance every 60 s). The impact below applies only if both go, which needs two nodes down at once:

- **Not affected:** deploy init, upload, finalize, promote, rollback, and serving. Those paths write to R2 and Postgres directly and never touch Hatchet.
- **Affected:** the scheduled jobs — `tombstone-purge` (03:00 UTC), `drift-detect` (04:00 UTC), and the event-triggered `gc-site`.
- **Not lost:** work queued while it is down. Unpublished `outbox` rows persist and the relay retries them; a claim expires after 5 minutes, so a row claimed by a dying pod becomes re-claimable.
- **Visible symptom:** a *missed* Sentry cron check-in if the outage spans 03:00 or 04:00 UTC — as distinct from a *red* check-in, which means artemis ran the job and it failed.

The engine keeps no local state; its run history lives in the `hatchet` database on `artemis-postgresql-0`, so eviction risks scheduling continuity, not data.

**`valkey`** — a single replica in the `valkey` namespace. Since the ruling of 2026-09-11 its PDB is `maxUnavailable: 1`, so the drain proceeds instead of hanging. Valkey is not the sites registry; Postgres is, after the artemis cutover of 2026-09-11. Valkey holds the deploy fence, the GitHub team cache and the `registry.changed` channel.

Its volume is `local-path`, so the evicted pod cannot start on another node and stays `Pending` until the drained node returns. Valkey is therefore down for the whole drain, not for a moment. Over that window:

- **Serving continues.** Sites are served by Caddy `r2_alias` on `gxy-cassiopeia`, which never calls artemis.
- **The artemis API continues.** `/readyz` returns `200 {"ready":true,"degraded":true}` on a Valkey ping error, so the pods stay in the Service endpoints. See artemis `docs/design/0007-readyz-degradation.md`.
- **Authentication continues.** A team-cache read error falls through to the GitHub API.
- **Deploys fail closed.** The upload and finalize handlers return `503 fence_unavailable` because the deploy fence read fails. This is correct: without the fence an in-flight permit can overwrite a finished deploy.
- **Registry changes propagate slowly.** The `registry.changed` channel is gone, so a change reaches the read-side pods on the 60 s TTL refresh from Postgres instead of at once.
- **A restarting artemis pod boots degraded.** artemis commit `9898b91` makes boot fall back to a Valkey client built without dialing when the registry source of truth is Postgres, so a rescheduled pod starts and serves. Before that release it crashlooped.

**This section describes the state after the artemis release that carries artemis commits `50df4ba` and `9898b91`.** Until that image is live, a Valkey eviction still returns `503` from `/readyz` and ejects every artemis pod from the Service, and a rescheduled artemis pod crashloops at boot. Check the running version first: `curl -sSI https://uploads.freecode.camp/healthz | grep x-artemis-version`.

## History — two blocking workloads remain

**2026-08-23.** `just release gxy-management hatchet` took the release to revision 2 and applied `hatchet-engine` at `minAvailable: 1`. **`just release gxy-management artemis` does not release the hatchet chart** — the two charts are separate releases in one namespace. That is why the template sat unapplied from 2026-06-06. At one replica that PDB blocked a drain, which was the intended trade at the time: an outage the operator times beats one the scheduler picks.

**2026-08-31.** The engine went to two replicas with required anti-affinity, per ADR-022 §Prerequisite. That reverses the trade rather than refining it: the engine no longer blocks a drain and no longer needs the manual scale-to-zero step, because one replica always survives.

**2026-09-11.** The `artemis-pg` CloudNativePG pair went live. Two workloads now block a drain, not one. CloudNativePG builds a `-primary` PodDisruptionBudget at `disruptionsAllowed: 0` for every cluster, so the node holding the primary blocks. It builds a replicas PodDisruptionBudget only at three or more instances, so at two instances the standby's node drains cleanly. Move the primary first — see [15-artemis-pg-failover-drill.md](15-artemis-pg-failover-drill.md) §B — then drain. Do not scale the `Cluster` to zero; that is not the CloudNativePG path.

**2026-09-11, third entry — the valkey PDB ruling.** `valkey` moved from `minAvailable: 1` to `maxUnavailable: 1`. On one replica the first reports `disruptionsAllowed: 0` and blocks every drain of the pinned node for good; the second reports 1 and lets the drain proceed. Two findings of the same day make the eviction survivable: Postgres, not Valkey, is the registry source of truth, and artemis `/readyz` no longer returns 503 on a Valkey ping error. `replicaCount` stays 1 — the chart has no replication wiring and the ClusterIP Service round-robins, so two replicas would split the deploy fence. See `k3s/gxy-management/apps/valkey/README.md`.

**2026-09-11, second entry.** A §C drill drain of `k3s-3` hung on `valkey-0` and retried every 5 seconds until the operator stopped it. This runbook had surveyed the `artemis` namespace only, so the third blocker was never recorded. `artemis-pg-1` evicted cleanly in the same drain and went `Pending` with `2 node(s) didn't match PersistentVolume's node affinity` — the `local-path` pin, measured rather than assumed. After `uncordon` the instance re-attached the same volume and the cluster returned to `2/2` in 17 seconds, with no re-clone and no restart.

Which node holds what is not declared anywhere. Re-check before every drain.

## Procedure

**Node holding only `artemis` replicas** — no special handling; the standard drain with `--ignore-daemonsets --delete-emptydir-data` completes on its own.

**Node holding `artemis-postgresql`** — the drain will hang. Do not reach for `--disable-eviction` or `--force`; both bypass the protection rather than satisfying it. Take the outage deliberately instead:

1. Announce the window. GC, the index and the audit log stop; serving and deploys continue.
2. Scale the statefulset to zero, which satisfies `minAvailable` by removing the pod from the PDB's scope.
3. Drain, do the maintenance, uncordon.
4. Scale back to 1 and verify per [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md) — `postgres.connected` in the artemis logs, `/readyz` no longer `degraded`, and the outbox backlog draining.

**Node holding `valkey`** — the drain proceeds. Do not scale the statefulset to zero; that step belonged to the `minAvailable: 1` posture and now causes the outage the drain would have survived.

1. Announce the window. Deploys return `503 fence_unavailable` for its whole length.
2. Confirm the artemis release carries `50df4ba` and `9898b91`. Without them a node that also holds an artemis replica loses that replica for the window: the rescheduled pod crashloops while Valkey is `Pending`. Drain a different node first, or accept 2 of 3 replicas.
3. Drain, do the maintenance, uncordon.
4. `valkey-0` re-attaches the same `local-path` volume when the node returns.
5. Confirm `curl -sS https://uploads.freecode.camp/readyz` returns `{"ready":true}` with no `degraded`, and run one real deploy.

**Node holding one `hatchet-engine` replica** — no special handling since 2026-08-31; `minAvailable: 1` at two replicas permits the eviction and the drain completes. Do NOT scale to zero: that step belonged to the single-replica posture and now causes an outage the PDB was about to prevent. Two cautions remain. Required anti-affinity means the evicted pod cannot reschedule until a node with no engine pod is free, so it stays `Pending` while the drained node is cordoned — expected, not a fault. And prefer a window outside 03:00–04:30 UTC so the nightly check-ins are not recorded as missed. Confirm the workers re-attach afterwards: the engine log reports `listing actions for workers` with a non-zero count.

### `valkey-0` and `artemis-pg-1` share k3s-3 — ruling 2026-09-11

**Do not move either one.** The co-location is accepted.

Measured on 2026-09-11:

```
data-valkey-0   local-path   [gxy-vm-management-k3s-3]
artemis-pg-1    local-path   [gxy-vm-management-k3s-3]   replica
artemis-pg-2    local-path   [gxy-vm-management-k3s-1]   primary
```

The cost of losing k3s-3 is one node's blast radius, which is what the design accepts:

- Valkey goes down. Deploys return `503 fence_unavailable`. Serving, authentication and the registry continue, per the Valkey entry above.
- The `artemis-pg` standby goes down. The primary is on k3s-1 and keeps serving. The pair loses its replication protection until the node returns; the daily R2 dump remains the backup floor.

Neither loss reaches the serve plane. The two faults do not compound: one pauses deploys, the other removes redundancy, and each is already the documented single-node case.

The move is also not durable. Both volumes are `local-path` with `WaitForFirstConsumer` and a `Delete` reclaim policy, so a volume cannot be detached and re-attached elsewhere — the move is a rebuild.

- Rebuilding `artemis-pg-1` is cheap. Delete the instance's PVC and pod and CloudNativePG re-clones the standby from the primary. **The new PVC binds wherever the scheduler puts the new pod.** `podAntiAffinityType: required` keeps it off k3s-1 and leaves k3s-2 and k3s-3, so the rebuild can land back on k3s-3. Holding it off k3s-3 needs an explicit `nodeSelector` or node affinity on the `Cluster`, which pins the pair to named nodes and removes the scheduling freedom the anti-affinity rule exists to use.
- Rebuilding `valkey-0` loses the append-only file. After the 2026-09-11 cutover that file holds the deploy fence and the GitHub team cache, not the registry. Both rebuild on demand, but any in-flight deploy permit is lost.

Re-open this ruling when a switchover puts the `artemis-pg` primary on k3s-3. The primary and Valkey on one node is a different case: that node's loss pauses deploys *and* forces a promotion, and the two recoveries compete for the same window. Check the current role before any planned maintenance:

```sh
kubectl -n artemis get pod -l cnpg.io/cluster=artemis-pg \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ROLE:.metadata.labels.cnpg\.io/instanceRole
```

### Full order for a node carrying more than one blocker

A node can hold the `artemis-pg` primary, `valkey-0`, `artemis-postgresql-0` and an artemis replica at once. Survey first, then run the steps that apply, in this order.

```sh
export KUBECONFIG=~/DEV/fCC/infra/k3s/gxy-management/.kubeconfig.yaml
kubectl get pods -A --field-selector spec.nodeName=<node> -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name
kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed
```

1. **Announce the window.** Deploys stop for its whole length if the node holds `valkey-0`.
2. **Set the CloudNativePG maintenance window** if the node holds an `artemis-pg` instance. Set `postgresCluster.nodeMaintenanceWindow.inProgress: true` and release. `reusePVC` is `true`, so the operator waits for the node and re-attaches the same volume.
3. **Move the `artemis-pg` primary off the node** if it is there. See [15-artemis-pg-failover-drill.md](15-artemis-pg-failover-drill.md) §B. The `-primary` PDB sits at `disruptionsAllowed: 0` and blocks until the primary is elsewhere.
4. **Scale `artemis-postgresql` to zero** if the node holds it. Its PDB is `minAvailable: 1` on one replica and blocks otherwise.
5. **Do nothing for `valkey-0`.** `maxUnavailable: 1` permits the eviction. Do not scale it to zero.
6. **Do nothing for `hatchet-engine` or the artemis replicas.** Both roll.
7. **Drain**, do the maintenance, **uncordon**.
8. **Restore, in reverse:** scale `artemis-postgresql` back to 1, clear `inProgress`, and confirm `valkey-0` re-attached its volume.
9. **Verify** per the section below, and run one real deploy.

Do not use `--force` or `--disable-eviction` at any step. Both bypass a PDB rather than satisfying it.

## Verify after any drain

```sh
kubectl -n artemis get pods -o wide          # all Running, spread across the surviving nodes
kubectl get pdb -A                           # artemis, hatchet-engine AND valkey disruptionsAllowed back to 1
kubectl -n artemis get pods -o wide          # confirm PG's node, and that the two engine pods are on different nodes
curl -sS https://uploads.freecode.camp/healthz
```

Then confirm the next scheduled check-ins land: Sentry org `freecodecamp`, project `artemis`, monitors `tombstone-purge` and `drift-detect`.
