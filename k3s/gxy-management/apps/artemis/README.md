# artemis — Universe deploy proxy (gxy-management)

Authenticates GitHub OAuth device-flow tokens, validates per-site team membership against the sites registry, mints HS256 deploy-session JWTs, and forwards authorized PUTs to Cloudflare R2 with admin S3 keys held cluster-side. Public surface: `https://uploads.freecode.camp`.

Spec: ADR-016 (Universe deploy proxy).

## Architecture

```
universe CLI / GHA / curl
    │  Bearer <gh-oauth-token>
    ▼
CF proxied (orange) — uploads.freecode.camp
    │  CF Origin → gxy-management public IP
    ▼
Traefik (hostNetwork DaemonSet)
    │  Gateway / HTTPRoute (gatewayClassName: traefik)
    ▼
Service artemis (ClusterIP :8080)
    │
    ▼
Pod artemis (Go binary)
    │  ── auth ── GitHub API (`/user`, team memberships)
    │  ── data ── Cloudflare R2 (S3 API)
    └─── sites registry ── Valkey (`registry.changed` pub-sub + TTL refresh)
```

No Tailscale. No Caddy/cassiopeia hop. No CF Access (programmatic API — GH OAuth Bearer is the auth gate per ADR-016). Compensating controls: Traefik rate-limit middleware (chart-internal) + CF WAF rules on the `freecode.camp` zone.

**TLS:** CF Edge terminates HTTPS using the zone's Universal SSL cert. CF→origin is plain HTTP (Flexible SSL mode on the `freecode.camp` zone — matches the cassiopeia caddy precedent on the same zone). No origin cert at the k8s layer; chart Gateway listens on HTTP :80 only.

## Layout

```
apps/artemis/
├── charts/artemis/
│   ├── Chart.yaml
│   ├── values.yaml             # chart defaults
│   └── templates/
│       ├── _helpers.tpl
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml      # non-secret env only
│       ├── secret-env.yaml     # 6 required + 3 optional secret env vars (sops overlay)
│       ├── middleware-ratelimit.yaml
│       ├── gateway.yaml        # HTTP :80 only — CF Flexible SSL
│       ├── httproute.yaml
│       └── networkpolicy.yaml
├── values.production.yaml      # production overlay (image, replicas, env defaults)
└── README.md                   # (this file)
```

## Deploy

```
just release gxy-management artemis
```

Generic `release` recipe smart-dispatches: `apps/artemis/charts/<chart>/` present → helm phase. Layers values:

1. `charts/artemis/values.yaml` — chart defaults
1. `apps/artemis/values.production.yaml` — production overlay
1. `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc` — sops-sealed (6 required + 3 optional secret env keys; optional triple gates the repo-creation feature)

No `.deploy-flags.sh` hook for artemis post-cutover — the chart no longer mounts a sites ConfigMap. Postgres is the authoritative store since the 2026-09-11 cutover; `universe sites <subcommand>` is the operator surface (see `docs/runbooks/01-deploy-new-constellation-site.md`).

The sops sealed overlay is operator-owned. Mint via the paste-once shell block in `docs/runbooks/02-deploy-artemis-service.md` §5. Re-run on env-var rotation. See runbook for end-to-end operator flow.

No TLS material in the overlay — CF Flexible SSL on `freecode.camp` zone (CF terminates HTTPS, CF→origin plain HTTP).

## Sites registry

Source of truth: the `sites` table in Postgres, since the 2026-09-11 cutover. `cmd/artemis/main.go:426-438` makes `pg.RegistryStore` the Writer and the Reader source when `DATABASE_URL` is set, and leaves Valkey (`valkey.valkey.svc.cluster.local:6379`, namespace `valkey`) as the change transport and the cache front. `internal/registry/valkey/reader.go` holds an in-memory snapshot and refreshes it from Postgres on a `registry.changed` event or on the TTL, so a Valkey outage does not lose registry data.

Valkey is not a hard dependency of readiness **from the artemis release that carries artemis commits `50df4ba` and `9898b91`**; before them, a Valkey ping error returned `503` and ejected the pod. Ruling 2026-09-11: no upstream failure makes `/readyz` return 503. Valkey, R2 and Postgres each set `degraded: true` in a 200 response, so a Valkey outage leaves every pod in the load balancer. Sentry pages instead. The ruling and its evidence are in artemis `docs/design/0007-readyz-degradation.md`. Valkey still holds the deploy fence (`internal/registry/valkey/finalized.go`) and the team cache. From artemis `9898b91` a pod that restarts during a Valkey outage boots degraded instead of crashlooping: deploys return `503 fence_unavailable`, team reads go to the GitHub API, and the registry serves from Postgres on the TTL refresh. The registry API contract — endpoints (`POST`/`PATCH`/`DELETE /api/site*`, `GET /api/sites`), `REGISTRY_AUTHZ_TEAM` authz (default `staff`; reads open to any GitHub bearer), slug rules, and `registry.changed` pub-sub propagation (≤60 s TTL fallback; no pod restart or Helm upgrade) — is canonical in **ADR-016 §Authn-authz**.

