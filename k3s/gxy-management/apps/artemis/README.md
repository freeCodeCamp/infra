# artemis — Universe deploy proxy (gxy-management)

Authenticates GitHub OAuth device-flow tokens, validates per-site team
membership against `config/sites.yaml` (loaded from
`freeCodeCamp/artemis` repo), mints HS256 deploy-session JWTs, and
forwards authorized PUTs to Cloudflare R2 with admin S3 keys held
cluster-side. Public surface: `https://uploads.freecode.camp`.

Spec: ADR-016 (Universe deploy proxy). Sprint dispatch: `T34-caddy-dns-smoke`.

## Architecture (Path X — 2026-04-27 reframe)

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
    └─── reads sites.yaml from ConfigMap (fsnotify hot-reload)
```

No Tailscale. No Caddy/cassiopeia hop. No CF Access (programmatic API
— GH OAuth Bearer is the auth gate per ADR-016). Compensating
controls: Traefik rate-limit middleware (chart-internal) + CF WAF
rules on the `freecode.camp` zone.

**TLS:** CF Edge terminates HTTPS using the zone's Universal SSL
cert. CF→origin is plain HTTP (Flexible SSL mode on the
`freecode.camp` zone — matches the cassiopeia caddy precedent on
the same zone). No origin cert at the k8s layer; chart Gateway
listens on HTTP :80 only.

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
│       ├── configmap.yaml      # env + sites.yaml
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
just deploy gxy-management artemis
```

Generic `deploy` recipe smart-dispatches: `apps/artemis/charts/<chart>/`
present → helm phase. Layers values:

1. `charts/artemis/values.yaml` — chart defaults
2. `apps/artemis/values.production.yaml` — production overlay
3. `infra-secrets/k3s/gxy-management/artemis.values.yaml.enc` — sops-sealed (5 secret env keys)

`apps/artemis/.deploy-flags.sh` is sourced; appends `--set-file sites=$ARTEMIS_REPO/config/sites.yaml` to the helm invocation. Operator never types the path. Default `ARTEMIS_REPO=$HOME/DEV/fCC-U/artemis`.

The sops sealed overlay is operator-owned. Mint via the paste-once
shell block in `docs/runbooks/deploy-artemis-service.md` §5. Re-run
on env-var rotation. See runbook for end-to-end operator flow.

No TLS material in the overlay — CF Flexible SSL on `freecode.camp`
zone (CF terminates HTTPS, CF→origin plain HTTP).

## Sites map (`sites.yaml`)

Source of truth: `freeCodeCamp/artemis` repo `config/sites.yaml` (PR-
reviewed by platform team, per ADR-016 §sites.yaml lifecycle).
Materialized into a ConfigMap by the chart at deploy time via
`--set-file sites=$ARTEMIS_REPO/config/sites.yaml` (injected by
`apps/artemis/.deploy-flags.sh`).

Updates:

1. PR to `freeCodeCamp/artemis` `config/sites.yaml` → review → merge.
2. `git -C ~/DEV/fCC-U/artemis pull --ff-only`
3. `just deploy gxy-management artemis` — re-renders ConfigMap,
   fsnotify reload (≤1min). No pod restart.

## Image / build / pull

GHCR direct: `ghcr.io/freecodecamp/artemis@sha256:<digest>`. Build
runs on GitHub Actions on `freeCodeCamp/artemis`. **No zot mirror in
pull path** — build- and run-residency rule for Universe pillars
(Universe field-note 2026-04-27).

## TLS

CF Edge terminates HTTPS via the zone's Universal SSL cert.
CF→origin is plain HTTP (Flexible SSL on `freecode.camp`, matches
cassiopeia caddy on the same zone). No origin cert / no per-app
cert at the k8s layer. Future flip to Full Strict (origin cert
present at Traefik) requires zone-wide change touching cassiopeia
caddy too — separate dispatch.

## Verify post-deploy

```
just deploy gxy-management artemis
kubectl -n artemis rollout status deploy/artemis --timeout=60s
kubectl -n artemis get pods,svc,gateway,httproute
curl -fsS https://uploads.freecode.camp/healthz   # → 200 "ok"
```

E2E smoke: `just phase5-smoke` (see `scripts/phase5-proxy-smoke.sh`).
