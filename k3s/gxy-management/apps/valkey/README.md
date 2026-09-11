# Valkey — registry cache front

In-cluster Valkey serving the static-apps registry consumed by artemis (`/api/site/register`, `/api/sites`, `/api/site/{slug}` PATCH/DELETE).

**Valkey is not the source of truth.** After the artemis Postgres cutover of 2026-09-11, `pg.RegistryStore` is the registry Writer and the Reader source; Valkey is the cache front and the `registry.changed` transport (artemis `cmd/artemis/main.go`, `openRegistry`). A Valkey outage loses no registry data. It costs the artemis deploy fence, the GitHub team cache and the change channel.

Selected over CF KV / R2 JSON / Postgres / etcd / Redis in `docs/architecture/rfc-gxy-cassiopeia-ga.md` §3 KV substrate matrix. Vendor-neutral, in-cluster, decouples the registry from the operator-on-PR loop that previously gated `artemis/config/sites.yaml`.

## Layout

```
apps/valkey/
├── README.md                    # this file
├── .deploy-flags.sh             # decrypts sops overlay into helm chain
├── values.production.yaml       # non-secret production overlay
├── charts/valkey/               # local Helm chart (greenfield)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── namespace.yaml
│       ├── statefulset.yaml     # 1 replica, 1Gi PVC, AOF on
│       ├── service.yaml         # ClusterIP + headless companion
│       ├── configmap.yaml       # valkey.conf
│       ├── secret-env.yaml      # VALKEY_PASSWORD from sops overlay
│       ├── pdb.yaml             # maxUnavailable 1 (ruling 2026-09-11)
│       └── networkpolicy.yaml   # ingress from artemis pods only
├── secrets/
│   └── valkey.values.yaml.enc.template  # sops envelope schema
└── scripts/
    └── import-sites.sh          # 11-site cutover hand-import
```

## Wire schema (consumed by artemis)

Per the artemis `internal/registry/valkey/store.go` shape:

| Key                | Type   | Fields                                                         | Purpose                    |
| ------------------ | ------ | -------------------------------------------------------------- | -------------------------- |
| `site:<slug>`      | hash   | `teams` (JSON array), `created_at`, `updated_at`, `created_by` | per-site row               |
| `sites:all`        | set    | slug strings                                                   | enumeration index          |
| `registry.changed` | pubsub | slug string                                                    | artemis cache invalidation |

All writes go through the artemis `POST /api/site/register` / `PATCH /api/site/{slug}` / `DELETE /api/site/{slug}` endpoints. Direct Valkey access is reserved for the one-time hand-import (`scripts/import-sites.sh`) and break-glass operator probes.

## Deploy

```sh
just release gxy-management valkey
```

End-to-end recipe (mint envelope, deploy, verify, import seed data): `docs/flight-manuals/gxy-management.md §C-valkey`.

## One replica, and why

Ruling 2026-09-11. `replicaCount` stays 1 and the PodDisruptionBudget uses `maxUnavailable: 1`.

Do not raise `replicaCount` to 2. The chart has no replication wiring and the `valkey` ClusterIP Service selects every pod by label, so two replicas are two independent servers behind one round-robin Service. The artemis deploy fence would split: `MarkDeployFinalized` writes to one pod and `IsDeployFinalized` reads the other and misses. That is a correctness regression, not high availability.

Real high availability needs Sentinel plus a failover-aware client in artemis. Valkey now holds only the deploy fence, the team cache and the change channel, so Sentinel is the wrong size for it. Revisit when one of those three becomes a source of truth.

`minAvailable: 1` on one replica reports `disruptionsAllowed: 0` and blocks every drain of the node that `local-path` pinned the PVC to. `maxUnavailable: 1` reports 1 and lets the drain proceed. After the artemis readyz ruling (artemis `docs/design/0007-readyz-degradation.md`) a Valkey outage no longer removes artemis from the load balancer, so the eviction is survivable and the permanent drain block is the larger harm.

**Order matters.** The PodDisruptionBudget change is safe only after the artemis release that carries artemis commit `50df4ba`. Until that image is live a Valkey eviction still returns `503` from `/readyz` and ejects every artemis pod. Release artemis first, then valkey.

**A drain still needs care.** The PVC is `local-path` and pinned by node affinity, so an evicted `valkey-0` stays `Pending` until the node returns. Valkey is down for the whole drain, not for a moment. artemis boot also still hard-fails on Valkey, so any artemis pod that restarts during that window crashloops. Follow the drain procedure in `docs/runbooks/12-node-drain-maintenance.md`.
