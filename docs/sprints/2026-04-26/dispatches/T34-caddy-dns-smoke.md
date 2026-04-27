# T34 — Caddy reverse proxy + DNS prep + smoke retarget

**Status:** done
**Worker:** w-infra (multi-session true-parallel — T34 worker session; shares repo with governor)
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** D016 §Operational surface + 2026-04-26 amend (`uploads → artemis` rename) + 2026-04-26 amend (deploy-session JWT in v1) + 2026-04-27 amend (CLI namespace `static`) + 2026-04-27 reframe (Path X — drop Tailscale + Caddy/cassiopeia hop, see DECISIONS D43 amend block)
**Cross-ref:** D43 amendment in sprint `DECISIONS.md`
**Toolchain:** Helm + ansible; existing infra recipes
**Started:** 2026-04-27
**Closed:** 2026-04-27
**Closing commit(s):** `0b8d6238` — `feat(artemis): close T34 — chart + Path X reframe`

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

## Galaxy placement — locked **Option A (gxy-management)** — 2026-04-27 reframe

**Reframe (2026-04-27, T34 worker):** original wording proposed
`uploads → CF → Caddy/cassiopeia → Tailscale → artemis/management`.
Operator (mrugesh, 2026-04-27) flagged the Tailscale leg conflicts
with **ADR-009** ("Tailscale Operator rejected — node-level only").
gxy-management runs no Tailscale Operator; the proposed
`artemis.management.tailscale.fcc:8080` MagicDNS hostname does not
exist. **Reframe:** drop the Caddy/cassiopeia hop entirely. Use the
**windmill / zot / argocd pattern**: each gxy-management app exposes
itself directly via its own Gateway + HTTPRoute (Traefik
gatewayClassName) on its own public hostname.

**New path (Path X — locked):**

```
uploads.freecode.camp
    → CF proxied (orange cloud)
    → CF Origin → gxy-management public IP (Traefik hostNetwork)
    → Gateway (artemis-gateway, ns artemis, sectionName: websecure)
    → HTTPRoute (artemis-route, hostname uploads.freecode.camp)
    → Service artemis (ClusterIP, port 8080)
    → Pod artemis (Go binary)
```

No Caddy-cassiopeia in path. No Tailscale in path. No cross-galaxy
hop. Same shape as `windmill.freecodecamp.net`,
`registry.freecodecamp.net`, `argocd.freecodecamp.net` — except on
the `freecode.camp` zone instead of `freecodecamp.net`.

**Cassiopeia Caddy untouched.** Caddy continues serving
`*.freecode.camp` (sites + previews via R2 alias). It does not see
`uploads.freecode.camp` traffic.

(Pre-lock options B / C lived in earlier draft; archived in HANDOFF.)

## Files to touch (Path X reframe — 2026-04-27)

```
infra/
├── k3s/gxy-management/
│   └── apps/artemis/
│       ├── charts/artemis/             # Helm chart (we own — no upstream)
│       │   ├── Chart.yaml
│       │   ├── values.yaml             # defaults (chart-internal)
│       │   └── templates/
│       │       ├── _helpers.tpl
│       │       ├── deployment.yaml
│       │       ├── service.yaml        # ClusterIP :8080
│       │       ├── configmap.yaml      # sites.yaml + non-secret env
│       │       ├── secret-env.yaml     # 5 secret env vars (sops overlay)
│       │       ├── secret-tls.yaml     # CF Origin cert (sops overlay)
│       │       ├── gateway.yaml        # Gateway API (Traefik) — web + websecure listeners
│       │       ├── httproute.yaml      # web→redirect-https + websecure→Service
│       │       ├── namespace.yaml
│       │       └── networkpolicy.yaml
│       ├── values.production.yaml      # production overlay (image, replicas, defaulted env)
│       └── README.md
├── (NO change to k3s/gxy-cassiopeia/apps/caddy/) — Path X reframe
├── justfile                            # add `mirror-artemis-secrets` recipe (dotenv → yaml overlay one-time)
├── scripts/
│   └── phase5-proxy-smoke.sh           # NEW — E2E artemis smoke (init/upload/finalize/promote)
└── docs/
    ├── runbooks/
    │   └── deploy-artemis-service.md   # NEW — operator runbook (DNS + OAuth + cert mint + sops + helm)
    └── flight-manuals/
        └── gxy-management.md           # add artemis service section + cluster-rebuild step

infra-secrets/  (operator one-time, separate repo)
└── k3s/gxy-management/
    ├── artemis.values.yaml.sample      # NEW — schema reference (commit)
    └── artemis.values.yaml.enc         # NEW — sops-sealed (operator-mints; commit)
```

