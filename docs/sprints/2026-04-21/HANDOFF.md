# Sprint 2026-04-21 — Session Handoff

Read this first when resuming in a fresh Claude Code session. Session-local
context for continuing Universe static-apps MVP work.

## Start-here checklist (fresh session)

1. Read this file end-to-end.
2. Read [`MASTER.md`](MASTER.md) — dispatch checklist + phase gates.
3. Read [`QA-recommendations.md`](QA-recommendations.md) — locked operator
   decisions (Q1–Q8, accepted 2026-04-22).
4. Read `docs/GUIDELINES.md` — doc conventions.
5. Run `TaskList`. If empty (fresh controller session), compile from
   the [2026-04-25 Wave A dispatch TaskList](#2026-04-25--wave-a-dispatch-tasklist-compile-in-fresh-session)
   section below — 17 tasks, dependency graph included. (Sprint-level
   bead tasks #17–#35 separately tracked in beads epic
   `gxy-static-k7d`.)
6. Verify live cluster state still matches [Galaxy state](#galaxy-state)
   (helm releases + droplets drift over time).
7. Epic `gxy-static-k7d` stage = `running` (promoted 2026-04-22). Ready
   to dispatch MVP sub-tasks.

## Session context (rolling)

### 2026-04-25 (later same day) — D33 second amendment + infra-secrets README rewrite

Structure deep-audit caught error in earlier same-day amendment.
First-pass D33 moved admin token from invented `platform/` dir to
`global/.env.enc` (canonical home for CF tokens per RFC). But
`global/.env.enc` is direnv-loaded into operator shell on every
`cd infra/`, leaking the admin token into every shell session.

**Corrected:** admin token home is `infra-secrets/windmill/.env.enc`
— activates the previously-empty reserved Universe-platform-app
namespace per `rfc-secrets-layout.md` D4. NOT loaded into shell
(consumed on-demand via `sops -d` or `wmill resource push`).

Changes this round:

- **RFC `rfc-gxy-cassiopeia.md`** — D33 row rewritten to point at
  `windmill/.env.enc`; "Amendments (2026-04-25)" section now lists
  both 1st-pass and 2nd-pass amendments with rationale.
- **`windmill-t11-dispatch.md`** — top amendment matrix + Locked
  Decisions D33 row + Operator bootstrap §1-§7 all reflect
  `windmill/.env.enc` (was `global/.env.enc` mid-session).
  Smoke-curl + commit message updated. Step 2 now creates the file
  (first-time activation) instead of editing existing.
- **`infra-secrets/README.md`** — major augmentation:
  - New §"Layout principles (read once, apply forever)" with 5 rules
    (two-scope, sample-twin discipline, direnv-vs-app-consumed,
    coexistence, single age recipient).
  - New §"Adding a new secret — decision tree" (Q1–Q6) routes any
    new secret to its canonical home.
  - New §"Activation status (Universe namespaces)" table tracks
    `argocd/` reserved, `windmill/` **active** (T11), `zot/` reserved.
  - New §"Worked example: activating the windmill/ namespace (T11
    CF R2 provisioner)" — canonical activation pattern, including
    rotation + rollback.
  - New §"In-repo encrypted secrets (windmill repo)" clarifies
    relationship between this repo's source-of-truth `.enc` files
    and the windmill repo's deployment-artifact `.resource.yaml` /
    `.variable.yaml` encrypted-value-only files.
- **T17 task description** updated to reference revised dispatch
  bootstrap (now 7 steps targeting `windmill/`).

**Sprint-doc patches still owed by T11 worker** (unchanged, just
refreshed for `windmill/.env.enc` paths): 24-static, MASTER, QA-rec.

### 2026-04-25 — Wave A staggered dispatch plan + D33/D40 amendments

Sprint dispatch shifted from "fire all 3 in parallel" to **staggered
Wave A** (one worker at a time, observe + verify before next launch).
Cause: T11 dispatch doc had drifted from `rfc-secrets-layout.md`
two-scope convention; structure audit caught it before any worker
fired. Decisions recorded:

- **D33 amended in place** (RFC `rfc-gxy-cassiopeia.md`): admin token
  path moved `platform/cf-r2-provisioner.secrets.env.enc` →
  `global/.env.enc`. Vars reduced to **two** —
  `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`. S3-style admin Access
  Key/Secret dropped (flow uses CF Bearer only).
- **D34 superseded by new D40**: per-site R2 secrets persist
  **only** in Woodpecker (D22 channel). No `constellations/` dir, no
  `.sops.yaml` rule. Re-mint via CF API is the recovery path.
  Offline backup deferred to TODO-park.
- Windmill T11 dispatch (`windmill-t11-dispatch.md`) prefixed with
  override matrix + revised operator bootstrap (5 numbered steps incl.
  smoke curl); §D / §F2-F6 / §G1-G2 / §H1 / §I4-I5 / §J5-J6 acceptance
  rows marked OBSOLETE.
- T11 worker owes sprint-doc patch (commit-only) at closure:
  `24-static-apps-k7d.md`, `MASTER.md`, `QA-recommendations.md` (append
  amendment block, do NOT rewrite locked Q2/Q3 prose).
- bun PATH NOT in shell — workers run `bunx wmill ...` from windmill
  repo cwd (devDep `windmill-cli@1.684.1`).

### 2026-04-25 — Wave A dispatch TaskList (compile in fresh session)

Use this section to recreate the controller-side TaskList. All work
runs through `claude-session-driver` (scripts at
`~/.claude/plugins/cache/superpowers-marketplace/claude-session-driver/1.0.1/scripts/`).

**Dependency graph:**

```
1  Preflight ✓
   ↓
17 OPERATOR BOOTSTRAP (CF Bearer + windmill/.env.enc)
   ↓ (gates 2)
8  Launch w-infra ──→ 9 Brief T15 ──→ 10 Observe ✓
                                          ↓
                                       (gates 5)
   ↓
5  Launch w-cli ──→ 6 Brief T16+T17 ──→ 7 Observe ✓
                                          ↓               ↓
                                       (gates 2)      12 T18 ──→ 13 T19 ──→ 14 T20
   ↓
2  Launch w-windmill ──→ 3 Brief T11 ──→ 4 Observe ✓
                                            ↓               ↓
                                         11 T22         15 T21 (gated on 4 + 10)
                                            ↓
                                        16 Cleanup (gated on 11 + 14 + 15)
```

**TaskList rows** (subject — description summary — blockedBy):

| #   | Subject                                                              | Description summary                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | blockedBy  |
| --- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| 1   | Preflight: verify direnv + secrets loaded in 3 repos                 | Check direnv loaded in windmill / cli / infra; tools sops/age/wmill/doctl present; infra-secrets dirs sane                                                                                                                                                                                                                                                                                                                                                                                          | —          |
| 17  | OPERATOR BOOTSTRAP: seed CF R2 provisioner cred in windmill/.env.enc | Manual ClickOps. Steps in `docs/sprints/2026-04-21/windmill-t11-dispatch.md §"Operator bootstrap (BEFORE T11 starts) — REVISED 2026-04-25 (×2)"`. 7 steps: mint CF Account-owned API Token (perm `Account → R2 Storage → Edit`) + author `windmill/.env.sample` (sample-twin) + create `windmill/.env.enc` via sops + smoke-curl + commit no push + register Windmill Resource `u/admin/cf_r2_provisioner`. Activates reserved `windmill/` namespace per `infra-secrets/README.md` §Worked example. | 1          |
| 8   | Wave A.3: Launch w-infra worker                                      | `launch-worker.sh w-infra ~/DEV/fCC/infra`                                                                                                                                                                                                                                                                                                                                                                                                                                                          | 1          |
| 9   | Wave A.3: Brief w-infra with T15 smoke runbook dispatch              | T15 = Phase 4 test-site smoke runbook + script. Bead `gxy-static-k7d.16`. Build `docs/runbooks/smoke-static-site.md` + `scripts/smoke/static-site.sh`. Poll 30s × 2 green per Q6 SLO                                                                                                                                                                                                                                                                                                                | 8          |
| 10  | Wave A.3: Observe T15 to completion + verify evidence                | Wait stop event; verify runbook + script committed, bash -n clean, dry-run executes, bead .16 closed with evidence                                                                                                                                                                                                                                                                                                                                                                                  | 9          |
| 5   | Wave A.2: Launch w-cli worker                                        | `launch-worker.sh w-cli ~/DEV/fCC-U/universe-cli`. Confirm branch `feat/woodpecker-pivot`                                                                                                                                                                                                                                                                                                                                                                                                           | 10         |
| 6   | Wave A.2: Brief w-cli with T16 + T17 dispatch                        | T16 (bead .17) = Woodpecker API client. T17 (bead .18) = config schema + site-name validation per D19 regex. TDD red-green-refactor                                                                                                                                                                                                                                                                                                                                                                 | 5          |
| 7   | Wave A.2: Observe T16+T17 to completion + verify evidence            | vitest green, eslint/oxlint clean, beads .17+.18 closed with evidence, commits on feat/woodpecker-pivot                                                                                                                                                                                                                                                                                                                                                                                             | 6          |
| 2   | Wave A.1: Launch w-windmill worker                                   | `PATH not needed inline — worker uses bunx wmill`. `launch-worker.sh w-windmill ~/DEV/fCC-U/windmill`                                                                                                                                                                                                                                                                                                                                                                                               | 7, 10, 17  |
| 3   | Wave A.1: Brief w-windmill with T11 dispatch                         | Paste FULL `windmill-t11-dispatch.md` (post-amendment) as opening prompt. Bead .12. Honor amendment matrix + Operator bootstrap §7 (sprint-doc patches owed)                                                                                                                                                                                                                                                                                                                                        | 2          |
| 4   | Wave A.1: Observe T11 to completion + verify evidence                | vitest green, oxfmt+oxlint clean, `wmill sync push --dry-run` zero deletions, MCP preview green, bead .12 closed, sprint docs patched (24/MASTER/QA-rec/HANDOFF), commit on main no push                                                                                                                                                                                                                                                                                                            | 3          |
| 11  | Wave B.windmill: T22 cleanup cron flow                               | Same w-windmill worker. T22 = R2 cleanup cron, 7d retention, prefix-pin both aliases per Q8. Bead .23                                                                                                                                                                                                                                                                                                                                                                                               | 4          |
| 12  | Wave B.cli: T18 deploy rewrite                                       | Same w-cli worker. Rewrite `deploy` consuming T16 client + T17 config. Bead .19                                                                                                                                                                                                                                                                                                                                                                                                                     | 7          |
| 13  | Wave B.cli: T19 promote + rollback rewrite                           | Bead .20                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | 12         |
| 14  | Wave B.cli: T20 strip legacy + cut 0.4.0-beta.1                      | Strip rclone/S3 + bump pkg version + CHANGELOG. Bead .21. NO `npm publish` — operator handles                                                                                                                                                                                                                                                                                                                                                                                                       | 13         |
| 15  | Wave B.infra: T21 .woodpecker/deploy.yaml template                   | Same w-infra worker. 10-step atomic promote pipeline. Bead .22. Consumes T11 R2 secret format (Woodpecker repo secret names `r2_access_key_id` + `r2_secret_access_key`).                                                                                                                                                                                                                                                                                                                           | 4, 10      |
| 16  | Cleanup: stop all 3 workers + sprint state audit                     | `stop-worker.sh × 3`, audit `dp_beads_show gxy-static-k7d`, update HANDOFF rolling log                                                                                                                                                                                                                                                                                                                                                                                                              | 11, 14, 15 |

**Worker ↔ repo map:**

- `w-windmill` → `~/DEV/fCC-U/windmill` branch `main`. Tasks: T11, T22.
- `w-cli` → `~/DEV/fCC-U/universe-cli` branch `feat/woodpecker-pivot`. Tasks: T16→T17→T18→T19→T20.
- `w-infra` → `~/DEV/fCC/infra` branch `feat/k3s-universe`. Tasks: T15, T21.

**Stagger discipline:** never launch next worker until prior Observe-✓
passes. If any acceptance fails → halt, diagnose, re-brief same worker
or kill + restart. Never run 2 workers in same repo (git race).

**Auto-approve tools:** Default ON (PreToolUse 30s window). Override
to manual via `approve-tool.sh <session-id> allow|deny` watching
`/tmp/claude-workers/<sid>.tool-pending`.

### 2026-04-22 — QA lock + rename dogfood + RFC amendments

- gxy-mgmt → gxy-management reprovision executed (#22 closed). Windmill
  restored from S3 CronJob dump (local backup truncation bug fixed in
  `justfile windmill-backup`).
- Dogfood gaps captured in `docs/flight-manuals/gxy-management.md`
  (new Phase 3.5 Windmill restore) + `Universe/spike/field-notes/infra.md`.
- QA brainstorm Q1–Q8 accepted; `QA-recommendations.md` marked
  ACCEPTED 2026-04-22. Tasks #28–#35 closed.
- MASTER.md written (#23 closed). #24 dispatch block written
  (`24-static-apps-k7d.md`).
- RFC amendments D33–D39 appended to `rfc-gxy-cassiopeia.md`:
  D5 superseded by D35 (`.preview` dot scheme); D29 superseded by
  D36 (DO FW only, no CF-IP allow-list).
- T14 bead `gxy-static-k7d.15` closed with Q4 descope reason.
- T32 bead `gxy-static-k7d.33` **still open** but verified live
  (see [T32 verification](#t32-verification-2026-04-22)).
- Epic `gxy-static-k7d` transitioned `speccing` → `running`
  (event `.36`).
- ArgoCD deployment deferred to TODO-park (not MVP crit-path).

### 2026-04-21 — Audit + reset

- `docs/sprints/2026-04-20/` scrapped; drifted from post-bootstrap reality.
- Fresh plan built around shipping static-apps E2E.
- Rename `gxy-mgmt` → `gxy-management` decided; acceptable dogfood path.
- Windmill permanent home = `gxy-management` (overrides ADR-001).
- CF Access dropped globally; OAuth org-gate canonical for native-OAuth
  tools. Resolves D22.
- Static-apps E2E = MVP. Dynamic, BM, o11y, BetterAuth deferred.
- ADR amendment ownership bypass granted (in-place this round).

### Galaxy role reassignments (stable)

| Galaxy         | Provider now | Provider future | Role                                  | Tools                                                       |
| -------------- | ------------ | --------------- | ------------------------------------- | ----------------------------------------------------------- |
| gxy-management | DO FRA1      | DO FRA1         | Control plane                         | Windmill + Zot + ArgoCD (deferred) + Atlantis               |
| gxy-launchbase | DO FRA1      | Hetzner         | Supply chain ("GitHub Actions layer") | Woodpecker (+ArgoCD TBD) + CI tooling                       |
| gxy-backoffice | TBD          | Hetzner         | Backoffice + o11y                     | VictoriaMetrics + ClickHouse + Vector + HyperDX + GlitchTip |
| gxy-cassiopeia | DO FRA1      | Hetzner         | Static hosting                        | Caddy + R2 (cassiopeia serves staff constellations)         |
| gxy-triangulum | —            | Hetzner         | Dynamic hosting ("Heroku-like")       | containers, CNPG prod, Ceph RGW future                      |

Deferred (not MVP): gxy-backoffice, gxy-triangulum.
Retiring: gxy-static at cassiopeia cutover (#26).
Out of scope: `ops-mgmt`, `ops-backoffice-tools` (legacy).

## Galaxy state (verified 2026-04-22)

### Naming conventions (post-rename — all three forms converged on `management`)

- **Repo dir:** `k3s/gxy-{management,static,launchbase,cassiopeia}/`
- **Ansible group:** `gxy_management_k3s`, `gxy_static_k3s`,
  `gxy_launchbase_k3s`, `gxy_cassiopeia_k3s`
- **DO droplet tag:** `gxy-management-k3s`, `gxy-static-k3s`,
  `gxy-launchbase-k3s`, `gxy-cassiopeia-k3s`
- **Droplet names:** `gxy-vm-{management,static,launchbase,cassiopeia}-k3s-{1,2,3}`

### Live clusters

All DO · FRA1 · k3s v1.34.5+k3s1 HA embedded etcd · Cilium 1.19.2 ·
Traefik 39.0.201+up39.0.2 (v3.6.9) + traefik-crd · PSS baseline · 3 nodes each.

| Galaxy         | Kubeconfig server            | Helm releases (chart / app ver)                                                         |
| -------------- | ---------------------------- | --------------------------------------------------------------------------------------- |
| gxy-management | `https://100.81.119.62:6443` | argocd (deferred — parked), windmill (windmill-4.0.134 / 1.686.0), restored post-rename |
| gxy-static     | legacy                       | caddy (caddy-static-0.1.0 / 2.9) — retires at #26 cutover                               |
| gxy-launchbase | (direnv-scoped)              | cnpg-system (cloudnative-pg-0.28.0 / 1.29.0), woodpecker (woodpecker-3.5.1 / 3.13.0)    |
| gxy-cassiopeia | (direnv-scoped)              | caddy (caddy-0.1.0 / 0.1.0) with in-tree `r2_alias` + `caddy.fs.r2`                     |

### External infra

- Cloudflare zones `freecodecamp.net` + `freecode.camp` — all origins proxied
- Origin certs: `*.freecodecamp.net`, `*.freecode.camp`,
  `*.preview.freecode.camp` (all ACM-issued, CF-activated)
- Object storage: CF R2 bucket `universe-static-apps-01`
- Secrets at rest: sops+age in sibling repo `infra-secrets`
- Admin plane: Tailscale (SSH + kubectl only; ADR-011)

### Live endpoints

- `https://woodpecker.freecodecamp.net` — 200, `x-woodpecker-version: 3.13.0`,
  CF-proxied, GitHub org-gate (CF Access off per commit `3875c02`)
- `https://argocd.freecodecamp.net` — HTTPRoute live; ArgoCD deploy deferred
  (parked)
- `https://windmill.freecodecamp.net` — HTTPRoute on gxy-management;
  restored from S3 dump 2026-04-22

### T32 verification (2026-04-22)

Probe results:

```
dig +short woodpecker.freecodecamp.net A @1.1.1.1
→ 172.67.180.88, 104.21.35.228  (CF proxy IPs)

curl -sI https://woodpecker.freecodecamp.net/
→ HTTP/2 200
  x-woodpecker-version: 3.13.0
  cf-cache-status: DYNAMIC
```

Verdict: T32 functionally complete. Bead `gxy-static-k7d.33` still open;
operator closes. Runbook `docs/runbooks/woodpecker-cf-access.md` kept for
when CF Access reactivated (if needed).

## Completed this round (audit trail)

Infra repo `feat/k3s-universe` — commits (operator pushed 2026-04-22):

- `e95f260` docs(guidelines): canonical doc conventions + monthly trim
- `6bfaf6d` docs(sprint/2026-04-21): seed handoff + README
- `f277aa9` docs: split FLIGHT-MANUAL.md per-cluster + reorg + archive 04-20
- `87fcdff` docs(park): seed deferment list
- `8914d69` docs(runbook): add gxy-mgmt → gxy-management rename runbook
- `25d33df` docs(sprint/2026-04-21): cluster audit (#20)
- `99bc332` docs(rename): correct rename scope + verify-grep exclusion
- `30f2205` docs(architecture): RFC secrets layout — two-scope (#36 Phase 1)
- `3465a9d` feat(secrets): RFC Phase 2b+3 — cluster.tls.zone markers
- `779ab28` fix(deploy): anchor cleanup trap to absolute paths (Phase 5)
- `cef8c8a` feat(windmill-backup): re-enable backup CronJob + fix image (Phase 5/7)
- `827bc7e` docs(secrets): sync flight-manuals + rename runbook (Phase 6)
- `9d49cda` refactor(naming): gxy-mgmt → gxy-management (repo refs only)
- `97b9c14` feat(infra): gxy-mgmt → gxy-management dogfood gaps
- `39d49b5` docs(sprint/2026-04-21): lock QA brainstorm decisions
- `6f3c84c` docs(sprint/2026-04-21): MASTER dispatch plan (#23)
- `3376e86` docs(sprint/2026-04-21): #24 MVP static-apps dispatch block
- `4c5e38b` docs(rfc-cassiopeia): append Q1-Q8 amendments as D33-D39

Universe repo `main` — 8 commits (pushed earlier sessions).
Remote now `freeCodeCamp-Universe/Universe-Architecture.git`.

## Task map

Ledger in Tasks API. If not present (session reset), recreate from below.

### Main track

| ID  | Subject                                                          | Status        |
| --- | ---------------------------------------------------------------- | ------------- |
| #17 | Docs foundation (GUIDELINES + field-notes + per-cluster manuals) | **completed** |
| #18 | ADR amendments in-place (bypass ownership)                       | **completed** |
| #19 | Write docs/TODO-park.md deferment list                           | **completed** |
| #20 | Deep cluster audit (cost + HA + autoscaling)                     | **completed** |
| #21 | Rename runbook: gxy-mgmt → gxy-management                        | **completed** |
| #22 | Execute rename via reprovision                                   | **completed** |
| #23 | MASTER sprint plan                                               | **completed** |
| #24 | MVP static-apps E2E chain                                        | pending       |
| #25 | Release @freecodecamp/universe-cli 0.4.0-beta.1                  | pending       |
| #26 | DNS cutover gxy-static → gxy-cassiopeia + teardown gxy-static    | pending       |
| #27 | Recurring monthly doc trim (standing)                            | standing      |

### Q/A brainstorm — LOCKED 2026-04-22

All 8 closed. Decisions in `QA-recommendations.md` summary table;
amended into `docs/architecture/rfc-gxy-cassiopeia.md` as D33–D39.

| ID    | Q   | Decision                                                   |
| ----- | --- | ---------------------------------------------------------- |
| #28 ✓ | Q1  | Woodpecker pipeline step                                   |
| #29 ✓ | Q2  | `infra-secrets/platform/cf-r2-provisioner.secrets.env.enc` |
| #30 ✓ | Q3  | `infra-secrets/constellations/<site>.secrets.env.enc`      |
| #31 ✓ | Q4  | DO Cloud Firewall only (no CF-IP allow-list)               |
| #32 ✓ | Q5  | `<site>.freecode.camp` + `<site>.preview.freecode.camp`    |
| #33 ✓ | Q6  | ≤ 2 minutes rollback SLO                                   |
| #34 ✓ | Q7  | Prod + preview both in MVP                                 |
| #35 ✓ | Q8  | Hard 7d cleanup; alias prefix-pin                          |

### Dependencies

Chain: **#24 → #25 → #26**. #27 standing.

## Deferment list

See [`docs/TODO-park.md`](../../TODO-park.md). MVP-out:

- Supply chain (Zot push, cosign, Grype+Trivy, Kyverno, SBOM)
- Atlantis on gxy-management
- BetterAuth + Account Service
- gxy-triangulum provisioning
- Hetzner migration (launchbase, backoffice, cassiopeia eventual)
- ArgoCD deployment on gxy-management (added 2026-04-22 — not crit-path)
- CNPG barman-cloud plugin
- DR runbook (ADR-012)
- Rook-Ceph
- `ops-*` legacy teardown
- gxy-backoffice provisioning + O11y stack

## Key file references

### Infra repo (`~/DEV/fCC/infra`, branch `feat/k3s-universe`)

- `CLAUDE.md` — project instructions + galaxy table
- `docs/flight-manuals/` — per-cluster rebuild manuals + `00-index.md`
- `docs/runbooks/` — `dns-cutover.md`, `gxy-launchbase.md`,
  `r2-bucket-provision.md`, `woodpecker-cf-access.md`,
  `cluster-rename-mgmt-to-management.md` (executed)
- `docs/architecture/`:
  - `rfc-secrets-layout.md` (accepted 2026-04-22)
  - `rfc-gxy-cassiopeia.md` (with 2026-04-22 D33–D39 amendments)
  - `task-gxy-cassiopeia.md` (source of truth for MVP sub-tasks)
  - `rfc-gxy-cassiopeia-caddyfile-poc.md`
- `docs/sprints/2026-04-21/` — this sprint
  - `HANDOFF.md` (this file) · `MASTER.md` · `README.md`
  - `QA-recommendations.md` · `cluster-audit.md` · `24-static-apps-k7d.md`
- `docs/sprints/archive/2026-04-20/` — scrapped
- `docs/TODO-park.md` — deferment ledger
- `ansible/` — playbooks, roles, inventory
- `k3s/<galaxy>/apps/<app>/charts/<chart>/` + `manifests/base/` +
  `values.production.yaml`
- `.claude/rules/` — code-quality + docs-ops rules
- `justfile` — `windmill-backup` hardened with in-pod dump + sentinel +
  `kubectl cp`

### Universe repo (`~/DEV/fCC-U/Universe`, branch `main`)

- `CLAUDE.md` (ownership model canonical)
- `decisions/001-015-*.md` — 15 ADRs
- `spike/field-notes/{infra,windmill,universe-cli}.md` — field notes
- `spike/spike-plan.md` · `spike/tool-validation.md`

### universe-cli repo (`~/DEV/fCC-U/universe-cli`, branch `feat/woodpecker-pivot`)

- Code shipped locally (commits `a7dd58e` + `f6971cf`) — Woodpecker
  client replaces direct R2; `@aws-sdk/client-s3` removed; bundle
  1.95 MB → 812 KB
- Version `0.3.3` on npm; `0.4.0-beta.1` release pending #25
- Branch diverged from `main` — merge before tagging

### Windmill repo (`~/DEV/fCC-U/windmill`, branch `main`)

- `workspaces/platform/f/` — existing flows (`app`, `github`,
  `google_chat`, `ops`, `repo_mgmt`)
- `workspaces/platform/f/static/` — does **not** exist yet. T11 creates:
  - `provision_site_r2_credentials.ts` + `.yaml` + `.test.ts`
- Dispatch doc: `docs/sprints/2026-04-21/windmill-t11-dispatch.md`
  (infra-repo authored; mirrors to windmill session start context)

### infra-secrets repo (private sibling — paths locked 2026-04-22)

- `platform/cf-r2-provisioner.secrets.env.enc` — **NEW** (D33, Q2).
  Admin-scope CF R2 token for bucket `universe-static-apps-01`;
  provisioner mints per-site tokens. Created during T11 implementation.
- `constellations/<site>.secrets.env.enc` — **NEW** (D34, Q3).
  Per-site data-plane token. Written by T11 Windmill flow.
- `.sops.yaml` creation_rule (land alongside T11):
  `path_regex: ^constellations/.*\.secrets\.env\.enc$` with platform
  age key.
- `k3s/gxy-launchbase/*.enc` — Woodpecker secrets (existing).
- `k3s/gxy-cassiopeia/caddy.values.yaml.enc` — R2 ro key bootstrap.

## Non-obvious invariants

- `rtk` tool mandatory for verbose Bash (per user CLAUDE.md)
- `caveman` output style active — drop articles/filler
- `context-mode` MCP routes >20-line outputs through sandbox
- **Never push from session; operator pushes.** (User pushed all infra
  commits through `4c5e38b` on 2026-04-22.)
- Never edit target files under `~/.claude/*` — edit source in
  `~/.dotfiles/`
- Epic `gxy-static-k7d` stage = `running` (promoted 2026-04-22).
- Windmill `wmill sync push` is destructive; check drift before pushing
- sops is stateful — `sops decrypt --in-place` → yq →
  `sops encrypt --in-place`
- `just play <name> <group>` expands to `play-<name>.yml`; no `-- --check`
  separator (runbook line 151 fixed).
- `.envrc` hierarchy: root loads CF/Tailscale tokens; cluster dir loads
  DO token from `do-universe/.env.enc`. Outside-cluster runs need
  `direnv exec <cluster-dir> <cmd>`.
- `just windmill-backup` now uses in-pod `pg_dumpall` + sentinel
  verification + `kubectl cp` (streaming pipe truncation bug fixed
  2026-04-22).
- PSS admission exempt: `windmill` + `tailscale` namespaces.
- Gateway API listener ports match Traefik entrypoint ports (80/443
  with hostNetwork).

## Success criteria (MVP done)

1. Staff push to Universe-org repo following `.woodpecker/deploy.yaml`
   template.
2. Woodpecker on gxy-launchbase builds + uploads to R2
   `universe-static-apps-01/<site>/deploys/<ts>-<sha>/`.
3. Pipeline writes `<site>/production` + `<site>/preview` atomically.
4. `<site>.freecode.camp` + `<site>.preview.freecode.camp` both route
   via CF → gxy-cassiopeia Caddy → `r2_alias` → R2 object served.
5. `universe rollback --to <deploy-id>` green ≤ 2 min (Q6).
6. `universe promote` repoints production from current preview atomically.
7. Cleanup cron deletes deploys > 7d except aliased prefixes.
8. gxy-static retired; DNS fully on gxy-cassiopeia.
9. `@freecodecamp/universe-cli@0.4.0-beta.1` published on npm.
10. Staff-facing "how to deploy a static site" playbook published.

## History of this sprint

- 2026-04-20 — Old sprint `docs/sprints/2026-04-20/` dispatched;
  bootstrap of gxy-launchbase + gxy-cassiopeia landed same day.
- 2026-04-21 — Audit; sprint scrapped; fresh plan built. HANDOFF
  seeded.
- 2026-04-22 — gxy-mgmt → gxy-management rename executed; Windmill
  restore dogfooded; QA locked; MASTER + dispatch block written;
  RFC amendments landed; T32 verified live; epic promoted to
  `running`; 18 infra commits pushed by operator.