`freeCodeCamp/artemis` `config/sites.yaml` is a **dormant cold-start seed** — checked in for cold-recovery reference, not consumed at runtime.

Operator writes go through `universe sites {register,update,rm,ls}` (staff-gated). Full staff/admin flow: `docs/runbooks/01-deploy-new-constellation-site.md`.

## Repo-creation feature

`/api/repo*` (ADR-016 §2026-05-29 amendment) — server-side repo creation in the `freeCodeCamp-Universe` org with an admin approval queue. Replaces the legacy Windmill `repo_mgmt` flow.

Feature is **opt-in** via the sops envelope: supply all three of `GH_APP_ID` + `GH_APP_INSTALLATION_ID` + `GH_APP_PRIVATE_KEY` (the Apollo-11 GitHub App credentials) and artemis mounts the routes at boot. Leave all three blank to keep the routes unmounted (deploy-only deployments unaffected). Partial config is a hard boot-failure.

Two GitHub teams gate the surface (overridable via env, defaults below):

- `REPO_CREATE_AUTHZ_TEAM=staff` — `POST /api/repo` (request a repo)
- `REPO_APPROVE_AUTHZ_TEAM=gh-artemis-approvers` — `POST /api/repo/{id}/{approve,reject}` (prod-canonical; `apollo-11-approvers` was the retired Windmill-era name)

Read routes (`GET /api/repos`, `GET /api/repo/{id}`, `GET /api/repo/templates`) are open to any GitHub bearer.

Trust boundary per ADR-016: the App private key lives in this envelope only — never on staff laptops, never in the CLI. artemis mints the App JWT (RS256) and exchanges for an installation token inline.

## Image / build / pull

GHCR direct: `ghcr.io/freecodecamp/artemis@sha256:<digest>`. Build runs on GitHub Actions on `freeCodeCamp/artemis`. **No zot mirror in pull path** — build- and run-residency rule for Universe pillars (Universe field-note 2026-04-27).

## TLS

CF Edge terminates HTTPS via the zone's Universal SSL cert. CF→origin is plain HTTP (Flexible SSL on `freecode.camp`, matches cassiopeia caddy on the same zone). No origin cert / no per-app cert at the k8s layer. Future flip to Full Strict (origin cert present at Traefik) requires zone-wide change touching cassiopeia caddy too — separate dispatch.

## Verify post-deploy

```
just release gxy-management artemis
kubectl -n artemis rollout status deploy/artemis --timeout=60s
kubectl -n artemis get pods,svc,gateway,httproute
curl -fsS https://uploads.freecode.camp/healthz   # → 200 "ok"
```

E2E smoke: `just verify-artemis`.

## Postgres: the replicated pair

`postgresCluster` declares a CloudNativePG `Cluster` named `artemis-pg`. It is disabled by default. The operator comes from `apps/cnpg-system`.

The name must not be `artemis`. CloudNativePG creates a PodDisruptionBudget with the same name as the `Cluster`, and the chart already owns a PodDisruptionBudget named `artemis` for the deploy-proxy Deployment (`templates/pdb.yaml`). Two owners of one object is a release failure.

It runs beside the legacy `postgres` StatefulSet, not in place of it. The StatefulSet keeps the `hatchet` database until ADR-023 moves it. Do not set `postgres.enabled: false` — that deletes the instance Hatchet still uses.

Five settings carry a ruling of 2026-09-11 and must not change without a new one.

| setting                          | value      | why                                                                                                       |
| -------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------- |
| `podAntiAffinityType`            | `required` | A soft rule is dropped under exactly the scheduling pressure the pair exists to survive.                  |
| `nodeMaintenanceWindow.reusePVC` | `true`     | The operator waits for the drained node to return and re-attaches the same `local-path` volume. It drops its own PodDisruptionBudget while it waits, so the drain completes. `false` instead rebuilds the instance on another node with a new volume. The setting is inert unless `maintenanceInProgress` is `true`, so it governs planned drains only. |
| `enableSuperuserAccess`          | `false`    | The `postgres` role keeps a NULL password. The backup job runs as the owner and exports roles separately. |
| `max_slot_wal_keep_size`         | `2GB`      | An orphaned replication slot would otherwise fill a 10Gi volume that cannot be expanded.                  |
| `smartShutdownTimeout`           | `15`       | The planned failover of 2026-09-11 took 183 seconds against the default of 180, so the smart phase ran its full length. A held pgx connection keeps it open, not slow work. Every artemis write is one short statement. The field does not roll the instances. |