**Single sealed envelope going forward.** The legacy
`infra-secrets/management/artemis.env.enc` (dotenv) becomes a SOT
**reference only** for env-mint provenance / local-dev / artemis docker-
compose. Helm consumes the new YAML overlay at
`infra-secrets/k3s/gxy-management/artemis.values.yaml.enc` via the
existing `helm-upgrade` recipe. The new `just mirror-artemis-secrets`
recipe converts dotenv → YAML overlay one-time so operator does not
re-mint values. Drift-prevention parked at TODO-park §Application
config (single-envelope unification).

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

Sample template lives at `infra-secrets/management/artemis.env.sample`
(15 vars, full mint-where + format + rotation docs per var). Operator
flow:

```
cp infra-secrets/management/artemis.env.sample \
   infra-secrets/management/artemis.env
# fill 5 REQUIRED secret values:
#   R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY,
#   GH_CLIENT_ID, JWT_SIGNING_KEY (`openssl rand -hex 32`)
# defaults already set: R2_BUCKET, GH_ORG, GH_API_BASE,
#   SITES_YAML_PATH, JWT_TTL_SECONDS, GH_MEMBERSHIP_CACHE_TTL,
#   ALIAS_*, DEPLOY_PREFIX_FORMAT, LOG_LEVEL
sops encrypt --in-place infra-secrets/management/artemis.env
mv infra-secrets/management/artemis.env \
   infra-secrets/management/artemis.env.enc
git -C infra-secrets add management/artemis.env.enc
git -C infra-secrets commit -m "feat(management): seal artemis env"
```

**Decrypt incantation** (Helm chart + any ops script):

```
sops decrypt --input-type dotenv --output-type dotenv \
  infra-secrets/management/artemis.env.enc
```

Both flags required — sops auto-detect from `.enc` extension falls
back to JSON parser; dotenv envelopes silently fail without explicit
type flags (`Error unmarshalling input json: invalid character '#'`).
See `infra/CLAUDE.md` §Secrets for canonical pattern.

Helm chart consumes via sealed Secret template (rendered at deploy
time by chart `templates/secret.yaml` calling sops with flags above).

### 5. sites.yaml seed — initial team→site map

**Source of truth (per ADR-016 §sites.yaml lifecycle, line 178).**

```
freeCodeCamp/artemis repo:  config/sites.yaml
```

PR-reviewed by platform team in the **artemis repo**. Schema per
ADR-016 §Q11 (line 35) — file-based static map, hot-reload:

```yaml
# ~/DEV/fCC-U/artemis/config/sites.yaml
#
# Source of truth for artemis authorization map. Per ADR-016 §Q11.
# PR-reviewed by platform team in this repo. artemis svc loads this
# file (via ConfigMap mount in cluster) and probes team membership
# per request: GET /orgs/freeCodeCamp/teams/{slug}/memberships/{user}
# cached `GH_MEMBERSHIP_CACHE_TTL` seconds (default 300).
#
# Hot-reloaded via fsnotify on ConfigMap update; no pod restart.
sites:
  example-site:
    teams: ["platform"]
```

**Drift correction (2026-04-27).** Earlier T34 step-5 draft pinned
`sites.yaml` to `infra/k3s/gxy-management/apps/artemis/sites.yaml`.
That was wrong — that path is the **render target** (chart-side
ConfigMap source), not the source of truth. ADR-016 §sites.yaml
lifecycle is explicit: source = artemis repo `config/sites.yaml`;
infra-side ConfigMap is one delivery mechanism among several.

