# 15 — Artemis Postgres failover drill (CloudNativePG pair)

**Audience:** operator. **Trigger:** rehearse the `artemis-pg` pair before it carries production data, or after any change to its instance count, storage class or `nodeMaintenanceWindow`.

The pair is a CloudNativePG `Cluster` named `artemis-pg` in namespace `artemis` on `gxy-management`. It runs beside the legacy `artemis-postgresql` StatefulSet, which still holds the `hatchet` database.

This runbook proves three things: the standby streams, the primary moves under node loss, and the move is reversible.

> The `kubectl cnpg` plugin is **not** installed on the operator laptop. Every step below uses plain `kubectl`. Install the plugin with `kubectl krew install cnpg` if you prefer its shorthand; nothing here depends on it.

```sh
export KUBECONFIG=~/DEV/fCC/infra/k3s/gxy-management/.kubeconfig.yaml
```

## Preconditions

- `kubectl -n artemis get cluster artemis-pg` reports `readyInstances: 2` and phase `Cluster in healthy state`.
- The two instances sit on different nodes. `podAntiAffinityType: required` guarantees it; confirm anyway.
- A third node is free of `artemis-pg` pods. The pair cannot reschedule without one.
- `just release`-clean tree. Do not run a drill across a pending chart change.

**Never name a pod ordinal.** The primary moves. Resolve it by label:

```sh
kubectl -n artemis get pod -l cnpg.io/cluster=artemis-pg,cnpg.io/instanceRole=primary -o name
```

Clients reach the primary through the `artemis-pg-rw` service. `artemis-pg-ro` serves the standbys and `artemis-pg-r` serves any instance.

## Baseline

Record all four before you touch anything.

```sh
kubectl -n artemis get cluster artemis-pg \
  -o custom-columns='READY:.status.readyInstances,PRIMARY:.status.currentPrimary,PHASE:.status.phase'
kubectl -n artemis get pods -l cnpg.io/cluster=artemis-pg \
  -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,ROLE:.metadata.labels.cnpg\.io/instanceRole'
kubectl -n artemis get pdb
curl -sS -o /dev/null -w '%{http_code}\n' https://uploads.freecode.camp/healthz
```

Expected today: 2 ready, primary on one node, standby on another, and `artemis-pg-primary` with `disruptionsAllowed: 0`.

## A — Replication lag

Read `pg_stat_replication` on the primary. This is the same query the `artemis-pg-lag-watch` CronJob runs every 15 minutes.

```sh
PRIMARY=$(kubectl -n artemis get pod -l cnpg.io/cluster=artemis-pg,cnpg.io/instanceRole=primary -o name | head -1)
kubectl -n artemis exec "$PRIMARY" -c postgres -- psql -U postgres -d artemis -tAc \
  "select application_name, state, sync_state, pg_wal_lsn_diff(sent_lsn, replay_lsn) from pg_stat_replication"
```

Expected: one row, `streaming`, `async`, lag `0`.

**A lag of `0` does not prove the query works.** A role that is neither superuser nor a member of `pg_read_all_stats` reads NULL in every LSN column, and the CronJob's `coalesce(...,0)` turns that into `0`. Separate the two cases:

```sh
kubectl -n artemis exec "$PRIMARY" -c postgres -- psql -U postgres -d artemis -tAc \
  "set role artemis; select sent_lsn is not null, replay_lsn is not null from pg_stat_replication"
```

Expected `t|t`. An `f|f` means the `spec.managed.roles` grant is gone and the lag watch is blind.

## B — Planned failover

Delete the primary pod. CloudNativePG promotes the standby, then rebuilds the old primary as a standby on its existing volume.

```sh
date -u +%H:%M:%S
kubectl -n artemis delete pod "${PRIMARY#pod/}"
kubectl -n artemis get cluster artemis-pg -w
```

| check                    | expected                                |
| ------------------------ | --------------------------------------- |
| `currentPrimary`         | changes to the other instance           |
| `readyInstances`         | returns to 2                            |
| `/healthz`               | stays `200` throughout                  |
| `artemis-pg-rw` endpoint | follows the new primary, no manual step |

Record the seconds from delete to `readyInstances: 2`. That number is the RTO for a promotion, and ruling R2 defines RTO as the standby promotion time.

**Measured 2026-09-11**, primary `artemis-pg-1` on k3s-3, deleted at 08:19:38Z:

| mark                        | time      | delta from delete |
| --------------------------- | --------- | ----------------- |
| `currentPrimary` changes    | 08:22:42Z | **182.9s**        |
| `readyInstances` back to 2  | 08:22:53Z | 193.9s            |

