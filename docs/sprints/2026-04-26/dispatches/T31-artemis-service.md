# T31 — Artemis service implementation (Go microservice)

**Status:** pending
**Worker:** _claim by setting Worker on first commit (e.g., `w-artemis`)_ — multi-session true-parallel mode active
**Repo:** `~/DEV/fCC-U/artemis` (branch: `main`) — empty git repo (only `.git/`); files land in this dispatch
**Spec:** D016 (`~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`) §Architecture + §Authn/authz + §R2 layout + §Amendments (read in full — covers `uploads → artemis` rename + JWT scope clarification)
**Cross-ref:** D43 + 2 dated amendments in sprint `DECISIONS.md`
**Toolchain:** Go 1.26.2 (`/opt/homebrew/bin/go`); chi router; AWS SDK Go v2 for R2; testify
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Naming locks (post-rename 2026-04-26)

| Surface         | Value                                                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------------------------- |
| Repo            | `freeCodeCamp/artemis`                                                                                               |
| Local path      | `~/DEV/fCC-U/artemis/`                                                                                               |
| Go module       | `github.com/freeCodeCamp/artemis`                                                                                    |
| Container image | `ghcr.io/freecodecamp/artemis:<sha>`                                                                                 |
| k3s Deployment  | `artemis`                                                                                                            |
| Helm chart path | `k3s/gxy-management/apps/artemis/` (T34)                                                                             |
| sops envelope   | `infra-secrets/management/artemis.env.enc`                                                                           |
| **Public host** | `uploads.freecode.camp` _(UNCHANGED — describes the verb to end users; repo describes the project to platform team)_ |

## Files to create

```
~/DEV/fCC-U/artemis/
├── .gitignore
├── .editorconfig
├── go.mod                                   # module github.com/freeCodeCamp/artemis
├── go.sum
├── Dockerfile
├── Makefile                                 # tasks: build, test, lint, run, image
├── README.md
├── LICENSE                                  # BSD-3 per fCC convention
├── cmd/
│   └── artemis/
│       └── main.go                          # entrypoint; loads env, starts HTTP server
├── internal/
│   ├── config/
│   │   ├── config.go                        # env-driven config struct
│   │   └── config_test.go
│   ├── auth/
│   │   ├── github.go                        # token validate, team membership probe, 5min cache
│   │   ├── github_test.go
│   │   ├── jwt.go                           # short-lived deploy-session JWTs (HS256, 15min, scope (login,site,deployId))
│   │   └── jwt_test.go
│   ├── sites/
│   │   ├── sites.go                         # sites.yaml loader + fsnotify hot-reload
│   │   └── sites_test.go
│   ├── r2/
│   │   ├── r2.go                            # AWS SDK Go v2 wrapper for R2
│   │   └── r2_test.go
│   ├── handler/
│   │   ├── deploy.go                        # /api/deploy/* handlers
│   │   ├── deploy_test.go
│   │   ├── site.go                          # /api/site/{site}/* handlers
│   │   ├── site_test.go
│   │   ├── whoami.go
│   │   ├── whoami_test.go
│   │   ├── healthz.go
│   │   └── middleware.go                    # auth middleware, request-id, recover
│   └── server/
│       ├── server.go                        # router wiring
│       └── server_test.go
├── config/
│   └── sites.yaml.example                   # example site→teams map
└── .github/
    └── workflows/
        └── ci.yml                           # build + test + image push (ghcr.io/freecodecamp/artemis)
```

## API surface (locked per D016)

```
POST   /api/deploy/init                       → { deployId, jwt, expiresAt }
PUT    /api/deploy/{deployId}/upload          → multipart streaming → R2
POST   /api/deploy/{deployId}/finalize        → { mode } → verify + atomic alias → { url }
POST   /api/site/{site}/promote               → atomic alias swap → { url }
POST   /api/site/{site}/rollback              → { to } → atomic alias write → { url }
GET    /api/site/{site}/deploys               → [{ deployId, ts, sha, size }]
GET    /api/whoami                            → { login, authorizedSites: [...] }
GET    /healthz                               → { ok: true }
```

Auth header on `/api/*` (except `/healthz`):

