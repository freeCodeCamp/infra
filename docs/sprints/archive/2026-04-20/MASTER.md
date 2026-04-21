# MASTER — Sprint 2026-04-20 Dispatch Checklist

Operator's single-page copy-paste sheet. Two parallel sessions max. Watch both.
Close one, then dispatch next phase.

## Rules

- Agent reads spec from absolute path. No `bd` calls from non-infra sessions.
- Agent verifies preconditions by `curl` / `dig` / `kubectl` / file checks.
- Agent updates: (1) field notes in Universe, (2) flight manual in own repo,
  (3) any local project docs the spec names.
- Agent prepares commits — never pushes. Operator pushes.
- Operator updates beads (`dp_beads_close <id>`) after verifying completion.
- Operator ticks this file after each close.

## Start each session with

```sh
claude --add-dir /Users/mrugesh/DEV/fCC/infra --add-dir /Users/mrugesh/DEV/fCC-U/Universe
```

Extra `--add-dir` entries per dispatch row. The first flag gives the session
read access to the infra spec file + RFC. The second gives write access to
`spike/field-notes/*.md`.

## Dispatch

Copy the **Dispatch** block under each session row into the claude prompt.

### Phase A — parallel ×2

| #   | Task                                              | Repo cwd                       |
| --- | ------------------------------------------------- | ------------------------------ |
| A1  | T32 Woodpecker DNS + CF Access                    | `/Users/mrugesh/DEV/fCC/infra` |
| A2  | T26 FLIGHT-MANUAL gxy-launchbase + gxy-cassiopeia | `/Users/mrugesh/DEV/fCC/infra` |

**A1 dispatch:**

```
@docs/sprints/2026-04-20/01-infra-T32.md

Execute this spec. Preconditions are shell-verifiable — skip any beads
status lookup. On completion, print the "Output expected" block and stop.
Do not push or close beads.
```

**A2 dispatch:**

```
@docs/sprints/2026-04-20/07-infra-T26.md

Execute this spec. On completion, print the "Output expected" block and stop.
Do not push.
```

### Phase B — parallel ×2 — gated on A1

Precondition check before dispatch:

```sh
curl -sI https://woodpecker.freecodecamp.net | head -3
# must show 302 Location: https://<team>.cloudflareaccess.com/...
```

| #   | Task                                     | Repo cwd                            | Extra --add-dir   |
| --- | ---------------------------------------- | ----------------------------------- | ----------------- |
| B1  | T11 Per-site R2 secret provisioning flow | `/Users/mrugesh/DEV/fCC-U/windmill` | (defaults enough) |
| B2  | T14 CF IP allow-list + refresh cron      | `/Users/mrugesh/DEV/fCC-U/windmill` | (defaults enough) |

**B1 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/02-windmill-T11.md

Execute this spec. All preconditions are shell checks — do not call bd.
Write code + tests in this windmill repo. Append a field-notes subsection
to /Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/windmill.md per the
"Docs to update" section. Prepare commits in both repos; do not push.
```

**B2 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/04-windmill-T14.md

Execute this spec. Note: this task spans infra + windmill repos. Start the
claude session with --add-dir for the infra repo so you can write the
CiliumNetworkPolicy manifest there. Do not push either repo.
```

### Phase C — parallel ×2 — gated on B1

Precondition check:

```sh
# verify per-site secret flow exists
ls /Users/mrugesh/DEV/fCC-U/windmill/workspaces/platform/f/static/provision_site_r2_credentials.ts
# and had a successful preview run against a test site (check Woodpecker UI)
```

| #   | Task                                            | Repo cwd                            |
| --- | ----------------------------------------------- | ----------------------------------- |
| C1  | T21 `.woodpecker/deploy.yaml` pipeline template | `/Users/mrugesh/DEV/fCC/infra`      |
| C2  | T22 Cleanup cron flow                           | `/Users/mrugesh/DEV/fCC-U/windmill` |

**C1 dispatch:**

```
@docs/sprints/2026-04-20/03-infra-T21.md

Execute this spec.
```

**C2 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/05-windmill-T22.md

Execute this spec. All preconditions are shell-verifiable.
```

### Phase D — parallel ×2 — gated on C1

Precondition check:

```sh
test -f /Users/mrugesh/DEV/fCC/infra/docs/templates/woodpecker-static-deploy.yaml && echo OK
```

| #   | Task                               | Repo cwd                            |
| --- | ---------------------------------- | ----------------------------------- |
| D1  | T15 Phase 4 smoke runbook + script | `/Users/mrugesh/DEV/fCC/infra`      |
| D2  | T27 Universe field notes Phase 0   | `/Users/mrugesh/DEV/fCC-U/Universe` |

**D1 dispatch:**

```
@docs/sprints/2026-04-20/06-infra-T15.md