`/healthz` answered 200 on all 226 polls. Both instances stayed on their original nodes with 0 restarts, replication returned to `streaming` at lag 0, the `pg_read_all_stats` grant survived, and `deploys` held at 321 rows.

**183s is the number to improve, and the cause is not yet established.** The obvious suspect is wrong: `smartShutdownTimeout` (180s, and a near-exact match) does not apply here, because CloudNativePG runs `TryShuttingDownFastImmediate` on a deleted primary, bounded by `switchoverDelay` (3600s), not a smart shutdown. The old pod's logs are destroyed with the pod, and the operator logged nothing between 08:19:38Z and 08:22:52Z. Capture both before the next run:

```sh
kubectl -n artemis logs -f "$PRIMARY" -c postgres > /tmp/old-primary.log &
kubectl -n cnpg-system logs -f -l app.kubernetes.io/name=cloudnative-pg > /tmp/operator.log &
```

**The 183s is handover latency, not downtime.** The old primary kept serving through `artemis-pg-rw` for nearly all of it. Three facts fix this:

- The `/readyz` probe runs every 10s on 3 pods, so about 55 probes fell inside the window. Exactly **one** logged `readyz.postgres.degraded`, at 08:22:40.
- The outbox relay logged exactly **one** `relay.run` connect failure, at 08:22:39.
- `artemis-pg-2` reports `pg_postmaster_start_time()` of 06:06:08, unbroken across the drill. The standby was promoted in place. Only the old primary restarted, at 08:22:43.

Real write unavailability was therefore about **3 seconds**, at the end of the window. Nothing was lost: zero rows were written between 08:19:38Z and 08:22:42Z, the last write before the drill was at 07:24:33Z, and the outbox holds 0 unpublished rows.

The cost of the 183s is a delayed handover, not an outage. It matters for a planned `kubectl delete pod`, which is what a chart change or a drain performs. It should not apply to an unplanned instance loss, where there is no old primary to wait for and `failoverDelay` is 0 — section C measures that case and has not been run.

## C — Node loss

A node carrying an instance goes away. Two cases behave differently, and the difference is the `artemis-pg-primary` PodDisruptionBudget.

| pod on the drained node | PDB                                                                    | drain behaviour                    |
| ----------------------- | ---------------------------------------------------------------------- | ---------------------------------- |
| standby                 | none — CloudNativePG builds a replicas PDB only at 3 or more instances | evicts cleanly                     |
| primary                 | `artemis-pg-primary`, `disruptionsAllowed: 0`                          | **blocks** until the primary moves |

Drain the standby's node first to see the clean path. Then drain the primary's node and watch the drain hang. Do not reach for `--force` or `--disable-eviction`. Move the primary instead, using section B, and then drain.

`local-path` pins each volume to one node by `nodeAffinity` and cannot expand it. An evicted instance therefore cannot start elsewhere on its old volume.

### Measured 2026-09-11 — drain of `k3s-3`, which held the standby

The standby evicted cleanly, as the table predicts. Two results were not predicted.

**The drain still hung, on a workload in another namespace.** `valkey-0` is a single replica with a PodDisruptionBudget of `minAvailable: 1`, so `disruptionsAllowed` is `0` and `kubectl drain` retried the eviction every 5 seconds without end. Read the PodDisruptionBudgets across all namespaces before a drain, not only `artemis`:

```sh
kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed
```

Three reported `0`: `artemis-pg-primary`, `artemis-postgresql` and `valkey`. See [12-node-drain-maintenance.md](12-node-drain-maintenance.md).

**The `local-path` pin is now proven.** `artemis-pg-1` went `Pending` with this scheduler event:

```
0/3 nodes are available: 1 node(s) were unschedulable,
2 node(s) didn't match PersistentVolume's node affinity.
```

| mark                         | value  |
| ---------------------------- | ------ |
| cluster state while drained  | `1/2`, phase `Waiting for the instances to become active` |
| primary                      | `artemis-pg-2`, unmoved, 0 restarts |
| edge `/healthz`              | `200` throughout |
| `uncordon` to pod `Running`  | 5s     |
| `uncordon` to `2/2` healthy  | **17s** |

The instance re-attached the same volume. There was no re-clone and no restart, and replication returned to `streaming` at `lag_bytes=0`.

This 17s is the baseline case, where `nodeMaintenanceWindow.inProgress` is `false` and `reusePVC` is therefore inert. It is not the section D measurement.

## D — The `reusePVC` measurement

`nodeMaintenanceWindow` applies only while `inProgress` is `true`. Both keys are chart values:

