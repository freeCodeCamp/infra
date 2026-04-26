# Sprint 2026-04-21 — deep state audit + recovery plan (2026-04-25)

**Status:** working doc, locked-in 2026-04-26 — recovery decisions
applied to sprint docs in single sweep. Sections 1–3 + 7 are
historical (audit findings as captured). Section 4 was revised by the
**Decisions applied** block at top of this doc — read that first.
Section 5 (open questions) is fully resolved.

## Decisions applied 2026-04-26 (read first)

Operator picked:

1. **Strategy:** Full recovery (Phase 1–5).
2. **CF naming canon:** Keep `CLOUDFLARE_API_TOKEN`; add `CF_ZONE_ID`
   to global only if needed (smoke does not need it under option 2).
3. **rclone bootstrap:** N/A — eliminated. Smoke refactored to
   `aws-cli` + admin S3 keys via on-demand sops decrypt of
   `windmill/.env.enc` (option 2). See **D41**.
4. **Worktree:** Stay on `feat/k3s-universe`.
5. **STATUS G1.0:** Full rewrite (live-cursor doc) showing PARTIAL.

Architecture clarification (operator-supplied):

- **Single R2 bucket** `universe-static-apps-01`. Per-site separation
  is **prefix scoping** (`<site>/...`), NOT per-bucket. All
  Section 4 / Section 5 language and downstream dispatches reflect
  this. No per-site bucket anywhere in spec / runbook / dispatches.

Consequences (recovery scope shrinks):

- T12 `ops-rw.env.enc` design **superseded by D42**. No per-cluster
  R2 ops cred file.
- B1 (cassiopeia .env.enc seed), B4 (rclone r2: remote) — **dropped**.
- G1.1 dispatch shrinks to two mechanical actions (`R2_BUCKET` export
  - kubeconfig pull).
- Smoke script env contract changes:
  - drops `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_ENDPOINT`,
    `CF_API_TOKEN`, `CF_ZONE_ID` from required input
  - requires `R2_BUCKET` + `GXY_CASSIOPEIA_NODE_IP` from operator
  - sops-decrypts `CF_ACCOUNT_ID` + `R2_OPS_ACCESS_KEY_ID` +
    `R2_OPS_SECRET_ACCESS_KEY` from `windmill/.env.enc` on demand
  - drops `rclone` surface; uses `aws s3` with explicit
    `--endpoint-url` and admin keys via env

DECISIONS.md amendments landed in this sweep: **D41** (smoke + cleanup
ops surface), **D42** (T12 ops-rw superseded). Spec amendment block
appended in `task-gxy-cassiopeia.md` Task 12.

New dispatches under `dispatches/`:

- `G1.0a-windmill-cf-resource.md`
- `G1.0b-windmill-woodpecker-resource.md`
- `G1.1-cassiopeia-env.md`
- `G1.1-smoke-live-run.md`

Sprint protocol amended: `verify <gate>` verb added to GUIDELINES +
infra/CLAUDE.md sprint table. Every G-dispatch carries a Verify
command block.

---

## Original audit (preserved below for archaeology)

**Working-doc framing kept for transparency.** Captures divergence
between sprint-doc claims and live-system reality, then proposes a
phased recovery. Section 4 originally included rclone + per-cluster
ops-rw machinery — superseded by the **Decisions applied** block above.

**Trigger:** T15 phase4-smoke pre-flight surfaced 5 unmet operator-env
prereqs. Cross-checked windmill / CF / Woodpecker / secrets layers and
found additional false-completion claims. Concluded: **every active
critical path is blocked**, several blockers were already documented
as done.

---

## Section 1 — Reality vs sprint-doc claims

### 1.1 G1.0 operator bootstrap — partial completion mis-marked done

| Sprint-doc claim                                                                     | Reality                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| STATUS L46 + HANDOFF L97: "CF Account-owned API Token minted"                        | ✅ True. Token present in `infra-secrets/windmill/.env.enc`. Verified live: token has R2 admin perms (lists 10 buckets including `universe-static-apps-01` created 2026-04-20).                                       |
| STATUS L46: "seeded with `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID`"                  | ❌ **PARTIAL.** Sops decrypt of `windmill/.env.enc` shows ONLY `CF_R2_ADMIN_API_TOKEN`. **`CF_ACCOUNT_ID` is missing.** Account ID retrieved live via API: `ad45585c4383c97ec7023d61b8aef8c8` (freeCodeCamp account). |
| STATUS L46 + HANDOFF L97: "Windmill Resource `u/admin/cf_r2_provisioner` registered" | ❌ **FALSE.** `wmill resource list` on platform workspace returns ONLY `f/github/apollo_11_app`. The `u/admin/cf_r2_provisioner` resource does NOT exist. T11 cannot dereference it.                                  |
| STATUS L46: "smoke-curl green"                                                       | ⚠ Misleading. CF API smoke verified token + bucket. The Windmill Resource leg of G1.0 was never executed.                                                                                                             |

