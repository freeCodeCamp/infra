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
- **2026-04-26 (late evening, post-T30 close)** — Q15 service rename `uploads → artemis`. Repo `freeCodeCamp/artemis`, path `~/DEV/fCC-U/artemis/`, Go module `github.com/freeCodeCamp/artemis`. Public hostname `uploads.freecode.camp` UNCHANGED. ADR-016 amended in-place at `Universe@310c7e1`. T31 dispatch renamed to `T31-artemis-service.md`. Operator-driven; rationale: `uploads` too generic for a named platform service.
- **2026-04-26 (late evening, JWT clarification)** — ADR-016 §Authn/authz "no JWT minting in v1" clarified at `Universe@310c7e1`: refers to **auth-session JWTs only**. **Deploy-session JWTs** (`(login, site, deployId)` scope, ≤15 min TTL, HS256) are in v1 — needed for multi-step deploy transactions. T31 dispatch already specified deploy-session JWT layer; ADR amended to match.

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