| key                                     | default |
| --------------------------------------- | ------- |
| `postgresCluster.maintenanceInProgress` | `false` |
| `postgresCluster.reusePVC`              | `true`  |

Set them in `values.production.yaml` and release from `~/DEV/fCC/infra` on `main`. Do not release from a stale worktree.

**`reusePVC` is inert while `inProgress` is `false`.** The operator evaluates `IsNodeMaintenanceWindowInProgress() && IsReusePVCEnabled()`, so a `false` `inProgress` short-circuits the pair. On an unplanned node failure the operator waits for the original node and its pinned PVC to return, whatever `reusePVC` says. This setting therefore governs **planned drains only**, where the node comes back by definition.

| value   | behaviour during a drain                                                                                                              | cost                                            |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `true`  | The operator waits for the drained node to return and re-attaches the same volume. It removes the PodDisruptionBudget while it waits. | The instance stays down until the node returns. |
| `false` | The operator discards the pinned volume and rebuilds the instance on a free node, re-cloning from the primary.                        | One re-clone.                                   |

Upstream calls `false` unsuitable **unless the database is small enough for fast re-cloning**. The `artemis` database measured 11877399 bytes on 2026-09-11. Upstream also keeps `nodeMaintenanceWindow` for backward compatibility only, and recommends direct control of the PodDisruptionBudget instead.

Ruling R6 chose `true`. It was made on a description that had the two values the wrong way round. Measure before you re-rule:

1. Set `maintenanceInProgress: true` and `reusePVC: true`. Release. Drain the standby's node. Time the return to `readyInstances: 2` after you uncordon.
1. Run `kubectl -n artemis describe resourcequota baseline`. The re-clone needs the drained instance's memory to be free first. A blocked join Job is section F, not a CloudNativePG fault.
1. Set `reusePVC: false`. Release. Drain again. Time the re-clone.
1. Clear `maintenanceInProgress`. Release.

Step 3 moves the standby to whichever node is free. That changes the blast radius recorded in [12-node-drain-maintenance.md](12-node-drain-maintenance.md). Update that table if the standby does not return to its old node.

Record both numbers here. The ruling follows the measurement.

- **`reusePVC: true` recovery:** _(pending)_
- **`reusePVC: false` recovery:** _(pending)_

## E — Rollback

Every step in this runbook is reversible.

| situation                            | rollback                                                                                                                                                       |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Promotion went to the wrong instance | Repeat section B. The pair has no preferred primary.                                                                                                           |
| A drill left `inProgress: true`      | Set it back to `false` and release. It is inert either way until a drain.                                                                                      |
| The pair misbehaves before cutover   | Where `postgresCluster.cutover` is `false`, artemis still uses the StatefulSet. Set `postgresCluster.enabled: false` and release to remove the `Cluster`.      |
| The pair misbehaves after cutover    | Set `postgresCluster.cutover: false` and release. See the section below.                                                                                       |

Never set `postgres.enabled: false`. That deletes the instance holding the `hatchet` database, and it also drops the hatchet gRPC egress rule, which sits inside the same conditional.

### The cutover rollback

`postgresCluster.cutover` on gxy-management is `true` since 2026-09-11. `secret-env.yaml` builds `DATABASE_URL` from the flag, so the rollback is the flag and a release, not a hand-edited secret.

| `cutover` | `DATABASE_URL` the chart builds                                                          |
| --------- | ---------------------------------------------------------------------------------------- |
| `true`    | `postgres://artemis:$ARTEMIS_DB_PASSWORD@artemis-pg-rw:5432/artemis?sslmode=require`      |
| `false`   | `postgres://artemis:$ARTEMIS_DB_PASSWORD@artemis-postgresql:5432/artemis?sslmode=disable` |

`sslmode` comes from `postgres.sslmode`, which is `disable` in the chart defaults. A `secretEnv.DATABASE_URL` in the sops overlay wins over both rows; confirm the overlay sets none before you trust the table.

**Rows written to the pair since the cutover do not follow the rollback.** The StatefulSet copy is frozen at the import. Read both counts before you decide:

```bash
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -tAc "select count(*) from deploys;"
PRIMARY=$(kubectl -n artemis get pod -l cnpg.io/cluster=artemis-pg,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}')
kubectl -n artemis exec "$PRIMARY" -c postgres -- psql -U postgres -d artemis -tAc "select count(*) from deploys;"
```

On 2026-09-11 those read 248 and 324. The gap is what a rollback discards.

### Hatchet during the cutover window

