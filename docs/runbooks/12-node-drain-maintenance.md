# 12 — Node drain / maintenance on gxy-management

**Audience:** operator. **Trigger:** kernel patch, DigitalOcean droplet resize, k3s upgrade, or any procedure needing a node drain on a `gxy-vm-management-k3s-*` node.

Read this before draining. Two of the three nodes carry a workload that either **blocks** the drain or is **evicted with no protection**, and neither is visible from `kubectl get nodes`.

## Why this runbook exists

The `artemis` namespace holds three workloads with three different disruption postures. Discovered 2026-08-19 while verifying the 1.8.0 deploy; no prior runbook covered it.

| Workload | Replicas | Node | PDB | `disruptionsAllowed` | Drain behaviour |
| --- | --- | --- | --- | --- | --- |
| `artemis` (deploy proxy) | 3 | all three | `minAvailable: 2` | 1 | Drains cleanly, one node at a time |
| `artemis-postgresql` | 1 | k3s-2 | `minAvailable: 1` | **0** | **Blocks indefinitely** |
| `hatchet-engine` | 1 | k3s-3 | **none deployed** | n/a | **Evicted immediately, no warning** |

Confirm the live numbers before trusting the table:

```sh
export KUBECONFIG=~/DEV/fCC/infra/k3s/gxy-management/.kubeconfig.yaml
kubectl -n artemis get pdb
kubectl -n artemis get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

Pod placement is not pinned, so re-check which node holds Postgres and the engine rather than assuming k3s-2 and k3s-3.

## Blast radius, per workload

**`artemis` deploy proxy** — no user impact. `minAvailable: 2` keeps a serving quorum; Traefik drops the drained endpoint.

**`artemis-postgresql`** — a single replica carrying both tenant databases (`artemis` and `hatchet`). Its PDB permits zero voluntary evictions, so the drain hangs rather than proceeding. This is deliberate: the alternative is an unscheduled control-plane outage. Serving is unaffected while it is down — `/readyz` returns `200 {"ready":true,"degraded":true}` and deploys still write to R2 — but GC, the index and the audit log stop. See [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md) for the rehearsed boundary.

**`hatchet-engine`** — the durable-execution substrate. It has **no PDB in the cluster**, so a drain evicts it instantly. The impact is narrower than it looks:

- **Not affected:** deploy init, upload, finalize, promote, rollback, and serving. Those paths write to R2 and Postgres directly and never touch Hatchet.
- **Affected:** the scheduled jobs — `tombstone-purge` (03:00 UTC), `drift-detect` (04:00 UTC), and the event-triggered `gc-site`.
- **Not lost:** work queued while it is down. Unpublished `outbox` rows persist and the relay retries them; a claim expires after 5 minutes, so a row claimed by a dying pod becomes re-claimable.
- **Visible symptom:** a *missed* Sentry cron check-in if the outage spans 03:00 or 04:00 UTC — as distinct from a *red* check-in, which means artemis ran the job and it failed.

The engine keeps no local state; its run history lives in the `hatchet` database on `artemis-postgresql-0`, so eviction risks scheduling continuity, not data.

## Known gap — the hatchet PDB is written but not shipped

`k3s/gxy-management/apps/hatchet/charts/hatchet/templates/pdb.yaml` exists and is gated on `pdb.enabled`, but the `hatchet` Helm release is still revision 1 from 2026-06-06. **`just release gxy-management artemis` does not release the hatchet chart**, so the template has never been applied. Verify:

```sh
helm -n artemis list          # hatchet REVISION 1 => the PDB is not deployed
kubectl -n artemis get pdb    # only `artemis` and `artemis-postgresql` appear
```

Shipping it flips k3s-3 from *surprise eviction* to *blocked drain*, matching Postgres. That is the chart author's stated intent — an outage the operator times beats one the scheduler picks. It is a decision, not a defect: make it deliberately, and if you ship it, expect two of three nodes to need the manual step below.

## Procedure

**Node holding only `artemis` replicas** — no special handling; the standard drain with `--ignore-daemonsets --delete-emptydir-data` completes on its own.

**Node holding `artemis-postgresql`** — the drain will hang. Do not reach for `--disable-eviction` or `--force`; both bypass the protection rather than satisfying it. Take the outage deliberately instead:

1. Announce the window. GC, the index and the audit log stop; serving and deploys continue.
2. Scale the statefulset to zero, which satisfies `minAvailable` by removing the pod from the PDB's scope.
3. Drain, do the maintenance, uncordon.
4. Scale back to 1 and verify per [11-artemis-pg-outage-drill.md](11-artemis-pg-outage-drill.md) — `postgres.connected` in the artemis logs, `/readyz` no longer `degraded`, and the outbox backlog draining.

**Node holding `hatchet-engine`** — today it needs no action; the pod is evicted and reschedules. Prefer a window outside 03:00–04:30 UTC so the nightly check-ins are not recorded as missed. If the PDB is later shipped, follow the Postgres procedure instead, scaling the engine deployment to zero.

## Verify after any drain

```sh
kubectl -n artemis get pods -o wide          # all Running, spread across the surviving nodes
kubectl -n artemis get pdb                   # artemis disruptionsAllowed back to 1
curl -sS https://uploads.freecode.camp/healthz
```

Then confirm the next scheduled check-ins land: Sentry org `freecodecamp`, project `artemis`, monitors `tombstone-purge` and `drift-detect`.
