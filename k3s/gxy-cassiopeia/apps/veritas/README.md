# veritas — freeCodeCamp account service (gxy-cassiopeia)

BetterAuth-powered IdP, account app and developer console. Three public surfaces on the `freecodecamp.org` zone:

- `https://login.freecodecamp.org` — IdP (sign-in flows, OIDC discovery, `/api/auth/oauth2/authorize`, JWKS)
- `https://account.freecodecamp.org` — account app + user-data API (`/api/me`, `/api/profile`, sessions, connected apps; opaque scoped bearer)
- `https://auth-console.freecodecamp.org` — developer console + control API (`/api/control/*`, one-time `/internal/bootstrap`)

Backed by CNPG-managed Postgres in the same namespace (`veritas-pg`, primary + 1 replica), R2 WAL archive (`cassiopeia-cnpg-backups`).

Spec: ADR-004 (auth-identity) + ADR-019 (cassiopeia-shared-services).

## Architecture

```
relying-party SPA / mobile / curl
    │  OAuth code+PKCE → opaque bearer
    ▼
CF proxied (orange) — login + account + auth-console .freecodecamp.org
    │  CF Origin → gxy-cassiopeia public IP
    ▼
Traefik (hostNetwork DaemonSet)
    │  Gateway (3 listeners) / HTTPRoute (1 per hostname)
    │  gatewayClassName: traefik
    ▼
Service veritas (ClusterIP :3000)
    │
    ▼
Pod veritas (Node 24 distroless, BetterAuth + Hono)
    │  ── DB ──── CNPG primary (veritas-pg-rw :5432)
    │  ── auth ── Google / GitHub / Apple OAuth (egress pair-gated), passkeys
    │  ── email ─ AWS SES SMTP :587 STARTTLS (magic link, OTP, new-device notice)
    └── migrate ─ Helm hook Job runs dist/migrate.js from the same image
```

No Caddy hop. No Tailscale. Public surface goes through CF → Traefik gateway → veritas. Compensating controls: Traefik rate-limit middleware (chart-internal) + CF WAF on the `freecodecamp.org` zone.

**TLS:** CF Edge terminates client HTTPS with Universal SSL. CF→origin is HTTPS with cert validation (Full/Strict SSL on `freecodecamp.org` zone — owning team chose Strict per UNIVERSE.md §1.1). Origin cert mounted as the `veritas-tls` Secret on the Gateway HTTPS :443 listeners; PEM material supplied via sops overlay. Distinct from cassiopeia caddy + management artemis precedent (those are on `freecode.camp` zone, Flexible SSL).

## Layout

```
apps/veritas/
├── charts/veritas/
│   ├── Chart.yaml
│   ├── values.yaml                  # chart defaults
│   └── templates/
│       ├── _helpers.tpl
│       ├── namespace.yaml            # PSS restricted
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── configmap.yaml            # non-secret env (15 keys + SMTP_* when smtp, PASSKEY_RP_ID when set, VALKEY_URL when valkey.deploy=true)
│       ├── secret-env.yaml           # app secret env (sealed overlay; Google/GitHub/Apple/SMTP pair-gated, INTERNAL_API_TOKEN + SENTRY_DSN + VALKEY_URL conditional)
│       ├── secret-cnpg-r2.yaml       # CNPG backup R2 creds (sops overlay; staging gated off)
│       ├── secret-tls.yaml           # origin cert + key for Full/Strict (sops overlay)
│       ├── gateway.yaml              # HTTPS :443 only — 3 TLS-terminate listeners (login + account + console)
│       ├── httproute-login.yaml      # login.freecodecamp.org → veritas Service
│       ├── httproute-account.yaml    # account.freecodecamp.org → veritas Service
│       ├── httproute-console.yaml    # auth-console.freecodecamp.org → veritas Service
│       ├── middleware-secure-headers.yaml
│       ├── middleware-ratelimit.yaml
│       ├── networkpolicy.yaml        # CiliumNetworkPolicy (Cilium CNI; SES + relying-party egress values-driven)
│       ├── job-migrate.yaml          # Helm hook Job: drizzle migrations (post-install, pre-upgrade)
│       ├── valkey.yaml               # in-namespace Valkey (valkey.deploy=true)
│       ├── cnpg-cluster.yaml         # postgresql.cnpg.io/v1 Cluster (2 instances)
│       └── cnpg-scheduledbackup.yaml # daily 04:00 UTC full backup
├── values.production.yaml            # production overlay (image pin, replicas, env, CNPG sizing)
├── secrets/
│   └── veritas.values.yaml.enc.template  # SHAPE for the sops envelope
└── README.md                         # (this file)
```