`managed.roles` grants `pg_read_all_stats` to `artemis`. This is an engineering fix, not a ruling. Without it `pg_stat_replication` returns NULL in every LSN column to a non-superuser, and the lag watch reads `lag_bytes=0` forever and never alerts.

The `artemis-pg-app` secret is `kubernetes.io/basic-auth` and carries the encrypted `ARTEMIS_DB_PASSWORD` from the overlay. CloudNativePG would otherwise generate its own password and `DATABASE_URL` would have two owners. The secret username must equal the `initdb` owner.

Ingress on 5432 to the pair is allowed from four sources only: peer instances, the deploy-proxy pods, the `pg-backup` job and the `pg-lag-watch` job. The legacy StatefulSet is not one of them. Move the data at cutover with two `kubectl exec` hops through the API server, not with a direct `psql` from `artemis-postgresql-0`.

The `nodeMaintenanceWindow` block applies only while `inProgress` is `true`. Set `inProgress` before a node drain and clear it after.

The backup job exports role definitions as idempotent `DO` blocks with no password. A restore must set each password again from the sops overlay. `enableSuperuserAccess: false` means the job cannot read `rolpassword`.

The primary moves after a failover. Reach it through the `artemis-pg-rw` service or the label `cnpg.io/instanceRole=primary`. Never name a pod ordinal.

### WAL archiving — ruling 2026-09-11

**The nightly dump is the floor. There is no WAL archive and none is planned for this store.**
`spec.backup` on the `artemis-pg` Cluster is null, so no `barmanObjectStore` and no
`archive_command`. Streaming replication to the standby is not WAL archiving: it protects against
instance loss, not against a logical fault that both instances replay.

RPO is therefore up to 24 hours, bounded by the `artemis-pg-backup` CronJob. RTO for instance loss
is the standby promotion time; RTO for data loss is a restore from the dump.

Four measurements support the ruling.

| measurement | value on 2026-09-11 |
| --- | --- |
| `artemis` database size | 12 MB |
| `pg_wal` on the primary | 561 MB |
| filesystem the PVC sits on | 309 G total, 275 G free |
| `spec.backup` | null |

- **The data does not justify it.** A 12 MB database restores from a dump in seconds. WAL-continuous
  buys an RPO of 5 minutes instead of 24 hours on the registry, the deploy index, the outbox and the
  audit log.
- **Most of a lost day is recoverable elsewhere.** Deploy bytes live in R2, and the nightly
  `drift-detect` sweep re-indexes what the index lost. The registry rows are the part that is not
  recoverable, and they change on the order of once a week.
- **It would add a failure mode this wave exists to remove.** With a `barmanObjectStore`, a failing
  `archive_command` holds WAL segments on the data volume until the archive drains. `local-path` is
  hostPath-backed with no quota — `df` inside the pod reports the node's 309 G filesystem, not the
  declared `10Gi` — so an R2 outage would fill the **node** disk and take down every pod on that
  node, not only Postgres. `max_slot_wal_keep_size: 2GB` bounds what a replication slot retains. It
  does not bound an archive backlog.
- **The ADR already says so.** ADR-019's 2026-09-11 amendment records that the GA floor for this
  store is no longer `RPO <= 5 min`; the operator ruling in ADR-023 §Database sets a daily RPO and
  an RTO equal to the standby promotion time.

Revisit when one of these changes: the database outgrows a dump-and-restore window, a storage class
with an enforced quota and volume expansion replaces `local-path`, or a `walStorage` volume with its
own bounded retention is added.

### Release order

Release `cnpg-system` first. The artemis chart declares a `Cluster`, and the CRD does not exist until the operator is installed.

```sh
just release gxy-management cnpg-system
just release gxy-management artemis
```

### The four production flags

| flag                      | value   | meaning                                                                            |
| ------------------------- | ------- | ---------------------------------------------------------------------------------- |
| `postgres.enabled`        | `true`  | The legacy StatefulSet. It still holds the `hatchet` database. Never set it false. |
| `postgresCluster.enabled` | `true`  | The pair runs.                                                                     |
| `postgresCluster.cutover` | `false` | `DATABASE_URL` still points at the StatefulSet.                                    |
| `pgBackup.enabled`        | `true`  | `pg_dump` of `artemis` to `artemis/<galaxy>/pg/` in R2.                            |

While `cutover` is `false` the pair runs empty and artemis keeps talking to the StatefulSet. Bringing the pair up is reversible by deleting the `Cluster`.

Setting `postgres.enabled: false` deletes the instance Hatchet uses, and also drops the hatchet gRPC egress rule in `networkpolicy.yaml` — the rule sits inside that same conditional. The hatchet move is the ADR-023 successor wave.

The cutover flips `cutover` to `true` and points `DATABASE_URL` at `artemis-pg-rw` with `sslmode=require`. `verify-full` needs the CloudNativePG CA mounted into the Deployment and is a separate change.
