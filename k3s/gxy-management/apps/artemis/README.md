# artemis — Universe deploy proxy (gxy-management)

Authenticates GitHub OAuth device-flow tokens, validates per-site team membership against the Valkey-backed sites registry, mints HS256 deploy-session JWTs, and forwards authorized PUTs to Cloudflare R2 with admin S3 keys held cluster-side. Public surface: `https://uploads.freecode.camp`.

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

No `.deploy-flags.sh` hook for artemis post-cutover — the chart no longer mounts a sites ConfigMap. The Valkey registry is the authoritative store; `universe sites <subcommand>` is the operator surface (see `docs/runbooks/01-deploy-new-constellation-site.md`).

The sops sealed overlay is operator-owned. Mint via the paste-once shell block in `docs/runbooks/02-deploy-artemis-service.md` §5. Re-run on env-var rotation. See runbook for end-to-end operator flow.

No TLS material in the overlay — CF Flexible SSL on `freecode.camp` zone (CF terminates HTTPS, CF→origin plain HTTP).

## Sites registry

Source of truth: Valkey (`valkey.valkey.svc.cluster.local:6379`, namespace `valkey`). The registry API contract — endpoints (`POST`/`PATCH`/`DELETE /api/site*`, `GET /api/sites`), `REGISTRY_AUTHZ_TEAM` authz (default `staff`; reads open to any GitHub bearer), slug rules, and `registry.changed` pub-sub propagation (≤60 s TTL fallback; no pod restart or Helm upgrade) — is canonical in **ADR-016 §Authn-authz**.

`freeCodeCamp/artemis` `config/sites.yaml` is a **dormant cold-start seed** — checked in for cold-recovery reference, not consumed at runtime.

Operator writes go through `universe sites {register,update,rm,ls}` (staff-gated). Full staff/admin flow: `docs/runbooks/01-deploy-new-constellation-site.md`.

## Repo-creation feature

`/api/repo*` (ADR-016 §2026-05-29 amendment) — server-side repo creation in the `freeCodeCamp-Universe` org with an admin approval queue. Replaces the legacy Windmill `repo_mgmt` flow.

Feature is **opt-in** via the sops envelope: supply all three of `GH_APP_ID` + `GH_APP_INSTALLATION_ID` + `GH_APP_PRIVATE_KEY` (the Apollo-11 GitHub App credentials) and artemis mounts the routes at boot. Leave all three blank to keep the routes unmounted (deploy-only deployments unaffected). Partial config is a hard boot-failure.

Two GitHub teams gate the surface (overridable via env, defaults below):

- `REPO_CREATE_AUTHZ_TEAM=staff` — `POST /api/repo` (request a repo)
- `REPO_APPROVE_AUTHZ_TEAM=apollo-11-approvers` — `POST /api/repo/{id}/{approve,reject}`

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
