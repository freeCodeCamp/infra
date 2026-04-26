# T34 — Caddy reverse proxy + DNS prep + smoke retarget

**Status:** pending
**Worker:** w-infra (governing session — broken ownership 2026-04-26)
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** D016 §Operational surface
**Cross-ref:** D43 amendment in sprint `DECISIONS.md`
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Where uploads service lands

`uploads.freecode.camp` → CF proxied → gxy-management public IP →
Caddy listener (existing `caddy-s3` on cassiopeia OR a new Caddy on
gxy-management — see open question below).

**Open question for operator:** uploads service runs on which galaxy?

- **Option A: gxy-management.** Already runs Windmill + Zot. Adding a
  small Go service is low-overhead. Caddy on gxy-cassiopeia already
  serves `*.freecode.camp`; would need to add `uploads.freecode.camp`
  upstream rule pointing across galaxies (Tailscale or DO private
  network). Slight cross-galaxy hop.
- **Option B: gxy-cassiopeia.** Same node already runs Caddy. Service
  - Caddy share node → no cross-galaxy hop. But cassiopeia is the
    "serve plane" — adding ingress-handling service blurs the role.
- **Option C: gxy-launchbase.** Newest cluster, less load. But adds
  ingress-handling responsibility to a build-only galaxy (Woodpecker).

Lean: **Option A (gxy-management).** Operator confirms.

## Files to touch

```
infra/
├── k3s/gxy-management/                 # OR cassiopeia per option above
│   └── apps/uploads/
│       ├── chart/                      # Helm chart for uploads svc
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
│   └── play-uploads-deploy.yml         # generic deploy playbook
├── justfile                            # add `just uploads-deploy` recipe
└── docs/
    ├── runbooks/
    │   └── deploy-uploads-service.md   # NEW
    ├── sprints/2026-04-21/
    │   └── dispatches/T34-caddy-dns-smoke.md
    └── flight-manuals/
        └── gxy-management.md           # add uploads service section
```

## DNS

Operator clickops:

- CF DNS → `freecode.camp` zone → add A record `uploads.freecode.camp`
  → gxy-management public IP
- Proxied (orange cloud)
- SSL Full (Strict) — origin cert `*.freecode.camp` already issued
- TTL auto

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
              - dial: "uploads.management.tailscale.fcc:8080"
            transport:
              protocol: http
            headers:
              request:
                set:
                  X-Forwarded-Host: ["{http.request.host}"]
                  X-Forwarded-Proto: ["{http.request.scheme}"]
```

(Final upstream addr depends on Option A/B/C. Tailscale name pattern
shown for cross-galaxy.)

## Smoke retarget

Existing `scripts/phase4-test-site-smoke.sh` writes objects directly to
R2 via admin S3 keys. Retarget for proxy model:

```
scripts/phase5-proxy-smoke.sh           # NEW — exercises proxy E2E
```

Flow:

1. Resolve identity via `gh auth token`
2. POST `/api/deploy/init` → capture deployJwt
3. PUT some test files via multipart upload
4. POST `/api/deploy/{id}/finalize?mode=preview`
5. Curl `https://test.preview.freecode.camp/` → assert 200 + content match
6. POST `/api/site/test/promote`
7. Curl `https://test.freecode.camp/` → assert 200
8. Cleanup: rollback to old preview (or trap delete via admin keys)

## Acceptance criteria

- Helm chart deploys uploads svc, pod runs, `/healthz` 200
- Caddy serves `uploads.freecode.camp` → uploads svc
- DNS resolves
- Smoke script green E2E

## Out of scope (operator owns)

- DNS A record creation (clickops above)
- GHCR image build for uploads (CI workflow file ships in T31; first build is operator-driven via `gh workflow run`)
- Helm install (operator runs `just helm-upgrade gxy-management uploads`)
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