## Deploy

```sh
just release gxy-cassiopeia veritas
```

Generic `release` recipe smart-dispatches: `apps/veritas/charts/veritas/` present → helm phase. Layers values:

1. `charts/veritas/values.yaml` — chart defaults
1. `apps/veritas/values.production.yaml` — production overlay (image digest pin)
1. `infra-secrets/k3s/gxy-cassiopeia/veritas.values.yaml.enc` — sops sealed (app secretEnv + CNPG R2 creds)

`.deploy-flags.sh` adds `--timeout 10m` so the migration Job's initContainer can wait for the CNPG primary on a first install (Helm deletes the Job on success). Chart uses the local path (`charts/veritas/`), no upstream registry.

The sops sealed envelope is operator-owned. See `secrets/veritas.values.yaml.enc.template` for the schema. Mint via paste-once shell block in `docs/runbooks/deploy-veritas-service.md` (TBD next dossier).

## CNPG cluster

The chart creates a `postgresql.cnpg.io/v1` Cluster CR in the veritas namespace:

- 2 instances (primary + 1 sync replica) — ADR-019 T1+T2 floor (RPO ≤ 5min, RTO ≤ 60min)
- 10Gi local-path PV per instance (k3s default storageClass)
- App user `veritas` owns database `veritas` (DDL allowed for the drizzle migration Job)
- App reads DATABASE_URL from CNPG-generated `veritas-pg-app` Secret via `secretKeyRef`

Backup → Barman Cloud → R2 `cassiopeia-cnpg-backups/veritas/`:

- WAL archive: continuous, gzipped (PITR support)
- Full backup: daily 04:00 UTC (ScheduledBackup CR, off-peak vs FRA1 + IST)
- Retention: 30 days

R2 credentials live in the sops envelope (`cnpgR2.{endpoint,accessKeyId,secretAccessKey}`). Operator mints a bucket-scoped R2 token (NOT the `r2-gxy` admin token) in CF R2 dashboard.

Restore drill (E5 from v0-build §G deferred registry — separate dossier).

## Image / build / pull

GHCR direct. The production pin has the shape `sha-<full git sha>@sha256:<digest>` (tag plus digest; the digest wins); staging follows the moving `main` tag. Build runs on GitHub Actions in `freeCodeCamp/veritas` (`.github/workflows/docker-ghcr.yml`). First image (`0.1.0`) was built locally + pushed via `docker buildx` per veritas-v0-deploy C1 gate; CD activates on first tag push post-deploy.

## TLS

CF Edge terminates client HTTPS via the zone's Universal SSL cert. CF→origin is HTTPS with cert validation (Full/Strict SSL on `freecodecamp.org` zone — per the .org owning team's policy; UNIVERSE.md §1.1 marks the zone as "separate fCC scope; not Universe"). Chart Gateway listens HTTPS :443 only — origin certificate + key mounted as the `veritas-tls` k8s Secret (`kubernetes.io/tls`), values supplied via the sops overlay. The certificate is the wildcard CF Origin certificate for the zone (`*.freecodecamp.org`, 15-year, only valid via CF proxy), which covers login, account and auth-console. No HTTP :80 listener — CF Full/Strict never hits it.

## Verify post-deploy

```sh
just release gxy-cassiopeia veritas
kubectl -n veritas rollout status deploy/veritas --timeout=60s
kubectl -n veritas get pods,svc,gateway,httproute,clusters.postgresql.cnpg.io,scheduledbackup.postgresql.cnpg.io
kubectl -n veritas get backup.postgresql.cnpg.io  # first full backup
curl -fsS https://login.freecodecamp.org/healthz   # → 200 "ok"
curl -fsS https://account.freecodecamp.org/healthz # → 200 "ok"
curl -fsS https://auth-console.freecodecamp.org/healthz # → 200 "ok"
curl -fsS https://login.freecodecamp.org/metrics   # → 404 (V7 public-block contract)
```

E2E auth smoke: extend `apps/api/tests/smoke.test.ts` against deployed URL (T7 (a)).
