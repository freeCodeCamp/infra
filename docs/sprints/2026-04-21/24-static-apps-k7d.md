# #24 — MVP static-apps E2E chain (dispatch block)

**Goal:** Staff push → site live on `<site>.freecode.camp` via Woodpecker
build → R2 upload → atomic alias flip → Caddy(`r2_alias`) serve on
gxy-cassiopeia. Preview siblings live at `<site>.preview.freecode.camp`.

**Gate:** Sprint MASTER Phase 1 (G1). Passes when the full chain executes
end-to-end against one reference repo + `universe rollback --to` +
`universe promote` both green within SLO.

**Source of truth:** `docs/architecture/task-gxy-cassiopeia.md` —
per-task breakdown with acceptance criteria, files to modify, and
traceability to `rfc-gxy-cassiopeia.md` requirements.

**Tracking model (2026-04-25):** filesystem-driven. Each T-id has a
dispatch doc at `dispatches/T<N>-<slug>.md` with status header
(`pending → in-progress → done`) and closure block. Beads + bead IDs
deprecated for this sprint; ignored on read, not updated on write.

---

## QA decision deltas (vs. pre-decision task breakdown)

Apply before dispatching sub-tasks:

| Decision                    | Impact on task breakdown                                                                                                                                                                                                           |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1 (Woodpecker alias write) | `T21` remains source of truth. Alias write is the **last** pipeline step.                                                                                                                                                          |
| Q2 (CF R2 admin cred path)  | `T11` bootstrap uses `infra-secrets/windmill/.env.enc` (D33 amended ×2 2026-04-25 — was `platform/`, then `global/`, now `windmill/`). Vars: `CF_R2_ADMIN_API_TOKEN` + `CF_ACCOUNT_ID` only (Bearer-only, S3 admin keys dropped).  |
| Q3 (per-site sops path)     | **NONE.** Per-site secrets persist in Woodpecker repo-scoped secrets only (D40 supersedes D34, 2026-04-25). No `constellations/` dir, no `.sops.yaml` rule change. Recovery path = re-mint via CF API. Offline backup → TODO-park. |
| Q4 (no CF-IP allow-list)    | `T14` **descoped**. Delete or hard-gate task. Galaxy FW stays 80/443 `0.0.0.0/0`.                                                                                                                                                  |
| Q5 (two-level DNS)          | Onboarding writes `<site>` + `<site>.preview` A records in one call.                                                                                                                                                               |
| Q6 (≤ 2 min rollback SLO)   | Smoke harness polls 30s × 2 green. LRU stays 60s (Task 02 default).                                                                                                                                                                |
| Q7 (prod+preview MVP)       | Every deploy writes **two** alias files. Pipeline template (T21) + cleanup (T22) must honor both.                                                                                                                                  |
| Q8 (7d cleanup)             | `T22` cron keeps hard 7d. Pins both alias targets as "in use".                                                                                                                                                                     |

Open inline one-liner addenda to `rfc-gxy-cassiopeia.md` §Decisions for
each delta above (tracked in Universe ADR-007 amendment D22/D32 thread).

---

## Sub-task matrix (MVP in-scope only)

Filesystem-driven. Each row's status reflects the Status header in the
linked dispatch doc. Worker flips `pending → in-progress → done` in
the dispatch doc, then updates this row in the same closure commit.

| T-id | Area         | Subject                                       | Dispatch                                                                           | Status                  |
| ---- | ------------ | --------------------------------------------- | ---------------------------------------------------------------------------------- | ----------------------- |
| T11  | windmill     | Per-site R2 secret provisioning flow          | [`dispatches/T11-windmill-flow.md`](dispatches/T11-windmill-flow.md)               | [ ] pending             |
| T15  | infra        | Phase 4 smoke runbook + script                | [`dispatches/T15-smoke-runbook.md`](dispatches/T15-smoke-runbook.md)               | [ ] pending             |
| T16  | universe-cli | Woodpecker API client                         | [`dispatches/T16-woodpecker-client.md`](dispatches/T16-woodpecker-client.md)       | [ ] pending             |
| T17  | universe-cli | Config schema + site name validation          | [`dispatches/T17-cli-config.md`](dispatches/T17-cli-config.md)                     | [ ] pending             |
| T18  | universe-cli | Rewrite `deploy` command                      | [`dispatches/T18-cli-deploy.md`](dispatches/T18-cli-deploy.md)                     | [ ] pending             |
| T19  | universe-cli | Rewrite `promote` + `rollback`                | [`dispatches/T19-cli-promote-rollback.md`](dispatches/T19-cli-promote-rollback.md) | [ ] pending             |
| T20  | universe-cli | Strip legacy rclone/S3 + release 0.4.0-beta.1 | [`dispatches/T20-cli-strip-cut.md`](dispatches/T20-cli-strip-cut.md)               | [ ] pending — gates #25 |
| T21  | infra        | `.woodpecker/deploy.yaml` template            | [`dispatches/T21-woodpecker-template.md`](dispatches/T21-woodpecker-template.md)   | [ ] pending             |
| T22  | windmill     | Cleanup cron flow                             | [`dispatches/T22-cleanup-cron.md`](dispatches/T22-cleanup-cron.md)                 | [ ] pending             |

**Out-of-scope / closed:**

- **T14** (CF IP refresh cron) — descoped 2026-04-22 per Q4. No dispatch.
- **T32** (Woodpecker DNS + CF Access + admin users) — verified live
  2026-04-22 (HANDOFF §"T32 verification"). No dispatch.

