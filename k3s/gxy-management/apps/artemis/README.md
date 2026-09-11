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

Valkey is still a hard dependency of readiness. `internal/handler/readyz.go:56-61` returns 503 when the Valkey ping fails, before the degraded branch that R2 and Postgres use, so a Valkey outage removes every pod from the load balancer. Valkey also holds the deploy fence (`internal/registry/valkey/finalized.go`) and the team cache. The registry API contract — endpoints (`POST`/`PATCH`/`DELETE /api/site*`, `GET /api/sites`), `REGISTRY_AUTHZ_TEAM` authz (default `staff`; reads open to any GitHub bearer), slug rules, and `registry.changed` pub-sub propagation (≤60 s TTL fallback; no pod restart or Helm upgrade) — is canonical in **ADR-016 §Authn-authz**.

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

Four settings carry a ruling of 2026-09-11 and must not change without a new one.

| setting                          | value      | why                                                                                                       |
| -------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------- |
| `podAntiAffinityType`            | `required` | A soft rule is dropped under exactly the scheduling pressure the pair exists to survive.                  |
| `nodeMaintenanceWindow.reusePVC` | `true`     | The operator waits for the drained node to return and re-attaches the same `local-path` volume. It drops its own PodDisruptionBudget while it waits, so the drain completes. `false` instead rebuilds the instance on another node with a new volume. The setting is inert unless `maintenanceInProgress` is `true`, so it governs planned drains only. |
| `enableSuperuserAccess`          | `false`    | The `postgres` role keeps a NULL password. The backup job runs as the owner and exports roles separately. |
| `max_slot_wal_keep_size`         | `2GB`      | An orphaned replication slot would otherwise fill a 10Gi volume that cannot be expanded.                  |

`managed.roles` grants `pg_read_all_stats` to `artemis`. This is an engineering fix, not a ruling. Without it `pg_stat_replication` returns NULL in every LSN column to a non-superuser, and the lag watch reads `lag_bytes=0` forever and never alerts.

The `artemis-pg-app` secret is `kubernetes.io/basic-auth` and carries the encrypted `ARTEMIS_DB_PASSWORD` from the overlay. CloudNativePG would otherwise generate its own password and `DATABASE_URL` would have two owners. The secret username must equal the `initdb` owner.

Ingress on 5432 to the pair is allowed from four sources only: peer instances, the deploy-proxy pods, the `pg-backup` job and the `pg-lag-watch` job. The legacy StatefulSet is not one of them. Move the data at cutover with two `kubectl exec` hops through the API server, not with a direct `psql` from `artemis-postgresql-0`.

The `nodeMaintenanceWindow` block applies only while `inProgress` is `true`. Set `inProgress` before a node drain and clear it after.

The backup job exports role definitions as idempotent `DO` blocks with no password. A restore must set each password again from the sops overlay. `enableSuperuserAccess: false` means the job cannot read `rolpassword`.

The primary moves after a failover. Reach it through the `artemis-pg-rw` service or the label `cnpg.io/instanceRole=primary`. Never name a pod ordinal.

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
