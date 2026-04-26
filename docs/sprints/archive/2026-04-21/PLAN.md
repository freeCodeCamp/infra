# Sprint 2026-04-21 — PLAN

Stable plan. Patched only when scope/phases/dispatch-graph change.
Live cursor lives in [`STATUS.md`](STATUS.md). Locked Q/D rows in
[`DECISIONS.md`](DECISIONS.md). Per-task briefs in
[`dispatches/T<N>-<slug>.md`](dispatches/).

## Sprint goal

Ship Universe static-apps MVP. Staff push → site live on
`<site>.freecode.camp` via Woodpecker → R2 → Caddy(`r2_alias`) on
gxy-cassiopeia. Preview siblings at `<site>.preview.freecode.camp`.
Retire gxy-static.

## Branches

- infra `feat/k3s-universe` (this doc's home)
- universe-cli `feat/woodpecker-pivot`
- windmill `main`
- infra-secrets private sibling (no branch — sops-encrypted main)

## Tracking model (2026-04-25)

Filesystem-driven. Per-task dispatch docs at `dispatches/T<N>-<slug>.md`
carry status header (`pending → in-progress → done`). Worker flips
header in same commit that closes the task. Sprint matrix below
mirrors dispatch-doc Status. Beads + bead IDs deprecated for this
sprint (epic `gxy-static-k7d` left at `running`, unused).

## Galaxy role matrix (MVP scope)

| Galaxy         | State                    | Role this sprint                                           |
| -------------- | ------------------------ | ---------------------------------------------------------- |
| gxy-management | Live (DO FRA1)           | Windmill + Zot + (ArgoCD deferred → TODO-park)             |
| gxy-launchbase | Live (DO FRA1)           | Woodpecker pipeline host — builds + writes alias + uploads |
| gxy-cassiopeia | Live (DO FRA1)           | Caddy + R2 serve plane for `*.freecode.camp(+.preview)`    |
| gxy-static     | Live → retire at cutover | Legacy static sandbox; DNS moves to cassiopeia             |

Out of sprint: gxy-triangulum, gxy-backoffice, legacy fCC clusters.

## Top-level task chain

Dependency: **#23 → #24 → #25 → #26**. #27 standing.

| ID      | Subject                                                           | Status     | Blocks  |
| ------- | ----------------------------------------------------------------- | ---------- | ------- |
| #17     | Docs foundation (GUIDELINES + field-notes + flight-manuals split) | **done**   | —       |
| #18     | ADR amendments in-place (ADR-001/003/007/008/011/013 + D22/D32)   | **done**   | —       |
| #19     | `docs/TODO-park.md` deferment list                                | **done**   | —       |
| #20     | Deep cluster audit (cost + HA + autoscaling)                      | **done**   | —       |
| #21     | Rename runbook `gxy-mgmt → gxy-management`                        | **done**   | #22     |
| #22     | Execute rename via reprovision                                    | **done**   | #23+    |
| #23     | MASTER sprint plan                                                | **done**   | #24     |
| #24     | MVP static-apps E2E chain                                         | pending    | #25 #26 |
| #25     | Release `@freecodecamp/universe-cli@0.4.0-beta.1`                 | pending    | #26     |
| #26     | DNS cutover gxy-static → gxy-cassiopeia + teardown gxy-static     | pending    | —       |
| #27     | Recurring monthly doc trim (standing)                             | standing   | —       |
| #28–#35 | Q/A brainstorm decisions (Q1–Q8)                                  | **closed** | —       |

## Phases + gates

### Phase 0 — Foundation (DONE)

- [x] Docs conventions + ownership codified (GUIDELINES)
- [x] ADR amendments landed (Universe repo, pushed)
- [x] Cluster audit + deferment list
- [x] Rename runbook authored + executed
- [x] RFC secrets-layout accepted + Phases 1–7 shipped
- [x] QA brainstorm decisions locked
- [x] MASTER sprint plan written

**Gate G0:** cluster gxy-management GREEN post-rename, Windmill restored
from S3 dump, UI smoke 200. **PASSED.**

### Phase 1 — MVP static-apps chain (#24) — **PIVOTED 2026-04-26 per D016 (proxy plane)**

Sub-deliverables (post-pivot):

1. **P1.1 — Deploy proxy service** (T30 ADR + T31 uploads svc) — Go microservice
   at `uploads.freecode.camp`. Holds sole R2 admin credential. Authenticates
   staff via GitHub identity (token / OIDC / device-flow). Authorizes via
   server-side `sites.yaml` map → GitHub team membership probe. Streams
   uploads to `universe-static-apps-01/<site>/deploys/<ts>-<sha>/`. Atomic
   alias write on finalize.
2. **P1.2 — Caddy `r2_alias` on gxy-cassiopeia** — verified live 2026-04-18 + D35 dot-scheme rolled 2026-04-26. No re-dispatch.
3. **P1.3 — DNS wiring** — `uploads.freecode.camp` A → uploads svc galaxy public IP (T34); `<site>.freecode.camp` + preview A → cassiopeia public IPs. CF proxied. SSL Full Strict.
4. **P1.4 — Cleanup cron (Windmill flow on gxy-management)** (T22) — 7d retention; both aliases pin prefix (Q8). Independent of upload path; unchanged.
5. **P1.5 — Firewall posture (Q4)** — `gxy-fw-fra1` 80/443 open to `0.0.0.0/0`. No CF-IP diff cron. Uploads svc galaxy follows same posture.
6. **P1.6 — Smoke harness** (T34 retarget) — exercises proxy E2E (init → upload → finalize → curl preview → promote → curl prod). Replaces direct-S3 phase4 smoke.
7. **P1.7 — universe-cli v0.4 rewrite** (T32) — fresh branch off `main`; identity priority chain; commands target proxy `/api/*`. v0.3 R2-token CLI keeps current published until 0.4 ships.
8. **P1.8 — `platform.yaml` v2** (T33) — strip credential paths; build + deploy config only.

**Pivot rationale:** D016 supersedes T11 design. Per-site R2 token sharing (whether to staff or to CI via Woodpecker secrets) violates platform tenet. Proxy holds sole admin token; staff devs ship sites with only `platform.yaml` + GitHub identity.

**Gate G1:** End-to-end staff push → site live → rollback → promote →
cleanup exercised against one reference repo. Smoke harness green.

### Phase 2 — Release (#25)

- Strip legacy rclone/S3 paths from universe-cli (T20).
- Bump `0.4.0-beta.1`, publish to npm.
- CHANGELOG + README ported to new CLI contract.

**Gate G2:** `npm i -g @freecodecamp/universe-cli@0.4.0-beta.1` works;
`universe deploy` + `rollback` + `promote` drive Woodpecker-owned flow
against G1 reference site.

### Phase 3 — Cutover (#26)

- Flip DNS for existing `*.freecode.camp` users from gxy-static → gxy-cassiopeia.
- Teardown gxy-static (VMs + DNS + Caddy chart).
- Archive gxy-static flight-manual note.

**Gate G3:** gxy-static destroyed; no 404s for pre-existing sandbox sites
during 24h observation; `doctl compute droplet list` shows no
`gxy-static-k3s` tagged droplets.

### Phase 4 — Close

- Move `docs/sprints/2026-04-21/` → `docs/sprints/archive/2026-04-21/`.
- Final field-notes journal entry (`Universe/spike/field-notes/infra.md`).
- `#27` recurring monthly doc trim kept standing.

## #24 sub-task matrix (MVP in-scope only)

### G-dispatches (operator-bootstrap gates) — added 2026-04-26 recovery

| G-id       | Area               | Subject                                                         | Dispatch                                                                                                               | Status                                               |
| ---------- | ------------------ | --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| G1.0a      | windmill / sops    | Complete `windmill/.env.enc` + push `u/admin/cf_r2_provisioner` | [`dispatches/archive/G1.0a-windmill-cf-resource.md`](dispatches/archive/G1.0a-windmill-cf-resource.md)                 | [x] done — supersedes partial G1.0                   |
| G1.0b      | windmill / WP      | Mint Woodpecker admin token + push `u/admin/woodpecker_admin`   | [`dispatches/archive/G1.0b-windmill-woodpecker-resource.md`](dispatches/archive/G1.0b-windmill-woodpecker-resource.md) | [x] done                                             |
| G1.1       | infra / cassiopeia | `R2_BUCKET` export in `.envrc` + cassiopeia kubeconfig pull     | [`dispatches/archive/G1.1-cassiopeia-env.md`](dispatches/archive/G1.1-cassiopeia-env.md)                               | [x] done 2026-04-26                                  |
| G1.1.smoke | infra              | Operator runs `just phase4-smoke` (RFC §6.6 Phase 4 exit)       | [`dispatches/archive/G1.1-smoke-live-run.md`](dispatches/archive/G1.1-smoke-live-run.md)                               | [x] done 2026-04-26 — `phase4-20260426-080726` green |

### T-dispatches

| T-id      | Area             | Subject                                                      | Dispatch                                                                                           | Status                                                                                                                   |
| --------- | ---------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| T11       | windmill         | Per-site R2 secret provisioning flow                         | [`dispatches/archive/T11-windmill-flow.md`](dispatches/archive/T11-windmill-flow.md)               | **SUPERSEDED 2026-04-26 by D016.** Per-site token mint replaced by proxy plane. Artifact `windmill@010d577` archaeology. |
| T30       | infra (xrepo)    | D016 ADR — deploy proxy plane (broken-ownership session)     | [`dispatches/T30-d016-deploy-proxy-adr.md`](dispatches/T30-d016-deploy-proxy-adr.md)               | [ ] pending                                                                                                              |
| T31       | infra (new repo) | Uploads service (Go) — `~/DEV/fCC-U/uploads`                 | [`dispatches/T31-uploads-service.md`](dispatches/T31-uploads-service.md)                           | [ ] pending                                                                                                              |
| T32       | universe-cli     | v0.4 rewrite — proxy client (`feat/proxy-pivot`)             | [`dispatches/T32-cli-v04-rewrite.md`](dispatches/T32-cli-v04-rewrite.md)                           | [ ] pending                                                                                                              |
| T33       | universe-cli     | `platform.yaml` v2 schema + validator                        | [`dispatches/T33-platform-yaml-v2.md`](dispatches/T33-platform-yaml-v2.md)                         | [ ] pending                                                                                                              |
| T34       | infra            | Caddy reverse proxy + DNS prep + smoke retarget              | [`dispatches/T34-caddy-dns-smoke.md`](dispatches/T34-caddy-dns-smoke.md)                           | [ ] pending                                                                                                              |
| T15       | infra            | Phase 4 smoke runbook + script                               | [`dispatches/archive/T15-smoke-runbook.md`](dispatches/archive/T15-smoke-runbook.md)               | [x] artifact done; live run = G1.1.smoke                                                                                 |
| T-r2alias | infra/caddy-s3   | r2_alias dot-scheme migration + GH Actions canonical builder | [`dispatches/archive/T-r2alias-dot-scheme.md`](dispatches/archive/T-r2alias-dot-scheme.md)         | [x] done 2026-04-26 — D35 module fix; image `sha-712c6e3` deployed; namespace flipped to `freecodecamp/caddy-s3`         |
| T16       | universe-cli     | Woodpecker API client                                        | [`dispatches/archive/T16-woodpecker-client.md`](dispatches/archive/T16-woodpecker-client.md)       | [x] done                                                                                                                 |
| T17       | universe-cli     | Config schema + site name validation                         | [`dispatches/archive/T17-cli-config.md`](dispatches/archive/T17-cli-config.md)                     | [x] done                                                                                                                 |
| T18       | universe-cli     | Rewrite `deploy` command                                     | [`dispatches/archive/T18-cli-deploy.md`](dispatches/archive/T18-cli-deploy.md)                     | [x] done                                                                                                                 |
| T19       | universe-cli     | Rewrite `promote` + `rollback`                               | [`dispatches/archive/T19-cli-promote-rollback.md`](dispatches/archive/T19-cli-promote-rollback.md) | [x] done                                                                                                                 |
| T20       | universe-cli     | Strip legacy rclone/S3 + release 0.4.0-beta.1                | [`dispatches/archive/T20-cli-strip-cut.md`](dispatches/archive/T20-cli-strip-cut.md)               | [x] done — #25 unblocks                                                                                                  |
| T21       | infra            | `.woodpecker/deploy.yaml` template                           | [`dispatches/archive/T21-woodpecker-template.md`](dispatches/archive/T21-woodpecker-template.md)   | **SUPERSEDED 2026-04-26 by D016.** Demoted to optional reference example; not critical path post-pivot.                  |
| T22       | windmill         | Cleanup cron flow                                            | [`dispatches/T22-cleanup-cron.md`](dispatches/T22-cleanup-cron.md)                                 | [ ] pending                                                                                                              |

**Out-of-scope / closed:**

- **T14** (CF IP refresh cron) — descoped 2026-04-22 per Q4. No dispatch.
- **T32** (Woodpecker DNS + CF Access + admin users) — verified live 2026-04-22. No dispatch.
- Caddy module tasks T01/T01b/T02/T03/T04/T05 — shipped 2026-04-18 bootstrap. Verified live on gxy-cassiopeia caddy-s3 image.

## Wave A staggered dispatch graph (post-pivot 2026-04-26)

```
PRIOR WAVE A (closed) ─ Wave A.1 (serve plane) ✅  | Wave A.2 (CLI v0.4-beta.1) ✅ archaeology

D016 PIVOT — 2026-04-26 (broken ownership; session governs)
        │
        ▼
T30 (D016 ADR draft) ──→ T31 (uploads svc Go scaffold + endpoints + tests)
                                           │
                                           ▼
                          T32 (CLI v0.4 fresh proxy-client) ─┐
                          T33 (platform.yaml v2 schema)  ───┤
                                                            ▼
                                            T34 (Caddy + DNS + smoke retarget — operator deploys)
                                                            │
                                                            ▼
                                                Wave B fanout: T22 (cleanup cron, unchanged)
                                                            │
                                                            ▼
                                                       Sprint G1 close
```

Notes:

- T30 → T31 serial (ADR locks shape before Go code).
- T32 + T33 parallel within universe-cli repo on `feat/proxy-pivot` branch.
- T34 blocks on T31 (chart values reference uploads svc image tag).
- T22 (cleanup cron) independent of upload path; can land anytime, blocks on T31 only for live verification (admin token shared via Resource).
- v0.3 R2-token CLI keeps serving until v0.4 publishes.
- Old `feat/woodpecker-pivot` branch in universe-cli = orphaned. Never merged. Archaeology only.

## Wave B parallel fanout (post-pivot 2026-04-26)

Replaced by post-pivot graph above. Wave B is now just T22 (cleanup
cron) which is upload-path agnostic. T21 demoted to optional reference;
T18/T19/T20 superseded by T32 fresh-branch rewrite.

## Worker ↔ repo map (post-pivot 2026-04-26)

- **Governing session** (broken ownership 2026-04-26) drives all T30–T34 across 4 repos.
  - `~/DEV/fCC-U/Universe` branch `main` — T30 (D016 ADR). Cross-repo authorized.
  - `~/DEV/fCC-U/uploads` (NEW; branch `main`) — T31 (uploads svc). Greenfield.
  - `~/DEV/fCC-U/universe-cli` branch `feat/proxy-pivot` (NEW off `main`) — T32 + T33.
  - `~/DEV/fCC/infra` branch `feat/k3s-universe` — T34 (Caddy + DNS + smoke + sprint docs).
  - `~/DEV/fCC-U/windmill` branch `main` — T22 (cleanup cron, post-T31 for live verify) + boneyard headers on T11 source.
- **Archaeology branches** (do not merge): `universe-cli@feat/woodpecker-pivot`.

**Stagger discipline:** broken ownership = single session. T30 → T31 serial. T32 + T33 parallel within same branch (different file tracks). T34 blocks on T31 image tag. T22 last (post live proxy).

## Dispatch instructions

- **Per-sub-task dispatch:** open `dispatches/T<N>-<slug>.md`. Body
  cross-references `docs/architecture/task-gxy-cassiopeia.md`
  (acceptance criteria source of truth) + RFC §sections + Q-deltas.
- **Status flow:** worker flips dispatch-doc Status header
  `pending → in-progress` on start, `→ done` on closure. Same commit
  updates the matrix row in this PLAN.
- **Commit policy:** TDD per `.claude/rules/code-quality.md`
  (RED → GREEN → REFACTOR). One commit per sub-task close. Title-only
  per `cmd-git-rules`. Operator pushes at sprint close, not per task.
- **Close-out:** when all matrix rows show `[x] done` + G1 smoke green
  → MASTER G1 ticks → #25 unblocks.

## Success criteria (MVP done)

1. Staff push to Universe-org repo following `.woodpecker/deploy.yaml` template.
2. Woodpecker on gxy-launchbase builds + uploads to R2 `universe-static-apps-01/<site>/deploys/<ts>-<sha>/`.
3. Pipeline writes alias atomically → `<site>/production` + `<site>/preview`.
4. `<site>.freecode.camp` request: CF → gxy-cassiopeia Caddy → `r2_alias` → R2 object served.
5. `universe rollback --to <deploy-id>` repoints alias; green ≤ 2 min.
6. `universe promote` swaps production to current preview atomically.
7. 7d cleanup cron deletes unreferenced prefixes; aliased prefixes pinned.
8. gxy-static retired, DNS fully on gxy-cassiopeia.
9. `@freecodecamp/universe-cli@0.4.0-beta.1` published on npm.
10. Staff-facing "how to deploy a static site" playbook published.

## Cross-references

| Doc                                                   | Role                             |
| ----------------------------------------------------- | -------------------------------- |
| `STATUS.md`                                           | Live cursor (read first)         |
| `DECISIONS.md`                                        | Locked Q/D rows + amendments     |
| `HANDOFF.md`                                          | Append-only history log          |
| `cluster-audit.md`                                    | Cost/HA/autoscaling inventory    |
| `dispatches/`                                         | Per-task briefs                  |
| `../../architecture/rfc-secrets-layout.md`            | Secrets layout (implemented)     |
| `../../architecture/rfc-gxy-cassiopeia.md`            | RFC w/ D33–D40 amendments        |
| `../../architecture/task-gxy-cassiopeia.md`           | Task acceptance source of truth  |
| `../../flight-manuals/gxy-management.md`              | Doomsday rebuild (inc. Windmill) |
| `../../flight-manuals/gxy-cassiopeia.md`              | Doomsday rebuild (R2 + Caddy)    |
| `../../flight-manuals/gxy-launchbase.md`              | Doomsday rebuild (Woodpecker)    |
| `../../runbooks/cluster-rename-mgmt-to-management.md` | Executed; archived as reference  |
| `../../TODO-park.md`                                  | Deferred work                    |
| `~/DEV/fCC-U/Universe/decisions/`                     | ADR set (Universe team owns)     |
| `~/DEV/fCC-U/Universe/spike/spike-plan.md`            | Master delivery plan (upstream)  |
| `~/DEV/fCC-U/Universe/spike/field-notes/infra.md`     | Append-only infra journal        |

## Non-obvious invariants (carry forward)

- **k3s clusters are hand-rolled, not DOKS.** `doctl kubernetes cluster kubeconfig save` does NOT apply. Per-cluster kubeconfig at `k3s/<cluster>/.kubeconfig.yaml` (loaded by direnv via `expand_path`). Operator pattern: `cd k3s/<cluster>` or `direnv exec k3s/<cluster> kubectl ...`. No `kubectl --context <cluster>`. Cluster reach via Tailscale (server URL `https://100.64.x.x:6443`). Restoration: `just kubeconfig-sync <cluster>` decrypts from `infra-secrets/k3s/<cluster>/kubeconfig.yaml.enc` (where present); cassiopeia kubeconfig.enc not yet seeded — reseed via `scp <node>:/etc/rancher/k3s/k3s.yaml`.
- Three-form galaxy naming: repo-dir (`gxy-management`), ansible group underscore (`gxy_management_k3s`), DO droplet tag dash (`gxy-management-k3s`). Inventory plugin regex_replace bridges.
- `.envrc` hierarchy: root loads global tokens (CF, Tailscale); cluster dir `.envrc` loads team-specific DO token from `do-universe/.env.enc`. Run cluster-scoped `ansible`/`kubectl` with `direnv exec <cluster-dir>` when not cd'd in.
- `just play <name> <group>` expands to `play-<name>.yml` against `<group>`; `*args` forwarded verbatim (no `-- --check` separator).
- Windmill backup local path truncates on streaming pipe; prefer S3 CronJob artifact (in-pod dump → `aws s3 cp`).
- Helm chart repos at `k3s/<cluster>/apps/<app>/charts/<chart>/repo`; absence → local chart dir.
- PSS admission exempt: `windmill` + `tailscale` namespaces.
- Caddy Gateway listener ports must match Traefik entrypoint ports (80/443 with hostNetwork).
- `rtk` mandatory for verbose Bash; context-mode sandbox for >20 line outputs.
- Operator pushes. Session never `git push` / `gh pr create`.
- bun PATH NOT in shell — workers run `bunx wmill ...` from windmill repo cwd (devDep `windmill-cli@1.684.1`).
- `wmill sync push` is destructive; never dismiss deletion warnings.
- sops stateful: `sops decrypt --in-place` → yq → `sops encrypt --in-place`.

## Close criteria

Sprint closed when: G0 ✅, G1 ✅, G2 ✅, G3 ✅, dir moved to
`archive/`, field-notes journal entry landed.