Caddy module tasks T01/T01b/T02/T03/T04/T05 already **shipped in the
2026-04-18 bootstrap** (verified live on gxy-cassiopeia caddy-s3 image).
No re-dispatch unless regression hit.

---

## Execution order

Each sub-task's own acceptance criteria gate the next. Wave A staggered;
Wave B parallel where deps allow.

1. **Operator bootstrap (manual ClickOps)**
   - CF Account-owned API Token minted; admin Bearer + Account ID
     seeded into `infra-secrets/windmill/.env.enc`; Windmill Resource
     `u/admin/cf_r2_provisioner` registered. See
     [`dispatches/T11-windmill-flow.md` §Operator bootstrap](dispatches/T11-windmill-flow.md).

2. **Wave A — staggered worker dispatch (one repo at a time)**
   - **A.1 (infra):** [T15](dispatches/T15-smoke-runbook.md) — Phase 4 smoke runbook + script.
   - **A.2 (universe-cli):** [T16](dispatches/T16-woodpecker-client.md) → [T17](dispatches/T17-cli-config.md) — woodpecker client + config schema.
   - **A.3 (windmill):** [T11](dispatches/T11-windmill-flow.md) — per-site R2 secret provisioning flow.

3. **Wave B — parallel fanout (post-Wave-A green)**
   - **infra:** [T21](dispatches/T21-woodpecker-template.md) — `.woodpecker/deploy.yaml` template (Q1 ordering + Q7 dual-alias + §4.4.3 audit metadata).
   - **universe-cli:** [T18](dispatches/T18-cli-deploy.md) → [T19](dispatches/T19-cli-promote-rollback.md) → [T20](dispatches/T20-cli-strip-cut.md).
   - **windmill:** [T22](dispatches/T22-cleanup-cron.md) — cleanup cron (Q7 prefix-pin + Q8 7d).

4. **Gate G1**
   - Reference-repo deploy end-to-end: push → build → upload → alias flip → DNS resolve → 200 served.
   - `universe rollback --to <prev-deploy-id>` → smoke green ≤ 2 min.
   - `universe promote` → preview becomes prod → smoke green ≤ 2 min.
   - Cleanup cron survives dry-run against fixture deploys.

5. **Unblock #25**
   - T20 closure triggers release dispatch for `25-universe-cli-release.md`.

---

## Secrets wiring (post-Phase 1 verification)

Paths on infra-secrets sibling repo (D33×2 + D40 amended 2026-04-25):

```
infra-secrets/
  windmill/
    .env.sample                          # documented schema (sample-twin)
    .env.enc                             # CF_R2_ADMIN_API_TOKEN + CF_ACCOUNT_ID (D33)
                                         #   Bearer-only, S3 admin keys dropped
                                         #   NOT direnv-loaded (app-consumed via sops -d)
  k3s/
    gxy-cassiopeia/
      caddy.values.yaml.enc              # R2 ro key bootstrap (pre-T11)
    gxy-launchbase/
      woodpecker.values.yaml.enc         # pipeline agent creds
```

**Per-site R2 secrets:** Woodpecker repo-scoped secrets only (D40).
No `infra-secrets/constellations/` dir, no new `.sops.yaml` rule.
Names: `r2_access_key_id` + `r2_secret_access_key`.

`.sops.yaml` already covers `windmill/.env.enc` via existing repo-wide
`path_regex: .*` rule. No change needed.

---

## Dispatch instructions

- **Per-sub-task dispatch:** open `dispatches/T<N>-<slug>.md` for the
  brief. Body cross-references `docs/architecture/task-gxy-cassiopeia.md`
  (acceptance criteria source of truth) + RFC §sections + QA deltas.
  This file only captures **scope deltas** caused by Q1–Q8 decisions
  - the matrix rollup.
- **Status flow:** worker flips dispatch-doc Status header
  `pending → in-progress` on start, `→ done` on closure. Same commit
  updates the matrix row in this file. Beads not used.
- **Commit policy:** TDD discipline per `.claude/rules/code-quality.md`
  (RED → GREEN → REFACTOR). Commit per sub-task close. Operator pushes
  at sprint close, not per task. Title-only commits per
  `.claude/skills/cmd-git-rules`.
- **Close-out trigger:** when all matrix rows show `[x] done` + G1 smoke
  green, this dispatch block closes; MASTER G1 ticks; #25 unblocks.

---

## Traceability

| Requirement → Source                                                         |
| ---------------------------------------------------------------------------- |
| Q1 Woodpecker step → `QA-recommendations.md` Q1 + RFC §4.5.x                 |
| Q2 admin cred scope → RFC §4.4.6 + ADR-011                                   |
| Q3 per-site sops path → RFC §5.secrets + `rfc-secrets-layout.md` §Two scopes |
| Q4 FW posture → `cluster-audit.md` §firewall + RFC §4.7                      |
| Q5 two-level DNS → ADR-009 + RFC §4.6 DNS                                    |
| Q6 SLO → RFC §6.6 Phase 4 exit                                               |
| Q7 preview parity → RFC §4.4.3 + §4.5 pipeline                               |
| Q8 7d cleanup → ADR-007 §retention + RFC §4.8 cleanup                        |

---

## Non-goals (this task)

- Zot push of build artifacts (TODO-park: supply chain).
- cosign / Kyverno verifyImages admission (TODO-park).
- ArgoCD on gxy-management (TODO-park; activate post-cutover).
- BYO domain onboarding (Phase 2 — ADR-009 flat DNS deferred).
- Tiered rollback SLO (Phase 2 — per-site override).