- `POST /api/deploy/init` + `POST /api/site/*` + `GET /api/*`: `Authorization: Bearer <github_token_or_oidc>` (validated via GH `/user` + team membership probe per ADR-016 Q10/Q11).
- `PUT /api/deploy/{deployId}/upload` + `POST /api/deploy/{deployId}/finalize`: `Authorization: Bearer <deploy_session_jwt>` (HS256, scoped to single `(login, site, deployId)` triple, ≤15min TTL — per ADR-016 Amendments §JWT scope clarification).

## Config (env-driven)

```
PORT                          # default 8080
R2_ENDPOINT                   # https://<account>.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID              # admin S3 key (from infra-secrets/management/artemis.env.enc → k8s Secret)
R2_SECRET_ACCESS_KEY          # paired
R2_BUCKET                     # universe-static-apps-01
GH_CLIENT_ID                  # OAuth app for CLI device flow (operator creates; lands in env)
GH_ORG                        # default freeCodeCamp
GH_API_BASE                   # default https://api.github.com
SITES_YAML_PATH               # default /etc/artemis/sites.yaml
JWT_SIGNING_KEY               # 32-byte random; mounted from k8s Secret
JWT_TTL_SECONDS               # default 900 (15 min)
GH_MEMBERSHIP_CACHE_TTL       # default 300 (5 min)
ALIAS_PRODUCTION_KEY_FORMAT   # default <site>/production
ALIAS_PREVIEW_KEY_FORMAT      # default <site>/preview
DEPLOY_PREFIX_FORMAT          # default <site>/deploys/<ts>-<sha>/
LOG_LEVEL                     # default info
```

## Acceptance criteria

### Test gates (TDD)

- All handlers covered ≥ 80% line-cov via `go test ./... -cover`
- Auth middleware tested with mock GH server (httptest)
- R2 client tested with mock S3 server (`s3:7000` via aws-sdk endpoint override)
- Sites loader tested with temp file + fsnotify reload
- Deploy lifecycle (init → upload → finalize) end-to-end test against mock R2
- Deploy-session JWT: tested for correct `(login, site, deployId)` scope; expired-token reject (401); wrong-deploy-id reject (403); HS256 signature verify

### Behavioral gates

- `GET /healthz` returns `{"ok":true}` with no auth
- `POST /api/deploy/init` rejects missing `Authorization` header (401)
- `POST /api/deploy/init` rejects user not on any authorized team for site (403)
- `POST /api/deploy/init` returns deploy-session JWT scoped to single `(login, site, deployId)`, expires 15 min
- `PUT /api/deploy/{deployId}/upload` rejects expired JWT (401), wrong-deploy JWT (403)
- `POST /api/deploy/{deployId}/finalize` writes alias only after ListObjectsV2 verifies expected files arrived
- `POST /api/site/{site}/promote` is atomic — single PUT to alias key
- `POST /api/site/{site}/rollback` validates target deploy exists in bucket

### Operational gates

- Image builds via `make image` (multi-stage Dockerfile, distroless final)
- `make run` boots locally with `.env` file
- `LICENSE` BSD-3 per fCC convention
- README documents env vars + curl examples for each endpoint

## Out of scope (future)

- Build environment provisioning (proxy doesn't build; CLI uploads pre-built artifacts)
- DNS provisioning (handled separately by infra DNS runbook)
- Per-deploy artifact signing (deferred to post-MVP)
- Webhooks (deferred)
- Site creation/deletion API (operator-driven via sites.yaml edit)
- Auth-session JWT (parked per ADR-016 Amendments §JWT scope clarification — only deploy-session JWT in v1)

## Closure checklist

- [ ] All files listed above present
- [ ] Tests green (`go test ./...`)
- [ ] Coverage ≥ 80% on `internal/handler/`, `internal/auth/`
- [ ] Image builds locally
- [ ] Single commit per dispatch allowed (greenfield repo init); flip Status `pending → done` in same commit
- [ ] T31 dispatch Status `done` (record closing commit SHA)
- [ ] **Worker does NOT touch sprint docs.** Governor session reconciles PLAN matrix row + HANDOFF entry in separate infra commit.
