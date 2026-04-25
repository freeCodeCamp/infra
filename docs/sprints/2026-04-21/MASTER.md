# Sprint 2026-04-21 — MASTER dispatch plan

**Sprint goal:** Ship Universe static-apps MVP. Staff push → site live on
`<site>.freecode.camp` via Woodpecker → R2 → Caddy(`r2_alias`) on
gxy-cassiopeia. Preview siblings at `<site>.preview.freecode.camp`.
Retire gxy-static.

**Status:** Phase 0 complete (docs + rename + audit + QA). Phase 1 open
(MASTER + MVP chain).

**Branch/repos:**

- infra `feat/k3s-universe` (this doc's home)
- universe-cli `feat/woodpecker-pivot`
- windmill `main`
- infra-secrets private sibling

**Tracking model (2026-04-25):** filesystem-driven. Per-task dispatch
docs at `dispatches/T<N>-<slug>.md` carry status header
(`pending → in-progress → done`). Sprint matrix in
[`24-static-apps-k7d.md`](24-static-apps-k7d.md). Beads + bead IDs
deprecated for this sprint (epic `gxy-static-k7d` left at `running`,
unused).

**Resumption:** Fresh session → read `HANDOFF.md` first, then this
`MASTER.md`, then `QA-recommendations.md`. Cluster-audit backlog in
`cluster-audit.md`.

---

## Locked decisions (2026-04-22)

Source: `QA-recommendations.md` — all 8 accepted. Closed tasks #28–#35.

| Q   | Topic                | Decision                                                                                |
| --- | -------------------- | --------------------------------------------------------------------------------------- |
| Q1  | Alias-write          | Woodpecker pipeline step (atomic last step)                                             |
| Q2  | CF R2 admin cred     | `infra-secrets/windmill/.env.enc` (D33 amended ×2 2026-04-25; Bearer + Account ID only) |
| Q3  | Per-site secrets     | Woodpecker repo-scoped secrets only — D40 supersedes D34 (no infra-secrets path)        |
| Q4  | Origin IP allow-list | DO Cloud Firewall only; no CF-IP allow-list; no per-galaxy split                        |
| Q5  | Staff-site DNS       | `<site>.freecode.camp` prod + `<site>.preview.freecode.camp` preview                    |
| Q6  | Rollback SLO         | ≤ 2 minutes (CF LRU 60s + 30s smoke poll × 2 green hits)                                |
| Q7  | Preview envs         | Both prod + preview in MVP (certs pre-issued via ACM → CF activated)                    |
| Q8  | Cleanup retention    | Hard 7d; both aliases pin their prefix                                                  |

**Cert posture:** `*.freecode.camp` + `*.preview.freecode.camp` CF Origin
certs already live on Cloudflare. No registrar/CF work for MVP path.

---

## Galaxy role matrix (MVP scope)

| Galaxy         | State                    | Role this sprint                                           |
| -------------- | ------------------------ | ---------------------------------------------------------- |
| gxy-management | Live (DO FRA1)           | Windmill + Zot + (ArgoCD deferred → TODO-park)             |
| gxy-launchbase | Live (DO FRA1)           | Woodpecker pipeline host — builds + writes alias + uploads |
| gxy-cassiopeia | Live (DO FRA1)           | Caddy + R2 serve plane for `*.freecode.camp(+.preview)`    |
| gxy-static     | Live → retire at cutover | Legacy static sandbox; DNS moves to cassiopeia             |

Out of sprint: gxy-triangulum, gxy-backoffice, legacy fCC clusters.

---

## Task matrix

Dependency chain: **#23 → #24 → #25 → #26**. #27 standing.

| ID      | Subject                                                           | Status     | Blocks  |
| ------- | ----------------------------------------------------------------- | ---------- | ------- |
| #17     | Docs foundation (GUIDELINES + field-notes + flight-manuals split) | **done**   | —       |
| #18     | ADR amendments in-place (ADR-001/003/007/008/011/013 + D22/D32)   | **done**   | —       |
| #19     | `docs/TODO-park.md` deferment list                                | **done**   | —       |
| #20     | Deep cluster audit (cost + HA + autoscaling)                      | **done**   | —       |
| #21     | Rename runbook `gxy-mgmt → gxy-management`                        | **done**   | #22     |
| #22     | Execute rename via reprovision                                    | **done**   | #23+    |
| #23     | MASTER sprint plan (this file)                                    | **done**   | #24     |
| #24     | MVP static-apps E2E chain                                         | pending    | #25 #26 |
| #25     | Release `@freecodecamp/universe-cli@0.4.0-beta.1`                 | pending    | #26     |
| #26     | DNS cutover gxy-static → gxy-cassiopeia + teardown gxy-static     | pending    | —       |
| #27     | Recurring monthly doc trim (standing)                             | standing   | —       |
| #28–#35 | Q/A brainstorm decisions (Q1–Q8)                                  | **closed** | —       |

---

## Phases + gates

### Phase 0 — Foundation (DONE)

- [x] Docs conventions + ownership codified (GUIDELINES)
- [x] ADR amendments landed (Universe repo, pushed)
- [x] Cluster audit + deferment list
- [x] Rename runbook authored + executed (#21 + #22)
- [x] RFC secrets-layout accepted + Phases 1–7 shipped
- [x] QA brainstorm decisions locked (#28–#35)
- [x] MASTER sprint plan written (this file, #23)

**Gate G0:** cluster gxy-management GREEN post-rename, Windmill restored
from S3 dump, UI smoke 200. **PASSED.**

### Phase 1 — MVP static-apps chain (#24)

Cover sheet: `24-static-apps-k7d.md` (to be written next; derives from
`docs/architecture/task-gxy-cassiopeia.md` task breakdown + QA decisions).

Sub-deliverables:

1. **P1.1 — Woodpecker `.woodpecker/deploy.yaml` template**
   - Builds static output, uploads to
     `universe-static-apps-01/<site>/deploys/<ts>-<sha>/`.
   - Last step writes alias files `<site>/production` + `<site>/preview`
     atomically (per Q1 + Q7).
   - Per-site data-plane token sourced from Woodpecker repo-scoped
     secrets `r2_access_key_id` + `r2_secret_access_key` (Q3 / D40).
   - Admin provisioning token at `infra-secrets/windmill/.env.enc` —
     `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID` (Q2 / D33×2).
2. **P1.2 — Caddy `r2_alias` on gxy-cassiopeia**
   - Verify `caddy.fs.r2` + `http.handlers.r2_alias` modules live in
     running image.
   - Per-request alias lookup with 60s LRU (meets Q6 SLO ≤ 2 min).
3. **P1.3 — DNS wiring**
   - Onboarding flow provisions `<site>.freecode.camp` + preview A records
     → cassiopeia public IPs. CF proxied. SSL Full Strict via the two
     pre-issued wildcard Origin certs.
4. **P1.4 — Cleanup cron (Windmill flow on gxy-management)**
   - 7d retention; both aliases pin prefix (Q8).
5. **P1.5 — Firewall posture (Q4)**
   - `gxy-fw-fra1` 80/443 open to `0.0.0.0/0`. No CF-IP diff cron.
6. **P1.6 — Smoke harness**
   - `universe promote <site>` + `universe rollback --to <deploy-id>`
     poll at 30s intervals, green after 2 consecutive 200s.

**Gate G1:** End-to-end staff push → site live → rollback → promote →
cleanup exercised against one reference repo. Smoke harness green.

### Phase 2 — Release (#25)

- Strip legacy rclone/S3 paths from universe-cli.
- Bump `0.4.0-beta.1`, publish to npm.
- CHANGELOG + README ported to new CLI contract.

**Gate G2:** `npm i -g @freecodecamp/universe-cli@0.4.0-beta.1` works;
`universe deploy` + `universe rollback` + `universe promote` drive the
Woodpecker-owned flow against G1 reference site.

### Phase 3 — Cutover (#26)

- Flip DNS for existing `*.freecode.camp` users from gxy-static to
  gxy-cassiopeia.
- Teardown gxy-static (VMs + DNS + Caddy chart).
- Archive gxy-static flight-manual note.

**Gate G3:** gxy-static destroyed; no 404s for pre-existing sandbox sites
during 24h observation window; `doctl compute droplet list` shows no
`gxy-static-k3s` tagged droplets.

### Phase 4 — Close

- Move `docs/sprints/2026-04-21/` → `docs/sprints/archive/2026-04-21/`.
- Final field-notes journal entry (`Universe/spike/field-notes/infra.md`).
- `#27` recurring monthly doc trim kept standing.

---

## Success criteria (MVP done)

1. Staff push to Universe-org repo following `.woodpecker/deploy.yaml`
   template.
2. Woodpecker on gxy-launchbase builds + uploads to R2
   `universe-static-apps-01/<site>/deploys/<ts>-<sha>/`.
3. Pipeline writes alias atomically → `<site>/production` +
   `<site>/preview`.
4. `<site>.freecode.camp` request: CF → gxy-cassiopeia Caddy →
   `r2_alias` → R2 object served.
5. `universe rollback --to <deploy-id>` repoints alias; green ≤ 2 min.
6. `universe promote` swaps production to current preview atomically.
7. 7d cleanup cron deletes unreferenced prefixes; aliased prefixes pinned.
8. gxy-static retired, DNS fully on gxy-cassiopeia.
9. `@freecodecamp/universe-cli@0.4.0-beta.1` published on npm.
10. Staff-facing "how to deploy a static site" playbook published.

---

## Dispatch references

| Doc                                                   | Role                                 |
| ----------------------------------------------------- | ------------------------------------ |
| `HANDOFF.md`                                          | Resumption context (session-level)   |
| `QA-recommendations.md`                               | Locked decisions (read-only now)     |
| `cluster-audit.md`                                    | Cost/HA/autoscaling inventory        |
| `../../architecture/rfc-secrets-layout.md`            | Secrets layout (implemented)         |
| `../../architecture/task-gxy-cassiopeia.md`           | Task breakdown source for #24 P1.\*  |
| `../../flight-manuals/gxy-management.md`              | Doomsday rebuild (inc. Windmill 3.5) |
| `../../flight-manuals/gxy-cassiopeia.md`              | Doomsday rebuild (R2 + Caddy)        |
| `../../flight-manuals/gxy-launchbase.md`              | Doomsday rebuild (Woodpecker)        |
| `../../runbooks/cluster-rename-mgmt-to-management.md` | Executed; archived as reference      |
| `../../TODO-park.md`                                  | Deferred work (ArgoCD, Zot push…)    |
| `~/DEV/fCC-U/Universe/decisions/`                     | ADR set (Universe team owns)         |
| `~/DEV/fCC-U/Universe/spike/spike-plan.md`            | Master delivery plan (upstream)      |
| `~/DEV/fCC-U/Universe/spike/field-notes/infra.md`     | Append-only infra journal            |

---

## Non-obvious invariants (carry forward)

- Three-form galaxy naming: repo-dir (`gxy-management`), ansible group
  underscore (`gxy_management_k3s`), DO droplet tag dash
  (`gxy-management-k3s`). Inventory plugin regex_replace bridges.
- `.envrc` hierarchy: root loads global tokens (CF, Tailscale); cluster
  dir `.envrc` loads team-specific DO token from
  `do-universe/.env.enc`. Run cluster-scoped `ansible`/`kubectl` with
  `direnv exec <cluster-dir>` when not cd'd in.
- `just play <name> <group>` expands to `play-<name>.yml` against
  `<group>`; `*args` forwarded verbatim (no `-- --check` separator).
- Windmill backup local path truncates on streaming pipe; prefer S3
  CronJob artifact (in-pod dump → `aws s3 cp`).
- Helm chart repos at `k3s/<cluster>/apps/<app>/charts/<chart>/repo`;
  absence → local chart dir.
- PSS admission exempt: `windmill` + `tailscale` namespaces.
- Caddy Gateway listener ports must match Traefik entrypoint ports
  (80/443 with hostNetwork).
- `rtk` mandatory for verbose Bash; context-mode sandbox for >20 line
  outputs.
- Operator pushes. Session never `git push` / `gh pr create`.

---

## Close criteria

Sprint closed when: G0 ✅, G1 ✅, G2 ✅, G3 ✅, dir moved to
`archive/`, field-notes journal entry landed.