The cutover release restarts the three artemis pods, and each pod runs one Hatchet worker. The window does not read as an incident. Measured on the engine pod that survived the cutover, `hatchet-engine-74f79677d7-5kjj8`, over 06:00Z to 08:00Z on 2026-09-11:

| signal                            | result                                       |
| --------------------------------- | -------------------------------------------- |
| engine `ERR` and `FTL` lines      | 0                                            |
| sampled worker-count lines        | 36, every one reporting `for 3 workers`      |
| `outbox` rows unpublished         | 0 of 299                                     |

The engine samples the worker count only when the listing is slow, so those 36 lines do not exclude a dip shorter than the gap between them. They do show the fleet back at 3 on both sides of the window, and the empty outbox shows nothing was dropped.

Expect this noise and do not treat it as a fault:

- `WRN replenishing slots took longer than 100ms`, `WRN concurrency strategy N took longer than 100ms`, and `WRN long lock .../scheduler.go:1162`. These run continuously, not only at a cutover.
- One `Readiness probe failed: HTTP probe failed with statuscode: 503` per engine pod restart.

`site.lifecycle` runs are durable. A run in flight when a worker goes away is re-claimed after the 5-minute claim expiry, and the relay retries an unpublished `outbox` row after 60 seconds. Neither needs an operator. The one real signal is a **missed** Sentry cron check-in, which happens only if the window spans 03:00Z or 04:00Z. A *red* check-in is different: that means the job ran and failed.

### The soak, and dropping the frozen copy

Keep the frozen `artemis` database on the StatefulSet for a **14-day soak** from the cutover date. It is the rollback target, and it costs 12 MB.

While it exists, a mistaken `DATABASE_URL` serves a frozen registry and raises no error. That is the reason to drop it rather than keep it forever.

Drop it on or after **2026-09-25**, and only when all three hold:

1. `postgresCluster.cutover` has stayed `true` for the whole soak.
2. `pgBackup` has written a dump of the pair's `artemis` database for each of the last 7 days.
3. Section B has been rehearsed against the pair at least once since the cutover.

```bash
kubectl -n artemis exec artemis-postgresql-0 -- \
  psql -U postgres -tAc "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'artemis';"
kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -c 'DROP DATABASE artemis;'
```

Do not drop the `artemis` **role**. The nightly `backup` job for the StatefulSet exports roles, and the `hatchet` database is unaffected by either command.

- **Cutover date:** 2026-09-11
- **Earliest drop date:** 2026-09-25
- **Dropped on:** _(pending)_

## F — Recovery from a stuck bring-up

Seen on 2026-09-11 during the first release. The second instance never started, and the operator log repeated once a second:

```
Selected PVC is not ready yet, waiting for 1 second   pvc: artemis-pg-2  status: initializing
```

`local-path` is `WaitForFirstConsumer`, so the PVC binds only when a pod consumes it. The only consumer is the join Job. If that Job is deleted or cannot be scheduled, the operator waits for a PVC that nothing will ever bind.

The namespace also carries a `ResourceQuota` named `baseline`. Check it before you blame CloudNativePG:

```sh
kubectl -n artemis describe resourcequota baseline
kubectl -n artemis get events --field-selector type=Warning
```

A `FailedCreate ... exceeded quota` event on the join Job is the real fault. A Job's pod template is immutable, so lowering the chart's memory limit does not fix a Job already created at the old value.

Clear it in this order:

1. `kubectl -n artemis delete job artemis-pg-2-join` — removes the Job pinned to the old resources.
1. `kubectl -n artemis delete pod artemis-pg-1` — the surviving instance restarts at the new limits and frees quota.
1. `kubectl -n artemis delete pvc artemis-pg-2` — removes the orphan `Pending` claim.

CloudNativePG then rebuilds the claim and the Job together. Do not delete the PVC of a **bound** instance; that discards its data copy.

## G — Record

Stamp each rehearsal here.

- **Last rehearsed:** 2026-09-11, section B only.
- **Promotion RTO:** 182.9s to `currentPrimary`, 193.9s to `readyInstances: 2`, of which about 3s was write unavailability. Cause of the 183s handover not established.
- **Node-loss outcome:** _(pending — sections C and D not run)_

## Cross-refs

- Node drains, and which workloads block one: [12-node-drain-maintenance.md](12-node-drain-maintenance.md).
- Restore from a backup artefact: [08-artemis-pg-restore-drill.md](08-artemis-pg-restore-drill.md).
- The outage boundary — serving survives a Postgres outage: [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md).
- Chart settings and the rulings behind them: `k3s/gxy-management/apps/artemis/README.md`.