**Verdict:** G1.0 should not be marked done. It is roughly 50% complete.

### 1.2 T11 dispatch upstream — Woodpecker side never started

T11 dispatch §6 references operator-prereq Resource `u/admin/woodpecker_admin`
with shape `{baseUrl, token}`. State:

- Woodpecker admin personal-access-token: **not minted** (operator UI step never run)
- Windmill Resource `u/admin/woodpecker_admin`: **not registered** (depends on token)
- Resource type `c_woodpecker_admin`: **not registered** (would be created by `wmill resource push`)

T11 cannot register repo-scoped Woodpecker secrets without this. Wave A.3 has TWO operator-bootstrap dependencies, only ONE of which (the CF half) was started — and that one is also incomplete (§1.1).

### 1.3 Cassiopeia operator-bootstrap — never tracked, never executed

T12 spec (`task-gxy-cassiopeia.md` L1751–1860) defines the artifact half
(runbook + verify script + justfile recipe). All three artifacts shipped
pre-sprint. Spec explicitly states "Do NOT actually provision a bucket
in this task — runbook only" (L1818). The **operator-side ClickOps half**
was never tracked as a sprint task. Concretely missing:

- `infra-secrets/k3s/gxy-cassiopeia/.env.enc` — file does not exist
  (only `caddy.values.yaml.enc` present)
- `k3s/gxy-cassiopeia/.envrc` — does not export `R2_BUCKET`, does not
  load any cassiopeia-scoped sops file
- rclone `r2:` remote in `~/.config/rclone/rclone.conf` — not configured
- kubectl context for gxy-cassiopeia — not in operator's kubeconfig

**Note:** the bucket itself DOES exist on R2 (verified live, created
2026-04-20). Only the operator-side credential / config wiring is
missing.

### 1.4 Spec ↔ runbook ↔ reality drift

Four authoritative places disagree on where R2 cluster creds live:

| Source                            | Claimed path                                                       |
| --------------------------------- | ------------------------------------------------------------------ |
| Task 12 spec L1842                | `~/DEV/fCC/infra-secrets/gxy-cassiopeia/caddy-r2.env.enc`          |
| Task 12 spec L1847                | `~/DEV/fCC/infra-secrets/gxy-cassiopeia/ops-rw.env.enc`            |
| T15 runbook §Required environment | `infra-secrets/k3s/gxy-cassiopeia/.env.enc`                        |
| Real `k3s/gxy-cassiopeia/.envrc`  | `infra-secrets/do-universe/.env.enc` (only file currently sourced) |

Naming drift on CF zone token:

| Source                             | Variable name                                      |
| ---------------------------------- | -------------------------------------------------- |
| T15 runbook                        | `CF_API_TOKEN`, `CF_ZONE_ID`                       |
| `infra-secrets/global/.env.sample` | `CLOUDFLARE_API_TOKEN` (only); no zone ID anywhere |
| RFC                                | not pinned                                         |

Woodpecker API base drift:

| Source                         | Claimed base                                                                                                                        |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| T11 dispatch (default reading) | `/api/v1/...` style endpoints                                                                                                       |
| Live probe                     | `/api/user` returns 401 (real API). `/api/v1/*` returns 200 HTML (SPA fallback). **Real API base = `/api` with no version prefix.** |

### 1.5 Tooling primitives never scoped

- rclone `r2:` remote — every R2 op in T15 smoke script + future
  cleanup tooling assumes this remote exists. No spec, dispatch, RFC,
  or runbook provisions it. Pure unscoped operator-environment assumption.
- Woodpecker repo-scope ownership — spec confirms `freeCodeCamp-Universe`
  org (L84, 1485, 1577). Dispatch §E2 reads cleanly here, no drift.
- `f/static/` folder.meta.yaml — needs `owners: [u/mrugesh]` shape per
  existing `f/github/folder.meta.yaml` (verified live in
  `~/DEV/fCC-U/windmill/workspaces/platform/f/github/folder.meta.yaml`).
  Not blocking — T11 worker creates it as part of normal work.