Execute this spec. Run the smoke against live gxy-cassiopeia. Clean up
on success AND failure.
```

**D2 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/08-universe-T27.md

Execute this spec. This is an append-only field-notes update documenting
the shipped Caddy r2_alias module + image. Gather real measurements from
the infra repo; no placeholders.
```

### Phase E — parallel ×2 — gated on D1

Precondition check:

```sh
just -f /Users/mrugesh/DEV/fCC/infra/justfile phase4-smoke --dry-run 2>&1 | head -5
# and confirm the actual live run was green (operator checked D1 output)
```

| #   | Task                                                  | Repo cwd                                |
| --- | ----------------------------------------------------- | --------------------------------------- |
| E1  | universe-cli release — push + live E2E + 0.4.0-beta.1 | `/Users/mrugesh/DEV/fCC-U/universe-cli` |
| E2  | T28 Universe field notes Phase 1-2                    | `/Users/mrugesh/DEV/fCC-U/Universe`     |

**E1 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/09-universe-cli-release.md

Execute this spec. Verify preconditions by live shell checks (dig, curl,
kubectl) — do not call bd. Push to main after local validation; CI OIDC
publishes. Stop at the "Output expected" block for operator sign-off.
```

**E2 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/08-universe-T28.md

Execute this spec. Real measurements only; no placeholders.
```

### Phase F — solo — gated on E1 (release live)

| #   | Task                             | Repo cwd                            |
| --- | -------------------------------- | ----------------------------------- |
| F1  | T29 Universe field notes Phase 4 | `/Users/mrugesh/DEV/fCC-U/Universe` |

**F1 dispatch:**

```
@/Users/mrugesh/DEV/fCC/infra/docs/sprints/2026-04-20/08-universe-T29.md

Execute this spec. Gather Phase 4 measurements from the T15 smoke run.
Phase 6 is out of scope today — leave placeholder only.
```

## Completion tracking

Tick as you close each task. Write the commit SHA so we can cross-reference.

| Phase | Task                           | Beads ID          | Status | Commit SHA | Notes                                                                        |
| ----- | ------------------------------ | ----------------- | ------ | ---------- | ---------------------------------------------------------------------------- |
| A1    | T32 Woodpecker DNS + CF Access | gxy-static-k7d.33 | [x]    | 3875c02    | CF Access deferred; GitHub org-gate is auth. Field note 2344385 in Universe. |
| A2    | T26 FLIGHT-MANUAL              | gxy-static-k7d.27 | [ ]    |            |                                                                              |
| B1    | T11 R2 secret flow             | gxy-static-k7d.12 | [ ]    |            |                                                                              |
| B2    | T14 CF IP allow-list + cron    | gxy-static-k7d.15 | [ ]    |            |                                                                              |
| C1    | T21 pipeline template          | gxy-static-k7d.22 | [ ]    |            |                                                                              |
| C2    | T22 cleanup cron               | gxy-static-k7d.23 | [ ]    |            |                                                                              |
| D1    | T15 Phase 4 smoke              | gxy-static-k7d.16 | [ ]    |            |                                                                              |
| D2    | T27 field notes Phase 0        | gxy-static-k7d.28 | [ ]    |            |                                                                              |
| E1    | universe-cli 0.4.0-beta.1      | gxy-static-k7d.21 | [ ]    |            |                                                                              |
| E2    | T28 field notes Phase 1-2      | gxy-static-k7d.29 | [ ]    |            |                                                                              |
| F1    | T29 field notes Phase 4        | gxy-static-k7d.30 | [ ]    |            |                                                                              |

## After a session finishes

Per session output, operator runs (in infra cwd):

```sh
# 1. push target repo if changes look right
#    (each agent prepares commits; you review, then push)

# 2. close beads
source /Users/mrugesh/.claude/plugins/cache/dp-cto/*/lib/dp-beads.sh 2>/dev/null || true
dp_beads_close gxy-static-k7d.<N>

# 3. tick MASTER.md table above; commit the tick
```

## Emergency stop

If any phase precondition fails, STOP, fix in a focused session, then
resume. Do not cascade dispatches past a failed gate.

## Non-goals for today

- DNS cutover `*.freecode.camp` gxy-static → gxy-cassiopeia (Phase 6, separate day).
- Hetzner migration (T30, deferred post-M5).
- universe-cli GA. 0.4.0-beta.1 only.
