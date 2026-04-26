# T34 — Caddy reverse proxy + DNS prep + smoke retarget

**Status:** pending
**Worker:** w-infra (multi-session true-parallel — T34 worker session; shares repo with governor)
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** D016 §Operational surface + 2026-04-26 amend (`uploads → artemis` rename) + 2026-04-26 amend (deploy-session JWT in v1) + 2026-04-27 amend (CLI namespace `static`)
**Cross-ref:** D43 amendment in sprint `DECISIONS.md`
**Toolchain:** Helm + Caddy + ansible; existing infra recipes
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Naming locks (post-rename 2026-04-26)

| Surface         | Value                                      |
| --------------- | ------------------------------------------ |
| Service         | `artemis` (Go svc; T31 done at `861e4c4`)  |
| k3s Deployment  | `artemis`                                  |
| Helm chart path | `k3s/gxy-management/apps/artemis/`         |
| Container image | `ghcr.io/freecodecamp/artemis:<sha>`       |
| sops envelope   | `infra-secrets/management/artemis.env.enc` |
| Public host     | `uploads.freecode.camp` _(unchanged)_      |
| Caddy upstream  | Tailscale name to gxy-management k3s svc   |

## Galaxy placement — locked **Option A (gxy-management)**

`uploads.freecode.camp` → CF proxied → Caddy on gxy-cassiopeia
(existing) → reverse-proxy via Tailscale to artemis svc on
gxy-management. gxy-management already runs Windmill + Zot;
artemis is low-overhead Go binary. Cross-galaxy hop accepted —
serve plane (Caddy + R2) stays on cassiopeia for role clarity.

(Pre-lock options B / C lived in earlier draft; archived in HANDOFF.)

## Files to touch

```
infra/
├── k3s/gxy-management/
│   └── apps/artemis/
│       ├── chart/                      # Helm chart for artemis svc
│       │   ├── Chart.yaml
│       │   ├── values.production.yaml
│       │   └── templates/
│       │       ├── deployment.yaml
│       │       ├── service.yaml
│       │       ├── secret.yaml         # env source (sealed via sops)
│       │       └── configmap.yaml      # sites.yaml mounted file
│       └── README.md
├── k3s/gxy-cassiopeia/apps/caddy/      # update Caddy chart values
│   └── values.production.yaml          # add uploads.freecode.camp upstream rule
├── ansible/playbooks/
│   └── play-artemis-deploy.yml         # generic deploy playbook (if recipe needs it)
├── justfile                            # add `just artemis-deploy` recipe (or reuse helm-upgrade)
└── docs/
    ├── runbooks/
    │   └── deploy-artemis-service.md   # NEW — operator runbook (DNS + OAuth + sops + helm)
    └── flight-manuals/
        └── gxy-management.md           # add artemis service section
```

## Operator preconditions (ClickOps; do BEFORE worker fires)

These four steps land state outside git that the worker will then
consume. Bundle = "ready to dispatch T34" gate.

### 1. CF DNS — `uploads.freecode.camp` A record

- CF DNS → `freecode.camp` zone → add A record `uploads.freecode.camp`
  → gxy-management public IP
- Proxied (orange cloud)
- SSL Full (Strict) — origin cert `*.freecode.camp` already issued
- TTL auto

### 2. GitHub OAuth App — `Universe CLI`

freeCodeCamp org → Settings → Developer settings → OAuth Apps → New:

- Name: `Universe CLI`
- Homepage URL: `https://uploads.freecode.camp`
- Application description: `freeCodeCamp Universe deploy CLI`
- Authorization callback URL: `https://uploads.freecode.camp/oauth/callback` _(unused for device flow but field is required)_
- **Enable Device Flow** ✅
- Capture `client_id` → land in:
  - `infra-secrets/management/artemis.env.enc` as `GH_CLIENT_ID`
  - universe-cli build constant (T32 worker scope)