---

## Section 2 — Cascade impact

```
G1.0 (false-done; CF half partial, Woodpecker half not started)
   ↓ blocks
Wave A.3 T11 windmill flow
   ↓ blocks (per stagger discipline)
Wave B parallel fanout (T21 + T22)
   ↓ blocks
RFC §6.6 sprint close + #25 release publish

Independently:
T12 operator-half (never dispatched, never tracked)
   ↓ blocks
Wave A.1 T15 phase4-smoke live run
   ↓ blocks
RFC §6.6 Phase 4 exit gate
   ↓ blocks
#25 release publish (per PLAN.md success-criterion 4)
```

**Every active critical path is blocked at an operator-bootstrap step
that is either false-claimed-done or never tracked.**

---

## Section 3 — Live-system facts (source of truth from this audit)

These are the empirical anchors for any reconciliation work.

| Fact                                                    | Value                                                                                    | Probe                                             |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------- |
| CF Account ID                                           | `ad45585c4383c97ec7023d61b8aef8c8` (name `freeCodeCamp`)                                 | `GET /accounts` with admin token                  |
| R2 bucket `universe-static-apps-01`                     | exists, created 2026-04-20                                                               | `GET /accounts/{acct}/r2/buckets`                 |
| CF R2 admin token                                       | functional (R2 ops authorized; self-verify endpoint denied — expected for scoped tokens) | live R2 list                                      |
| `infra-secrets/windmill/.env.enc` keys                  | `CF_R2_ADMIN_API_TOKEN` only                                                             | sops decrypt + grep                               |
| Windmill platform workspace resources                   | `f/github/apollo_11_app` only                                                            | `wmill resource list`                             |
| Woodpecker host                                         | `https://woodpecker.freecodecamp.net`, version 3.13.0                                    | header probe                                      |
| Woodpecker API base                                     | `/api` (NOT `/api/v1`)                                                                   | `/api/user` → 401, `/api/v1/user` → 200-HTML      |
| Cassiopeia droplets                                     | 3/3 active: `165.227.149.249`, `46.101.179.141`, `188.166.165.62`                        | `doctl compute droplet list`                      |
| Cassiopeia Caddy                                        | alive on every node, 404 pre-smoke (no alias yet)                                        | `curl -H "Host: test.freecode.camp" http://<ip>/` |
| `test.freecode.camp` + `test.preview.freecode.camp` DNS | resolves via CF anycast                                                                  | `dig +short`                                      |
| Existing folder owner pattern                           | `owners: [u/mrugesh]` per `f/github/folder.meta.yaml`                                    | live read                                         |

---

## Section 4 — Recovery plan (5 phases)

Discipline: phases are sequential at the **commit** level, parallel at
the **execution** level where noted. Every phase ends with a single
sprint-doc commit.

### Phase 1 — Truth-up (sprint-doc only, no operator action) — IMMEDIATE

Goal: stop the sprint-doc from lying. No live-system mutation.

