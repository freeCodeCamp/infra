# Valkey — registry KV substrate

In-cluster Valkey backing the static-apps registry consumed by artemis (`/api/site/register`, `/api/sites`, `/api/site/{slug}` PATCH/DELETE).

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
│       ├── pdb.yaml             # minAvailable 1
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