### 3. artemis CI — first GHCR image

```
gh workflow run ci.yml --repo freeCodeCamp/artemis --ref main
```

Tag: `ghcr.io/freecodecamp/artemis:<sha>` — pin in
`values.production.yaml`. Re-run on every artemis `main` push.

### 4. sops envelope — `infra-secrets/management/artemis.env.enc`

Seal with operator's age key:

```
R2_ENDPOINT=https://<account>.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=<admin S3 key>
R2_SECRET_ACCESS_KEY=<paired>
R2_BUCKET=universe-static-apps-01
GH_CLIENT_ID=<from step 2>
GH_ORG=freeCodeCamp
JWT_SIGNING_KEY=<32-byte random — `openssl rand -hex 32`>
JWT_TTL_SECONDS=900
GH_MEMBERSHIP_CACHE_TTL=300
LOG_LEVEL=info
```

Helm chart consumes via sealed Secret template.

### 5. sites.yaml seed — initial team→site map

Land alongside artemis chart as ConfigMap source. Initial seed (operator
edits per actual freeCodeCamp team slugs):

```yaml
sites:
  example-site:
    teams: ["platform"]
```

Mount path inside pod: `/etc/artemis/sites.yaml` (default per T31 dispatch
`SITES_YAML_PATH`).

---

When all 5 done → fire T34 worker (resume prompt in STATUS).

## Caddy reverse proxy snippet (cassiopeia caddy chart values)

```yaml
# k3s/gxy-cassiopeia/apps/caddy/values.production.yaml — addition
caddy:
  config:
    routes:
      - match:
          host: ["uploads.freecode.camp"]
        handle:
          - handler: reverse_proxy
            upstreams:
              - dial: "artemis.management.tailscale.fcc:8080"
            transport:
              protocol: http
            headers:
              request:
                set:
                  X-Forwarded-Host: ["{http.request.host}"]
                  X-Forwarded-Proto: ["{http.request.scheme}"]
```

(Tailscale upstream name follows existing cross-galaxy pattern; verify
exact form from running gxy-management Tailscale advert before committing.)

## Smoke retarget

Existing `scripts/phase4-test-site-smoke.sh` writes objects directly to
R2 via admin S3 keys. Retarget for proxy model:

```
scripts/phase5-proxy-smoke.sh           # NEW — exercises artemis E2E
```

Flow:

1. Resolve identity via `gh auth token`
2. POST `/api/deploy/init` → capture deploy-session JWT (HS256, 15min, scope `(login,site,deployId)` per ADR amend 2026-04-26)
3. PUT test files via multipart upload (Authorization: Bearer <deployJwt>)
4. POST `/api/deploy/{id}/finalize?mode=preview`
5. Curl `https://test.preview.freecode.camp/` → assert 200 + content match
6. POST `/api/site/test/promote` (re-auth via GH token; deployJwt scope ends at finalize)
7. Curl `https://test.freecode.camp/` → assert 200
8. Cleanup: rollback to old preview (or trap delete via admin keys)

## Acceptance criteria

- Helm chart deploys artemis svc, pod runs, `/healthz` 200
- Caddy serves `uploads.freecode.camp` → artemis svc (Tailscale upstream)
- DNS resolves; CF Full Strict OK; `*.freecode.camp` cert covers
- Smoke script green E2E (init → upload → finalize → preview curl → promote → prod curl)

## Out of scope (operator owns)

- 5 operator preconditions above (DNS / OAuth / image / sops / sites.yaml)
- Helm install (operator runs `just helm-upgrade gxy-management artemis`)
- Smoke run (operator runs after deploy)

## Closure checklist

- [ ] Helm chart files landed
- [ ] Caddy values updated
- [ ] Smoke script landed
- [ ] Runbook landed
- [ ] Flight-manual section added
- [ ] T34 Status `done`
- [ ] PLAN matrix row checked
- [ ] HANDOFF entry appended