1. Revert STATUS L46 G1.0 from `✅ DONE` to `⚠ PARTIAL — see audit report`. Add link to this audit report.
2. Append HANDOFF correction entry per protocol ("never edit past
   entries — append correction entry referencing the original"). Cite
   §1.1, §1.2, §1.3 of this audit. Reference original entry by date
   - summary line.
3. Save preflight report (already on disk, uncommitted) +
   this audit report under `docs/sprints/2026-04-21/reports/`.
4. Single commit: `docs(sprint/2026-04-21): truth-up G1.0 + add audit reports`.

### Phase 2 — Spec / runbook / layout reconciliation — SPRINT DOCS

Goal: pick one canonical layout for every drifted axis. Amend sources
to match. No live-system mutation yet.

Canonical proposals (operator approves or vetoes):

| Axis                       | Proposed canonical                                                                                                                                   |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cassiopeia R2 rw cred path | `infra-secrets/k3s/gxy-cassiopeia/.env.enc` (matches T15 runbook + flight-manual convention; T12 spec amended to align)                              |
| Vars in that file          | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_ENDPOINT` (Caddy + smoke read these via direnv → cassiopeia .envrc → sops)                         |
| `R2_BUCKET`                | added to cassiopeia .envrc as plain export (not secret)                                                                                              |
| CF API token name + path   | `CLOUDFLARE_API_TOKEN` (existing in `global/.env.enc`) — patch T15 runbook + smoke script to use this name. Add `CF_ZONE_ID` to global as new entry. |
| Woodpecker API base        | `https://woodpecker.freecodecamp.net/api` — patch T11 dispatch + universe-cli config defaults if needed                                              |
| rclone `r2:` remote        | new `rclone-bootstrap` justfile recipe writes minimal user-scope `~/.config/rclone/rclone.conf` from env-derived values (NOT checked-in config)      |

Files patched:

- `docs/architecture/task-gxy-cassiopeia.md` — Task 12 path correction
- `docs/runbooks/phase4-test-site-smoke.md` — env table + var names
- `scripts/phase4-test-site-smoke.sh` — `CF_API_TOKEN` → `CLOUDFLARE_API_TOKEN` (or alias)
- `scripts/tests/phase4-test-site-smoke.sh` — env-guard contract update
- `docs/sprints/2026-04-21/DECISIONS.md` — new D-amendment recording the canon picks
- `justfile` — new `rclone-bootstrap` recipe under `[group('smoke')]`

Single commit: `docs(sprint/2026-04-21): reconcile R2 / CF / Woodpecker layout drift (D-amend)`.

### Phase 3 — New operator-bootstrap dispatches — SPRINT DOCS

Goal: every operator-bootstrap step gets a tracked dispatch with
acceptance criteria + post-run verify command.

New dispatches:

- **G1.0a — Windmill Resource finalize**
  - add `CF_ACCOUNT_ID=ad45585c4383c97ec7023d61b8aef8c8` to `infra-secrets/windmill/.env.enc`
  - `wmill resource push u/admin/cf_r2_provisioner --workspace platform --resource-type c_cf_r2_provisioner --value '{"cfApiToken":"…","cfAccountId":"…"}'`
  - field-name resolution: align with T11 dispatch §6 (`cfApiToken` + `cfAccountId`) — agent's A1 question answered by this dispatch's spec
  - verify: `wmill resource get u/admin/cf_r2_provisioner --workspace platform` returns both keys
- **G1.0b — Woodpecker admin Resource**
  - mint Woodpecker personal access token (UI ClickOps)
  - register Resource type `c_woodpecker_admin` schema `{baseUrl: string, token: string}`
  - push `u/admin/woodpecker_admin` with `{baseUrl: "https://woodpecker.freecodecamp.net/api", token: "<paste>"}`
  - verify: `wmill resource get u/admin/woodpecker_admin --workspace platform` returns both keys
- **G1.1 — gxy-cassiopeia operator bootstrap**
  - mint cassiopeia-scoped R2 rw token (CF dashboard or via admin token API call) — path-condition `universe-static-apps-01/*`
  - sops-encrypt `infra-secrets/k3s/gxy-cassiopeia/.env.enc` with `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_ENDPOINT`
  - patch `k3s/gxy-cassiopeia/.envrc` to `use_sops` that file + `export R2_BUCKET=universe-static-apps-01`
  - run `just rclone-bootstrap` (recipe added in Phase 2)
  - pull cassiopeia kubeconfig into `~/.kube/config`
  - verify: re-run T15 preflight commands (this audit §3 probes) — all GREEN before any smoke fire
- **G1.1.smoke — T15 live run**
  - operator adds 2 temp DNS records (already in place per audit, but verify)
  - `just phase4-smoke`
  - removes temp DNS post-green
  - verify: exit 0, `OK: phase 4 smoke passed — phase4-<ts>`
  - this is the deferred half of T15 closure; collect explicitly

Single commit: `docs(sprint/2026-04-21): add G1.0a/G1.0b/G1.1/G1.1.smoke operator-bootstrap dispatches`.

### Phase 4 — Sprint protocol amendment — DOCS

Goal: prevent recurrence. Patch `docs/GUIDELINES.md` Sprint protocol
vocab to add `verify <gate>` verb.

- New verb: `verify <G-id>` — runs the dispatch's post-run verify
  command (read-only). Reports green/red. Required before any "operator
  runs X" deferral closes.
- Per-task closure checklist amended: every G-task must declare a
  `verify` command in its dispatch. Dispatch closure block must include
  the verify command's last green output.
- `infra/CLAUDE.md` Sprint protocol table extended with `verify <T-id>`
  row.

Single commit: `docs(GUIDELINES): add sprint protocol verify verb`.

### Phase 5 — Resume — EXECUTION

Once Phase 1–4 commits land:

1. Operator runs G1.0a → `verify G1.0a` green
2. Operator runs G1.0b → `verify G1.0b` green
3. **Wave A.3 T11 unblocks** — w-windmill agent in `~/DEV/fCC-U/windmill` starts implementation
4. Operator runs G1.1 → `verify G1.1` green (parallel with T11 implementation; different surface)
5. Operator runs G1.1.smoke → green → RFC §6.6 Phase 4 exit ✓ → **Wave A.1 closes for real**
6. T11 observe-✓ → **Wave B fans out** (T21 infra + T22 windmill)
7. Wave B closes → #25 release publish unblocks

Stagger discipline (PLAN.md L165) preserved; just adds the operator-bootstrap phase that was missing.

---

## Section 5 — Open questions for operator decision

1. **Canonical paths in §4 Phase 2** — accept proposals or override?
2. **CF token naming** — rename `CLOUDFLARE_API_TOKEN` → `CF_API_TOKEN` in global, OR keep `CLOUDFLARE_API_TOKEN` and adjust T15 runbook + smoke script? (Cost trade-off: rename = touches every consumer of global env; alias = local change to 2 files.)
3. **rclone bootstrap surface** — justfile recipe writing to `~/.config/rclone/rclone.conf`, OR inline `--s3-*` flags on every `rclone` invocation in scripts (no config file)? Latter is more vendor-neutral per memory note.
4. **Worktree strategy for recovery commits** — single feat-branch `feat/k3s-universe` (current) OR carve `fix/sprint-2026-04-21-recovery` for the truth-up + reconciliation? Sprint doc convention is single feature branch; recovery is meta-work but still belongs there.
5. **G1.0 mark-down handling** — append HANDOFF correction (per protocol, never edit past) is non-negotiable. Question is whether STATUS L46 gets a strikethrough OR full rewrite. Strikethrough preserves audit trail in the live-cursor doc itself.

---

## Section 6 — What this audit did NOT change

No live-system mutations. No commits. No sprint-doc edits. No
infra-secrets writes. No CF API writes. No Windmill resource pushes.
No git operations beyond status.

The pre-flight report `T15-smoke-preflight-2026-04-25.md` and this
audit are both uncommitted working docs. Operator decides Phase 1
commit timing.

---

## Section 7 — Probe transcript appendix

All commands run during this audit (read-only, no mutations):

```bash
# repo-state
git log --oneline origin/feat/k3s-universe..HEAD | wc -l
git status --short

# spec / dispatch grep
grep -nE "Task 12|R2 bucket|preflight|prerequisite|G1\." docs/sprints/2026-04-21/{PLAN,DECISIONS,HANDOFF}.md
grep -nE "freeCodeCamp-Universe|owner.*repo" docs/architecture/task-gxy-cassiopeia.md

# cluster
doctl compute droplet list --tag-name gxy-cassiopeia-k3s --format Name,PublicIPv4,Status
kubectl config get-contexts

# DNS / edge
dig +short test.freecode.camp
dig +short test.preview.freecode.camp
curl -sS -o /dev/null -w "<fmt>" https://test.freecode.camp/
curl -sS -o /dev/null -w "<fmt>" https://test.preview.freecode.camp/
curl -sS -H "Host: test.freecode.camp" "http://<each-node-ip>/"

# Woodpecker API base discovery
curl -sS -o /dev/null -w "<fmt>" https://woodpecker.freecodecamp.net/api/{user,v1/user,info,version,healthz}

# secrets / env
test -f infra-secrets/k3s/gxy-cassiopeia/.env.enc
ls infra-secrets/{global,windmill,k3s/gxy-cassiopeia,do-universe}
cat infra-secrets/{global,do-universe}/.env.sample
sops -d --input-type dotenv infra-secrets/windmill/.env.enc | grep ^CF_

# direnv / rclone
direnv exec k3s/gxy-cassiopeia sh -c '<env-presence checks>'
direnv exec k3s/gxy-cassiopeia rclone lsf "r2:universe-static-apps-01/" --max-depth 1
rclone config show

# Windmill platform
cd ~/DEV/fCC-U/windmill && bunx wmill workspace list
bunx wmill resource list
ls workspaces/platform/f/github/folder.meta.yaml

# CF API (live, read-only — token redacted on disk)
fetch /user/tokens/verify
fetch /accounts
fetch /accounts/{acct}/r2/buckets

# T15 contract
just phase4-smoke-test
shellcheck scripts/phase4-test-site-smoke.sh
bash -n scripts/phase4-test-site-smoke.sh
just --unstable --fmt --check
```

Token material was held in a temporary file (`/tmp/cftok.txt`) for one
ctx_execute call and unlinked immediately after. No token written to
any persistent file.
