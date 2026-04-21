# Sprint 2026-04-21 — Session Handoff

Read this first when resuming in a fresh Claude Code session. All session-local
context needed to continue the Universe static-apps MVP work lives here.

## Start-here checklist (fresh session)

1. Read this file end-to-end.
2. Read `docs/GUIDELINES.md` (doc conventions).
3. Run `TaskList` — verify tasks #17–#35 present; if not, recreate from the
   [Task map](#task-map) below.
4. Verify live cluster state still matches [Galaxy state](#galaxy-state) (helm
   releases + droplets drift over time).
5. Pick next unblocked task in `TaskList` and proceed.

## Session context (2026-04-21)

This handoff was produced after a deep audit that concluded the
`docs/sprints/2026-04-20/` sprint had drifted from post-bootstrap reality and
was scrapped. A fresh plan was built around shipping static-apps end-to-end to
unblock the staff team.

### Operator decisions this round

- **Rename `gxy-mgmt` → `gxy-management` globally.** Acceptable to teardown +
  reprovision as dogfood for the flight-manual.
- **Windmill permanent home = `gxy-management`.** Overrides ADR-001's
  backoffice placement. ADR-001 needs amendment.
- **CF Access dropped globally.** OAuth org-gate is canonical for any tool
  with native OAuth (Woodpecker, ArgoCD, Windmill, Grafana). CF Access
  reserved only for auth-less surfaces (rare). Resolves open decision D22.
- **Old sprint scrapped** — `docs/sprints/2026-04-20/` to be moved to
  `docs/sprints/archive/2026-04-20/` during the docs reorg (task #17).
- **ADR amendment ownership bypass granted** — this agent may amend ADRs
  in-place despite Universe-team owning them per convention.
- **Static-apps E2E = MVP.** Dynamic apps, bare-metal, o11y, BetterAuth are
  deferred. Goal: staff push to repo → site live on cassiopeia.

### Galaxy role reassignments (operator-supplied)

| Galaxy         | Provider now | Provider future | Role                                  | Tools                                                       |
| -------------- | ------------ | --------------- | ------------------------------------- | ----------------------------------------------------------- |
| gxy-management | DO FRA1      | DO FRA1         | Control plane                         | Windmill + Zot + ArgoCD (platform-only) + Atlantis          |
| gxy-launchbase | DO FRA1      | Hetzner         | Supply chain ("GitHub Actions layer") | Woodpecker (+ArgoCD TBD) + CI tooling                       |
| gxy-backoffice | TBD          | Hetzner         | Backoffice + o11y                     | VictoriaMetrics + ClickHouse + Vector + HyperDX + GlitchTip |
| gxy-cassiopeia | DO FRA1      | Hetzner         | Static hosting                        | Caddy + R2 (cassiopeia serves staff constellations)         |
| gxy-triangulum | —            | Hetzner         | Dynamic hosting ("Heroku-like")       | containers, CNPG prod, Ceph RGW future                      |

Deferred galaxies (not in MVP): gxy-backoffice, gxy-triangulum.
Retiring: gxy-static at cassiopeia cutover.
Out of scope: `ops-mgmt`, `ops-backoffice-tools` (legacy fCC, retire post-Universe).

## Galaxy state (verified 2026-04-21)

### Naming conventions (critical — all three forms diverge)

- **Repo dir:** `k3s/gxy-{management,static,launchbase,cassiopeia}/`
  (full word `management`; others short)
- **Ansible group (underscore):** `gxy_mgmt_k3s`, `gxy_static_k3s`,
  `gxy_launchbase_k3s`, `gxy_cassiopeia_k3s`
- **DO droplet tag (dash):** `gxy-mgmt-k3s`, `gxy-static-k3s`,
  `gxy-launchbase-k3s`, `gxy-cassiopeia-k3s`
- **Droplet names:** `gxy-vm-{mgmt,static,launchbase,cassiopeia}-k3s-{1,2,3}`

The `mgmt` → `management` rename (task #21/#22) touches all three forms plus
repo doc refs.

### Live clusters

All DO · FRA1 · k3s HA embedded etcd · `cilium 1.19.2` ·
`traefik 39.0.201+up39.0.2 (v3.6.9)` + `traefik-crd` · PSS baseline ·
3 nodes each.

| Galaxy         | Nodes                                           | App helm releases (chart / app ver)                                                  |
| -------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------ |
| gxy-management | 164.92.245.161, 64.226.72.77, 164.90.160.64     | argocd (argo-cd-9.4.17 / v3.3.6), windmill (windmill-4.0.134 / 1.686.0)              |
| gxy-static     | (legacy)                                        | caddy (caddy-static-0.1.0 / 2.9)                                                     |
| gxy-launchbase | 68.183.221.232, 68.183.215.167, 165.245.220.145 | cnpg-system (cloudnative-pg-0.28.0 / 1.29.0), woodpecker (woodpecker-3.5.1 / 3.13.0) |
| gxy-cassiopeia | 46.101.179.141, 188.166.165.62, 165.227.149.249 | caddy (caddy-0.1.0 / 0.1.0) with in-tree r2_alias + caddy.fs.r2                      |

### External infra

- Cloudflare (zones `freecodecamp.net`, `freecode.camp`) — all origins proxied
- Origin TLS: CF Origin Cert `*.freecodecamp.net` reused across galaxies
- Object storage live: Cloudflare R2 bucket `universe-static-apps-01`
- Secrets at rest: sops + age in sibling repo `infra-secrets`
- Admin plane: Tailscale (SSH + kubectl only; per ADR-011)

### Live endpoints

- `https://woodpecker.freecodecamp.net` → 302 via CF, org-gated OAuth
- `https://argocd.freecodecamp.net` → HTTPRoute on gxy-management
- `https://windmill.freecodecamp.net` → HTTPRoute on gxy-management

### Apps-dir vs deployed drift

- `k3s/gxy-management/apps/zot/` exists but Zot NOT in helm releases — deploy gap.
- Supply-chain chain (cosign / Grype / Trivy / Kyverno / SBOM) absent —
  acceptable for static-apps MVP, blocks triangulum.

## Completed this round (audit trail)

- `fb333fc` MASTER.md A1 tick + dispatch path typo fix (sprints/)
- Bead `gxy-static-k7d.33` closed with reason referencing `fb333fc`
- Universe main pushed (8 commits: 2344385, 589b6a8, 7c26006, 8cf77e6,
  41c538e, 9a0beef, ab8d7c2, 161a93e). Remote moved to
  `freeCodeCamp-Universe/Universe-Architecture.git` (warning from old URL —
  update when convenient)
- `965901d` FLIGHT-MANUAL Parts 3+4 (gxy-launchbase + gxy-cassiopeia) shipped
- Old sprint 2026-04-20 dispatch files: no new commits; to be archived during
  docs reorg (task #17)

## Task map

All tasks live in the Tasks API. If not present (session reset lost state),
recreate from subjects below; dependencies at end of table.

### Main track (11 tasks)

| ID  | Subject                                                                                      | Status      |
| --- | -------------------------------------------------------------------------------------------- | ----------- |
| #17 | Docs foundation: GUIDELINES + field-notes reformat + tree reorg + per-cluster flight-manuals | in_progress |
| #18 | ADR amendments in-place (bypass ownership)                                                   | pending     |
| #19 | Write docs/TODO-park.md deferment list                                                       | pending     |
| #20 | Deep cluster audit: cost + HA + autoscaling inventory                                        | pending     |
| #21 | Rename runbook: gxy-mgmt → gxy-management (full blast radius)                                | pending     |
| #22 | Execute gxy-mgmt → gxy-management via reprovision                                            | pending     |
| #23 | Write new MASTER sprint plan (`docs/sprints/2026-04-21/`)                                    | pending     |
| #24 | MVP: static-apps E2E chain (Woodpecker pipeline + R2 flow + alias + cleanup + smoke)         | pending     |
| #25 | Release universe-cli 0.4.0-beta.1                                                            | pending     |
| #26 | Cutover: DNS gxy-static → gxy-cassiopeia + teardown gxy-static                               | pending     |
| #27 | Recurring: monthly doc trim (standing)                                                       | pending     |

### Q/A brainstorm track (8 decisions, all gate #23)

| ID  | Question                                                              | Status  |
| --- | --------------------------------------------------------------------- | ------- |
| #28 | Q1 alias-write mechanism (Windmill flow vs Woodpecker pipeline step)  | pending |
| #29 | Q2 CF R2 admin cred path in infra-secrets                             | pending |
| #30 | Q3 per-site secret sops path naming                                   | pending |
| #31 | Q4 origin IP allow-list enforcement (Cilium CNP vs DO Cloud Firewall) | pending |
| #32 | Q5 staff-site DNS pattern (platform-owned vs BYO)                     | pending |
| #33 | Q6 rollback SLO target                                                | pending |
| #34 | Q7 preview envs in MVP (prod-only vs prod+preview)                    | pending |
| #35 | Q8 cleanup retention policy (hard 7d vs per-site override)            | pending |

### Dependencies

- #22 blocked by #17, #21
- #23 blocked by #17, #18, #28, #29, #30, #31, #32, #33, #34, #35
- #24 blocked by #23
- #25 blocked by #24
- #26 blocked by #25, #32

Ready-now: #17 (in progress), #18, #19, #20, #21, plus all Q/A (#28–#35).

## Deferment list (will land in docs/TODO-park.md via #19)

**Parked (no MVP impact):**

- Supply chain (Zot push, cosign, Grype+Trivy, Kyverno verifyImages, SBOM) —
  activates with first image ship (gxy-triangulum)
- Atlantis on gxy-management — after first IaC PR pain
- BetterAuth + Account Service — post-10-app threshold per spike
- gxy-triangulum provisioning — no dynamic apps in MVP
- Hetzner migration (launchbase, backoffice, cassiopeia eventual) — post-M5
- ArgoCD multi-cluster wiring — single-cluster MVP
- CNPG barman-cloud plugin — when prod DB lands
- DR runbook (ADR-012) — post-M1
- Rook-Ceph — post-bare-metal
- ops-\* legacy teardown — post-Universe launch
- gxy-backoffice provisioning + O11y stack — sequence after static MVP

**Not deferred, part of MVP:**

- Rename `gxy-mgmt` → `gxy-management` (incl. reprovision)
- Static-apps E2E chain
- universe-cli 0.4.0-beta.1 release
- DNS cutover + gxy-static teardown
- Docs reorg

## Q/A brainstorm — current options (operator decisions pending)

All 8 questions gate task #23. Answers unblock #24, #25, #26 cascade.

- **Q1 alias-write:** (a) Woodpecker pipeline step / (b) Windmill flow /
  (c) hybrid
- **Q2 CF R2 admin cred path:** (a) `infra-secrets/platform/…` /
  (b) `infra-secrets/k3s/gxy-cassiopeia/…` / (c) dedicated provisioning token
- **Q3 per-site sops path:** (a) `infra-secrets/constellations/<site>.secrets.env.enc` /
  (b) `infra-secrets/k3s/gxy-cassiopeia/sites/<site>.secrets.env.enc` /
  (c) `infra-secrets/cassiopeia/sites/<site>.secrets.env.enc` (current RFC)
- **Q4 origin IP allow-list:** (a) Cilium CNP / (b) DO Cloud Firewall /
  (c) both
- **Q5 staff-site DNS:** (a) platform-owned `<site>.freecode.camp` /
  (b) BYO via `universe` CLI / (c) both (default platform, opt-in BYO)
- **Q6 rollback SLO:** (a) seconds / (b) minutes / (c) tiered
- **Q7 preview envs:** (a) prod-only MVP / (b) prod+preview day 1 /
  (c) prod on cassiopeia + preview on launchbase
- **Q8 cleanup retention:** (a) hard 7d / (b) 7d default + platform.yaml
  override / (c) tiered by site importance

Tradeoffs documented in each task description.

## Key file references

### Infra repo (`~/DEV/fCC/infra`, branch `feat/k3s-universe`)

- `CLAUDE.md` — project instructions + galaxy table
- `docs/FLIGHT-MANUAL.md` — current singular manual (to split into
  `docs/flight-manuals/` per-cluster via #17)
- `docs/runbook/` (to rename → `docs/runbooks/` via #17):
  `dns-cutover.md`, `gxy-launchbase.md`, `r2-bucket-provision.md`
- `docs/architecture/`:
  `rfc-gxy-cassiopeia.md` (large, canonical spec),
  `task-gxy-cassiopeia.md` (large, breakdown),
  `rfc-gxy-cassiopeia-caddyfile-poc.md`
- `docs/sprints/2026-04-20/` — scrapped, archive via #17
- `docs/sprints/2026-04-21/` — this sprint (HANDOFF + README here)
- `ansible/` — playbooks, roles, inventory
- `k3s/<galaxy>/` — per-cluster app dirs (pattern: `apps/<app>/charts/<chart>/`
  - `apps/<app>/manifests/base/` + `values.production.yaml`)
- `.claude/rules/` — code-quality + docs-ops rules

### Universe repo (`~/DEV/fCC-U/Universe`, branch `main`)

- `CLAUDE.md`, `CONTEXT.md`, `REQUIREMENTS.md`, `ARCHI-DIAGRAM.md`
- `decisions/001-015-*.md` — 15 ADRs (to amend via #18)
- `spike/field-notes/{infra,windmill,universe-cli}.md` — reformat via #17
- `spike/spike-plan.md`
- `spike/tool-validation.md`
- Remote renamed to `freeCodeCamp-Universe/Universe-Architecture.git` —
  update `origin` URL when convenient.

### universe-cli repo (`~/DEV/fCC-U/universe-cli`, branch `feat/woodpecker-pivot`)

- Code shipped locally (commits `a7dd58e` + `f6971cf`) — Woodpecker client
  replaces direct R2; `@aws-sdk/client-s3` removed; bundle 1.95 MB → 812 KB
- Version still `0.3.3` on npm; `0.4.0-beta.1` release pending task #25
- Branch diverged from main — merge to main before tagging release

### Windmill repo (`~/DEV/fCC-U/windmill`, branch `main`)

- `workspaces/platform/f/` — existing flows (`app`, `github`, `google_chat`,
  `ops`, `repo_mgmt`)
- `workspaces/platform/f/static/` — does not exist yet; task #24 creates
  `provision_site_r2_credentials.{ts,yaml,test.ts}`

### infra-secrets repo (private, sibling)

- `k3s/gxy-launchbase/*.enc` — woodpecker secrets live here
- Per-site R2 secret path — NOT YET DEFINED (gated on Q3)
- CF R2 admin cred path — NOT YET DEFINED (gated on Q2)

## Non-obvious invariants

- `rtk` tool is mandatory for all Bash tool calls per user CLAUDE.md
- `caveman` output style active — drop articles/filler in user-facing text
- `context-mode` MCP tools route large outputs through sandbox — use
  `ctx_batch_execute` / `ctx_execute_file` / `ctx_search` for anything
  producing >20 lines
- Never push from session; operator pushes
- Never edit target files under `~/.claude/*` — edit source in `~/.dotfiles/`
- Stage enforcement active: epic `gxy-static-k7d` currently at stage
  `speccing`; may need `running` promotion for MVP execution
- Windmill `wmill sync push` is destructive; check drift before pushing
- sops is stateful — `sops decrypt --in-place` then yq then
  `sops encrypt --in-place`

## Success criteria (MVP done)

1. Staff member pushes to a Universe-org repo following the
   `.woodpecker/deploy.yaml` template.
2. Woodpecker on gxy-launchbase builds + uploads build output to R2 bucket
   `universe-static-apps-01` under `<site>/deploys/<ts>-<sha>/`.
3. Alias write repoints `<site>/production` (or equivalent) to the new
   deploy prefix atomically.
4. Request to `<site>.freecode.camp` (or BYO domain) routes via CF →
   cassiopeia Caddy → R2 via `r2_alias` + `caddy.fs.r2`.
5. `universe rollback --to <deploy-id>` repoints alias to prior deploy;
   verified green within agreed SLO (Q6).
6. `universe promote` repoints production alias from preview (if Q7=b/c).
7. Cleanup cron deletes deploys older than retention (Q8) except aliased.
8. gxy-static retired; DNS for `*.freecode.camp` on gxy-cassiopeia.
9. `@freecodecamp/universe-cli@0.4.0-beta.1` published on npm.
10. Staff-facing "how to deploy a static site" playbook published.

## History of this sprint

- 2026-04-20 — Old sprint `docs/sprints/2026-04-20/` dispatched;
  bootstrap of gxy-launchbase + gxy-cassiopeia landed same day;
  T32 shipped as side-effect.
- 2026-04-21 — Audit surfaced doc-vs-reality drift; sprint scrapped;
  fresh plan built (this HANDOFF).