**Delivery to k8s (T34 chart designer's call; v1 path).**

T34 worker selects ONE of:

- **(v1 default — recommended)** Helm `--set-file` from operator's
  artemis local checkout at deploy time:

  ```bash
  helm upgrade artemis ./chart \
    --set-file sites=$HOME/DEV/fCC-U/artemis/config/sites.yaml \
    ... (other flags)
  ```

  Wrapped in justfile recipe (e.g. `just helm-upgrade gxy-management
artemis`) so operator never types the long path. T34 chart
  `templates/configmap.yaml` renders ConfigMap from `.Values.sites`.

- **(future — when ArgoCD multi-cluster lands)** ArgoCD multi-source
  app sources artemis repo `config/sites.yaml` + infra chart in
  parallel. Eliminates manual sync. Parked at TODO-park §ArgoCD
  multi-cluster wiring.

- **(option C — image-bake)** artemis CI bakes `config/sites.yaml`
  into the image at build time; pod reads from `/etc/artemis/sites.yaml`
  inside container layer. Pros: zero infra coupling. Cons: image
  rebuild + rollout per site change; defeats fsnotify hot-reload.
  ADR-016 line 180 lists this as alternative ("CI builds image OR
  ships ConfigMap-only update"). Reject for v1 — fsnotify hot-reload
  is the locked-in pattern.

**ConfigMap mount path inside pod:** `/etc/artemis/sites.yaml`
per `SITES_YAML_PATH` env (T31 dispatch default).

**Operator action BEFORE T34 worker fires.**

```bash
cd ~/DEV/fCC-U/artemis
mkdir -p config
cat > config/sites.yaml <<'YAML'
sites:
  example-site:
    teams: ["platform"]
YAML
# Edit example-site → real first production site slug + team slugs
# matching freeCodeCamp org reality (e.g. "platform", "staff", or
# editorial team slugs)

git add config/sites.yaml
git commit -m "feat(config): initial sites.yaml seed"
git push   # operator-owned push
```

T34 worker references this file via `--set-file` in the Helm install
recipe; no further action needed beyond ensuring the path is current
on the operator's machine at deploy time.

**Lifecycle (per ADR-016 §sites.yaml lifecycle):**

- New site / team change: PR to `freeCodeCamp/artemis` repo
  `config/sites.yaml` → review → merge → operator runs
  `just helm-upgrade gxy-management artemis` → ConfigMap renders
  from latest local checkout → fsnotify reload in pod (≤1min). No
  pod restart.
- Cache invalidation per ADR-016 line 182: clear `(user, site)` and
  `(user, slug)` cache entries scoped to changed sites on reload.

**Cross-ref.** ADR-016 §sites.yaml lifecycle (line 178); §Authn/authz
Q11 (line 35); env sample
`~/DEV/fCC/infra-secrets/management/artemis.env.sample` §SITES_YAML_PATH;
TODO-park §Application config (artemis sites.yaml schema slim +
embedded registry — followup for scale + simpler reality).

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

- [x] Helm chart files landed (`k3s/gxy-management/apps/artemis/charts/artemis/` + `apps/artemis/values.production.yaml` + README)
- [x] ~~Caddy values updated~~ — N/A under Path X reframe (cassiopeia caddy not in path; dispatch §Galaxy placement amend 2026-04-27)
- [x] Smoke script landed (`scripts/phase5-proxy-smoke.sh` + `just phase5-smoke`)
- [x] Runbook landed (`docs/runbooks/deploy-artemis-service.md`)
- [x] Flight-manual section added (`docs/flight-manuals/gxy-management.md` §Phase 7 Artemis)
- [x] Justfile recipes added (`just artemis-deploy`, `just mirror-artemis-secrets`, `just phase5-smoke`)
- [x] RUN-residency clause documented (Universe field-note 2026-04-27 + infra TODO-park amend + auto-memory)
- [x] `.prettierignore` for chart templates (post-write formatter mangles helm `{{ }}` syntax)
- [x] T34 Status `done`
- [x] PLAN matrix row checked
- [x] HANDOFF entry appended
- [x] DECISIONS D43 Path X amend block appended
