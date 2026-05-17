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
│       ├── secret-env.yaml     # 5 secret env vars (sops overlay)
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
1. `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc` — sops-sealed (5 secret env keys)

No `.deploy-flags.sh` hook for artemis post-cutover — the chart no longer mounts a sites ConfigMap. The Valkey registry is the authoritative store; `universe sites <subcommand>` is the operator surface (see `docs/runbooks/01-deploy-new-constellation-site.md`).

The sops sealed overlay is operator-owned. Mint via the paste-once shell block in `docs/runbooks/deploy-artemis-service.md` §5. Re-run on env-var rotation. See runbook for end-to-end operator flow.

No TLS material in the overlay — CF Flexible SSL on `freecode.camp` zone (CF terminates HTTPS, CF→origin plain HTTP).

## Sites registry

Source of truth: Valkey (`valkey.valkey.svc.cluster.local:6379`, namespace `valkey`). Mutated via the artemis registry endpoints (`POST /api/site/register`, `PATCH /api/site/{slug}`, `DELETE /api/site/{slug}`), gated on `staff` team membership (`REGISTRY_AUTHZ_TEAM` env, default `staff`). Reads (`GET /api/sites`) open to any GitHub bearer.

`freeCodeCamp/artemis` `config/sites.yaml` is a **dormant cold-start seed** — checked in for cold-recovery reference, not consumed at runtime. Editing it does not register anything live.

Updates (staff):

```bash
universe sites register <slug> --team <team>[,<team>...]
universe sites update   <slug> --team <team>[,<team>...]
universe sites rm       <slug>
universe sites ls       [--mine]
```

All artemis replicas pick up writes via `registry.changed` pub-sub within seconds; ≤60 s on the TTL fallback. No pod restart, no Helm upgrade. Full staff/admin flow: `docs/runbooks/01-deploy-new-constellation-site.md`.

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
