# Sprint 2026-04-26 — DECISIONS

Locked operator + governing-session decisions. **Read-only after acceptance.** Amendments appended in-place via dated blocks; never rewrite original rows.

Source-of-truth split:

- **Q9–Q15** locked here (prior Q1–Q8 archived under `../archive/2026-04-21/DECISIONS.md`).
- **D016** is Universe-ADR-authoritative — `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`. Row below is summary cross-ref.
- **D33–D42** carry forward from prior sprint; row below repeats only D43 (this sprint's first new D-row, cross-ref to D016).

## Summary table — Q9–Q15 ACCEPTED 2026-04-26 (governing session, broken ownership)

| Q   | Topic                       | Decision                                                                                               |
| --- | --------------------------- | ------------------------------------------------------------------------------------------------------ |
| Q9  | Proxy hosting + R2 layout   | Standalone Go svc at `uploads.freecode.camp`; Caddy reverse-proxies; direct upload to existing bucket  |
| Q10 | CLI identity priority chain | env → GHA OIDC → Woodpecker OIDC → `gh auth token` → device-flow stored                                |
| Q11 | Authz model                 | Server-side static `sites.yaml` (site → team-slugs); GH team membership probe per request, 5min cache  |
| Q12 | Upload model                | Streaming proxy (no presigned URLs); bandwidth thru proxy fine for static-app sizes                    |
| Q13 | Atomic alias write          | Server-side; proxy is sole writer; single S3 PUT (R2 PutObject atomic); verify via ListObjectsV2 first |
| Q14 | universe-cli versioning     | Yank `feat/woodpecker-pivot` work; fresh `feat/proxy-pivot` off `main`; v0.3 stays current published   |
| Q15 | Proxy repo                  | New repo `freeCodeCamp/uploads` at `~/DEV/fCC-U/uploads/`; Go module `github.com/freeCodeCamp/uploads` |

## D-row cross-refs

| D   | Status                                                                               | Summary                                                                                                                                                                                                                                              |
| --- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D43 | accepted 2026-04-26 evening (cross-ref Universe ADR D016; supersedes T11 token-mint) | Deploy-proxy plane. Standalone Go microservice at `uploads.freecode.camp` holds sole R2 admin credential. CLI authenticates via GitHub identity. Server-side static team-slug map. Streaming proxy. Atomic alias write. Per-site R2 token mint DEAD. |

Prior D-rows (D33–D42) live in `../archive/2026-04-21/DECISIONS.md`. They remain in force where applicable:

- D33 — admin token home `infra-secrets/windmill/.env.enc` (proxy reads via Resource)
- D35 — Preview DNS dot-scheme `<site>.preview.freecode.camp` (carried)
- D36 — DO Cloud Firewall only (carried)
- D37 — Two-zone staff-site DNS pattern (carried)
- D38 — Rollback SLO ≤2 min (carried)
- D39 — 7d hard retention; alias prefix-pin (carried, T22)
- D40 — Per-site R2 secrets in Woodpecker — **superseded in spirit by D43** (no per-site secrets at all post-pivot)
- D41 — Smoke + cleanup ops use admin S3 keys (carried)
- D42 — Per-cluster ops-rw.env.enc dropped (carried)

## Amendments log (this doc)

- **2026-04-26 (sprint open)** — Q9–Q15 accepted via single governing session under broken-ownership authorization. D43 row landed. No team round-trip required tonight; teams may amend post-hoc via append-only block.
- **2026-04-26 (late evening, post-T30 close)** — Q15 service rename `uploads → artemis`. Repo `freeCodeCamp/artemis`, path `~/DEV/fCC/artemis/`, Go module `github.com/freeCodeCamp/artemis`. Public hostname `uploads.freecode.camp` UNCHANGED. ADR-016 amended in-place at `Universe@310c7e1`. T31 dispatch renamed to `T31-artemis-service.md`. Operator-driven; rationale: `uploads` too generic for a named platform service.
- **2026-04-26 (late evening, JWT clarification)** — ADR-016 §Authn/authz "no JWT minting in v1" clarified at `Universe@310c7e1`: refers to **auth-session JWTs only**. **Deploy-session JWTs** (`(login, site, deployId)` scope, ≤15 min TTL, HS256) are in v1 — needed for multi-step deploy transactions. T31 dispatch already specified deploy-session JWT layer; ADR amended to match.
- **2026-04-27 (CLI namespace pivot, pre-T32 fire)** — ADR-016 amended (3rd dated block): deploy verbs namespaced under `static` subcommand. Top-level `universe` reserved for cross-cutting (`login`, `logout`, `whoami`, `version`); future surfaces (workers, dbs, queues) follow same pattern. Pre: `universe deploy` / `promote` / `rollback` / `ls`. Post: `universe static deploy` / `promote` / `rollback` / `ls`. Caught before T32 worker fired; T32 dispatch + sprint goal phrasing updated same commit. T33-shipped `docs/platform-yaml.md` text fix folded into T32 worker scope. No semantic change to proxy plane.

## Brainstorm rationale

### Q9 — Proxy hosting + R2 layout

**Decision: Standalone Go service. Existing bucket. No staging.**

- Go gives portable single binary, no Node runtime in deploy plane, low cold-start.
- Hostname `uploads.freecode.camp` (CF proxied; SSL Full Strict).
- Caddy on cassiopeia reverse-proxies to k3s service (Tailscale upstream).
- Direct upload to `universe-static-apps-01/<site>/deploys/<ts>-<sha>/` (existing bucket; no new bucket; no folder move). R2 has no real folders → copy+delete = 2× ops + bandwidth + race risk. KISS.
- Atomic alias flip on finalize (single PUT to `<site>/preview` or `<site>/production`).

### Q10 — CLI identity priority chain

**Decision: Env → GHA OIDC → Woodpecker OIDC → `gh auth token` → device-flow stored.**

- Env (`$GITHUB_TOKEN`/`$GH_TOKEN`) covers explicit CI + advanced laptop users.
- GHA OIDC (`$ACTIONS_ID_TOKEN_REQUEST_TOKEN`) auto in GHA workflows; ID token presented to proxy.
- Woodpecker OIDC similar (when WP supports — currently planned, not blocking).
- `gh auth token` shell-out — laptop user with GH CLI installed; zero new auth state.
- Device flow stored at `~/.config/universe-cli/token` — laptop fallback when no `gh` CLI.

Server validates via `GET /user`, caches login→user 5 min. Authz separate (Q11).

### Q11 — Authz model

**Decision: Server-side static `sites.yaml`; GH team membership probe per request.**

- Repos cannot grant themselves access (no `authorizedTeams` in `platform.yaml`).
- `sites.yaml` lives alongside uploads svc, hot-reload on file change (fsnotify).
- Probe `GET /orgs/{org}/teams/{slug}/memberships/{user}` per request, cached 5 min.
- Apollo GH module reusable for token exchange + GH client lib.

### Q12 — Upload model

**Decision: Streaming proxy. No presigned URLs.**

- Static-app sizes typically <100 MB; bandwidth thru proxy not a real cost.
- Streaming proxy keeps trust boundary at proxy + simpler CLI (no presigned URL minting + upload-then-confirm dance).
- Future option: switch to presigned for >1 GB uploads if any site demands.

### Q13 — Atomic alias write

**Decision: Server-side; proxy is sole writer.**

- R2 admin token stays in proxy. Client never has R2 access to alias keys.
- After upload finalize, proxy ListObjectsV2 verifies all expected files arrived under expected prefix.
- Verify pass → single S3 PUT to alias key (atomic per-key in R2). Old deploy keeps serving until PUT lands.
- Verify fail → 422; alias untouched; client sees error.
- Trust boundary clean: alias = trust signal; only proxy writes it.

### Q14 — universe-cli versioning

**Decision: Yank `feat/woodpecker-pivot`; fresh `feat/proxy-pivot` off `main`.**

- 4 commits on `feat/woodpecker-pivot` are now archaeology — built on a wrong assumption (CI as upload origin).
- v0.3 stays current published until v0.4 ships (no breakage in flight).
- Fresh branch off `main` keeps history clean; old branch never merged.
- v0.4 numbering (not v0.5): same major (0), minor bump for surface change.

### Q15 — Proxy repo

**Decision: New repo `freeCodeCamp/uploads`.**

- CLI = client surface. Proxy = server. Different audiences (staff devs vs platform team), different lifecycles, different deps (Go vs TS), different release cadence.
- Naming: short, neutral, descriptive (`uploads`). Not `proxy` (too generic), not `deploy-proxy` (verbose).
- Path: `~/DEV/fCC-U/uploads/`. Go module: `github.com/freeCodeCamp/uploads`.

---

### D43 amendment — 2026-04-27 — T34 Path X reframe + RUN-residency + auth path

T34 worker session surfaced three architectural conflicts in the
original dispatch wording. Resolved by operator (mrugesh) on
2026-04-27. All three live as `D43` amendments because the original
D43 row anchors the deploy-proxy plane (cross-ref `Universe ADR-016`).

**Amend 1 — Path X (drop Tailscale + Caddy/cassiopeia hop).**

Original dispatch wording proposed: `uploads.freecode.camp → CF →
Caddy/cassiopeia → Tailscale → artemis/management`. Conflicts with
**Universe ADR-009** ("Tailscale Operator rejected — node-level only,
no operator on Universe galaxies; Cloudflare → node public IP →
Traefik is the staff-access pattern").

**Resolution.** Reframe to single-galaxy hop. DNS already aligned:
`uploads.freecode.camp` A → gxy-management public IPs (operator-
confirmed). Caddy on cassiopeia stays on `*.freecode.camp` tenant
sites + previews; never sees `uploads.freecode.camp`.

```
uploads.freecode.camp
    → CF proxied (orange) → CF Origin → gxy-management public IP
    → Traefik (hostNetwork DaemonSet)
    → Gateway (artemis-gateway, ns artemis, websecure listener)
    → HTTPRoute (artemis-route, hostname uploads.freecode.camp)
    → Service artemis (ClusterIP :8080)
    → Pod artemis (Go binary)
```

Same shape as `windmill.freecodecamp.net`,
`registry.freecodecamp.net`, `argocd.freecodecamp.net` — except on
the `freecode.camp` zone instead of `freecodecamp.net`. Per-app TLS
overlay (CF Origin cert sealed inside the values overlay) matches
the cassiopeia caddy precedent.

**Amend 2 — RUN-residency clause for Universe platform pillars.**

Operator flagged: artemis pillar deployed on `gxy-management` MUST
NOT pull its container image from a registry on the same galaxy
(zot lives at `gxy-management`). Cluster-wipe rebuild deadlock —
kubelet cannot reach zot until zot runs; zot cannot run without
its image; that image must come from zot. Same outage equivalent
on any zot incident.

**Resolution.** RUN-residency rule extends the 2026-04-26 build-
residency rule (Universe field-note `infra.md` line 983):

| Path                                             | Universe pillars (caddy-s3, artemis, ingress) | Tenant deploys (cassiopeia, launchbase)             |
| ------------------------------------------------ | --------------------------------------------- | --------------------------------------------------- |
| Build location                                   | Outside Universe (GitHub Actions)             | Universe Woodpecker                                 |
| Pull source (`image.repository` in chart values) | **GHCR direct** (`ghcr.io/freecodecamp/<x>`)  | GHCR direct OR ratified zot pull-through (deferred) |
| Storage backing                                  | Outside Universe (R2, etc.)                   | Inside Universe acceptable                          |

Both build AND pull must clear the recovery boundary for pillars.
Documented in Universe field-note 2026-04-27 + infra TODO-park
§Build-residency migration amendment. Auto-memory feedback file
landed for cross-session continuity.

ADR proposal (Universe team owns) renamed: "Build + Run residency
for Universe platform pillars" — supersedes the 2026-04-26 single-
axis proposal.

**Amend 3 — Auth path A (no CF Access on artemis).**

Operator asked whether artemis should sit behind CF Access (Google
OAuth) like windmill / argocd / zot. Answer: no — artemis is a
programmatic API for the `universe` CLI + CI. Browser-based Google
SSO incompatible with headless `universe deploy` invocations. CF
Access service tokens (Path B) require per-CI provisioning and
duplicate auth without adding meaningful security (GH membership
check is the actual authorization gate per ADR-016 Q11).

**Resolution.** Path A: GitHub OAuth Bearer + deploy-session JWT
(HS256, 15min, scoped `(login, site, deployId)`) per ADR-016 §Authn/
authz. Compensating controls:

- chart-internal Traefik rate-limit Middleware (per-source-IP, CF
  X-Forwarded-For depth=1, tunable via values overlay)
- CF WAF rules on `freecode.camp` zone (deferred to operator post-
  deploy; runbook §Failure modes)
- read-only R2 keys + per-prefix scoping (D33 ×2)
- JWT scope narrowing (cannot promote/rollback — those re-auth via
  GH token)

Path C (CF Access service tokens) parked at TODO-park §Application
config — revisit post-G2 if abuse appears.

**Cross-refs.**

- `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` §2026-04-27
  RUN-residency clause
- `~/DEV/fCC/infra/docs/runbooks/deploy-artemis-service.md`
- `~/DEV/fCC/infra/docs/flight-manuals/gxy-management.md` §Phase 7
- `~/DEV/fCC/infra/docs/sprints/2026-04-26/dispatches/T34-caddy-dns-smoke.md`
  §Galaxy placement (Path X reframe)
- `~/DEV/fCC/infra/docs/TODO-park.md` §Build-residency migration
  (RUN-residency amendment block)
