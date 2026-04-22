# #24 — MVP static-apps E2E chain (dispatch block)

**Epic:** `gxy-static-k7d` (stage `speccing` → promote to `running` before
any mutation).

**Goal:** Staff push → site live on `<site>.freecode.camp` via Woodpecker
build → R2 upload → atomic alias flip → Caddy(`r2_alias`) serve on
gxy-cassiopeia. Preview siblings live at `<site>.preview.freecode.camp`.

**Gate:** Sprint MASTER Phase 1 (G1). Passes when the full chain executes
end-to-end against one reference repo + `universe rollback --to` +
`universe promote` both green within SLO.

**Source of truth:** `docs/architecture/task-gxy-cassiopeia.md` —
per-task breakdown with acceptance criteria, files to modify, and
traceability to `rfc-gxy-cassiopeia.md` requirements.

---

## QA decision deltas (vs. pre-decision task breakdown)

Apply before dispatching sub-tasks:

| Decision                    | Impact on task breakdown                                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Q1 (Woodpecker alias write) | `T21` remains source of truth. Alias write is the **last** pipeline step.                                                      |
| Q2 (CF R2 admin cred path)  | `T11`/`T32` bootstrap uses `infra-secrets/platform/cf-r2-provisioner.secrets.env.enc` (not `do-primary/.env.enc`).             |
| Q3 (per-site sops path)     | Per-site tokens land at `infra-secrets/constellations/<site>.secrets.env.enc`. Update `.sops.yaml` creation_rule + T11 writer. |
| Q4 (no CF-IP allow-list)    | `T14` **descoped**. Delete or hard-gate task. Galaxy FW stays 80/443 `0.0.0.0/0`.                                              |
| Q5 (two-level DNS)          | Onboarding writes `<site>` + `<site>.preview` A records in one call.                                                           |
| Q6 (≤ 2 min rollback SLO)   | Smoke harness polls 30s × 2 green. LRU stays 60s (Task 02 default).                                                            |
| Q7 (prod+preview MVP)       | Every deploy writes **two** alias files. Pipeline template (T21) + cleanup (T22) must honor both.                              |
| Q8 (7d cleanup)             | `T22` cron keeps hard 7d. Pins both alias targets as "in use".                                                                 |

Open inline one-liner addenda to `rfc-gxy-cassiopeia.md` §Decisions for
each delta above (tracked in Universe ADR-007 amendment D22/D32 thread).

---

## Sub-task matrix (MVP in-scope only)

Tagged by status per `bd list epic:gxy-static-k7d` snapshot.

| Bead  | T-id | Area         | Subject                                       | Status                                |
| ----- | ---- | ------------ | --------------------------------------------- | ------------------------------------- |
| `.17` | T16  | universe-cli | Woodpecker API client                         | open                                  |
| `.18` | T17  | universe-cli | Config schema + site name validation          | open                                  |
| `.19` | T18  | universe-cli | Rewrite `deploy` command                      | open                                  |
| `.20` | T19  | universe-cli | Rewrite `promote` + `rollback`                | open                                  |
| `.21` | T20  | universe-cli | Strip legacy rclone/S3 + release 0.4.0-beta.1 | open — gates #25                      |
| `.22` | T21  | infra        | `.woodpecker/deploy.yaml` template            | open                                  |
| `.23` | T22  | windmill     | Cleanup cron flow                             | open                                  |
| `.16` | T15  | infra        | Phase 4 smoke runbook + script                | open                                  |
| `.12` | T11  | windmill     | Per-site R2 secret provisioning flow          | open (Q2+Q3 rescope)                  |
| `.15` | T14  | infra        | CF IP refresh cron                            | **descoped (Q4)** — close with reason |
| `.33` | T32  | infra        | Woodpecker DNS + CF Access + admin users      | open                                  |

Caddy module tasks T01/T01b/T02/T03/T04/T05 already **shipped in the
2026-04-18 bootstrap** (verified live on gxy-cassiopeia caddy-s3 image).
No re-dispatch unless regression hit.

---

## Execution order

Linear chain; each sub-task's own acceptance criteria gate the next.

1. **Bootstrap (parallel-safe)**
   - Close `.15 T14` with reason "Q4 descoped 2026-04-22".
   - Rescope `.12 T11` sops paths (Q2 + Q3).
   - Land one-liner addenda on `rfc-gxy-cassiopeia.md` §Decisions.

2. **Platform wiring**
   - `.12 T11` — per-site secret provisioning Windmill flow at new sops path.
   - `.33 T32` — Woodpecker DNS + CF Access + admin users (already done per
     earlier sprint audit; verify green + close).

3. **Pipeline + CLI (can run in parallel, converge at smoke)**
   - infra lane: `.22 T21` — `.woodpecker/deploy.yaml` template with Q1
     step ordering + Q7 dual-alias write + §4.4.3 audit metadata.
   - universe-cli lane: `.17 T16` → `.18 T17` → `.19 T18` → `.20 T19`.

4. **Cleanup + smoke**
   - `.23 T22` — Windmill cleanup cron honoring Q7 prefix-pin + Q8 7d.
   - `.16 T15` — `scripts/phase4-test-site-smoke.sh` + runbook + `just
phase4-smoke` recipe. Poll cadence 30s; assert 2 consecutive 200s
     inside 120s window (Q6 SLO).

5. **Gate G1**
   - Run reference-repo deploy end-to-end: push → build → upload → alias
     flip → DNS resolve → 200 served.
   - Run `universe rollback --to <prev-deploy-id>` → smoke green ≤ 2 min.
   - Run `universe promote` → preview becomes prod → smoke green ≤ 2 min.
   - Confirm cleanup cron survives dry-run against fixture deploys.

6. **Unblock #25**
   - `.21 T20` closure triggers release dispatch for `25-universe-cli-release.md`.

---

## Secrets wiring (post-Phase 1 verification)

Paths on infra-secrets sibling repo:

```
infra-secrets/
  platform/
    cf-r2-provisioner.secrets.env.enc    # Q2 — admin scope, mints per-site tokens
  constellations/
    <site>.secrets.env.enc               # Q3 — per-site data-plane token (created by T11)
  k3s/
    gxy-cassiopeia/
      caddy.values.yaml.enc              # R2 ro key bootstrap (pre-T11)
    gxy-launchbase/
      woodpecker.values.yaml.enc         # pipeline agent creds
```

`.sops.yaml` creation_rule (land in infra-secrets alongside T11):

```yaml
- path_regex: ^constellations/.*\.secrets\.env\.enc$
  key_groups:
    - age:
        - <platform age key fingerprint>
```

---

## Dispatch instructions

- **bd stage:** promote epic `gxy-static-k7d` to `running` before starting
  Execution step 2. Source:
  `bash -c 'source ${CLAUDE_PLUGIN_ROOT}/lib/dp-beads.sh && dp_beads_stage gxy-static-k7d running'`.
- **Per-sub-task dispatch:** work from the Acceptance Criteria block in
  `docs/architecture/task-gxy-cassiopeia.md` (source of truth). This file
  only captures **scope deltas** caused by Q1–Q8 decisions.
- **Commit policy:** TDD discipline per
  `.claude/rules/code-quality.md` (RED → GREEN → REFACTOR). Commit per
  sub-task close. Operator pushes at sprint close, not per task.
- **Close-out trigger:** when all sub-tasks close + G1 green, this
  dispatch block closes; MASTER G1 ticks; #25 unblocks.

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
