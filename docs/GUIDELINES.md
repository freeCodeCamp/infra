# Documentation Guidelines

How to write, update, and trim every doc in this repo and the sibling Universe
and Windmill repos. Consolidated so every contributor — human or agent —
reads one file to know where a thing goes.

## Principles

- **One doc type per concern.** A flight-manual rebuilds a cluster. An ADR
  records a decision. A runbook executes an operation. A field-note records
  a learning. Don't mix.
- **Append-only learnings, replaceable procedures.** Field-notes grow
  forever; flight-manuals and runbooks are overwritten to match reality.
- **Living ADRs.** Amend in place; git history tracks change. No "ADR-014a"
  or "ADR-014-revised". Edit the original; add a dated amendment section.
- **Lookup first, narrative second.** Tables beat paragraphs for
  operational content. Reserve prose for context ADRs need to explain.
- **Monthly trim is a discipline, not a request.** Stale docs are bugs.

## Doc-type matrix

| Doc type          | Location (canonical)                      | Purpose                                    | Owner                                                          |
| ----------------- | ----------------------------------------- | ------------------------------------------ | -------------------------------------------------------------- |
| ADR               | `Universe/decisions/NNN-*.md`             | Architectural decision + rationale         | Universe team (amend-in-place; infra/windmill can propose)     |
| Flight-manual     | `infra/docs/flight-manuals/gxy-<name>.md` | Rebuild one cluster from zero              | Infra team                                                     |
| Runbook           | `infra/docs/runbooks/<verb>-<noun>.md`    | Execute a specific operation               | Infra team                                                     |
| Field-note        | `Universe/spike/field-notes/<area>.md`    | Append-only operational learnings          | Per area (infra / windmill / universe-cli)                     |
| RFC               | `infra/docs/architecture/rfc-<topic>.md`  | Deep design for non-trivial infra work     | Infra team                                                     |
| Sprint dispatch   | `infra/docs/sprints/<date>/*.md`          | Per-sprint plan + per-task dispatch blocks | Sprint lead; archive to `sprints/archive/` after sprint closes |
| Guidelines (this) | `infra/docs/GUIDELINES.md`                | Doc conventions                            | Infra team                                                     |
| TODO park         | `infra/docs/TODO-park.md`                 | Deferred items with activation triggers    | Infra team                                                     |
| CLAUDE.md (repo)  | `<repo>/CLAUDE.md`                        | Agent-facing project instructions          | Per-repo team                                                  |

Cross-repo references use absolute paths with the `~/DEV/...` prefix so
agents resolve them regardless of cwd. Validate with `just docs-verify`
(to be added post-MVP).

## Field-note format (append-only)

Every field-note file opens with a short header, a distilled _invariants_
block, then an append-only journal.

```markdown
# <Area> Field Notes

Format: append-only journal + distilled invariants. New entries at the
bottom of the Journal, dated. Invariants are curated during monthly trim;
do not edit ad-hoc.

Last invariants review: YYYY-MM-DD.

## Invariants

Stable facts that survived at least one monthly trim cycle. No dates.

- <terse invariant statement>
- ...

## Journal (append-only)

### YYYY-MM-DD — <short event title>

<body — what happened, what was learned, what changed>

### YYYY-MM-DD — <next entry>

...
```

Rules:

- Never edit a past journal entry. If reality invalidates it, add a new
  entry that links back and corrects.
- Journal entries ≥30 days old are candidates for distillation during
  monthly trim — either their lesson folds into Invariants, or the raw
  entry moves to `journal-archive/<year>-<month>.md` adjacent to the
  field-note file.
- Delete an entry only if it is proven transient AND the lesson is now
  invalid (rare).

## Flight-manual format (per cluster)

One file per galaxy under `infra/docs/flight-manuals/`. Every manual
reconstructs that cluster from zero using only the manual + referenced
runbooks + infra-secrets.

Structure:

```markdown
# Flight Manual — gxy-<galaxy>

Last rebuild-verified: YYYY-MM-DD.

## Pre-flight

- Required accounts + tokens
- Required tooling on operator host

## Phase N: <phase name>

### N.1 <step>

<commands or runbook refs>

**Verification:** <how to confirm>

...

## Backups

...

## Teardown

...

## Known gaps

- <anything this manual cannot yet rebuild>
```

Cross-ref runbooks instead of inlining long procedures:
`See [dns-cutover runbook](../runbooks/dns-cutover.md).`

The `flight-manuals/00-index.md` file orders galaxies by provisioning
dependency and points to each per-cluster manual.

## Runbook format

One verb + noun per file. Single-purpose. Executable.

```markdown
# Runbook — <verb> <noun>

Blast radius: <what this affects; what rollback costs>
Last verified: YYYY-MM-DD.

## Preconditions

- <checkable state>

## Steps

1. <command or ClickOps>
   **Verify:** <how to confirm>
2. ...

## Rollback

...

## Exit criteria

...
```

Runbook names: `<verb>-<noun>.md` (e.g. `dns-cutover.md`,
`r2-bucket-provision.md`, `cluster-rename-mgmt-to-management.md`).

## ADR lifecycle

States: `Proposed` → `Accepted` → (optional) `Superseded` or `Parked`.

- **Amend in place.** Git history is the audit log.
- **Status change is an amendment.** Update the header + append a dated
  note at the bottom of the ADR explaining the change and the trigger.
- **Supersede, don't rewrite.** When an ADR is replaced, mark it
  `Superseded by ADR-NNN` and keep the body intact for context.
- **Decisions inside ADRs (D-refs).** Specific decisions get a
  D-identifier (e.g. D22, D32). When resolved, add a dated resolution note
  at the bottom of the ADR body citing the D-ref.
- **Infra/windmill may amend ADRs with explicit operator grant** (logged
  in the field-note journal with the grant date).

## Sprint docs

One directory per sprint: `infra/docs/sprints/<YYYY-MM-DD>/`. Filesystem-driven —
beads/issue-tracker IDs optional, dispatch-doc Status headers + STATUS.md
are source of truth.

**Canonical layout:**

```
infra/docs/sprints/<YYYY-MM-DD>/
├── README.md         — read-order pointer
├── STATUS.md         — live cursor (Shipped / Open / Other state / Resume prompt)
├── PLAN.md           — stable plan: goal, phases, gates, sub-task matrix, Wave graph
├── DECISIONS.md      — locked Q-rows + D-row cross-refs to RFCs
├── HANDOFF.md        — append-only dated history log
├── <topic>-audit.md  — point-in-time snapshots (optional)
└── dispatches/T<N>-<slug>.md — per-task briefs with Status header
```

**Doc roles (read-order matters):**

| File         | Mutability                                 | Read-when                         |
| ------------ | ------------------------------------------ | --------------------------------- |
| README.md    | Stable                                     | First — orients the dir           |
| STATUS.md    | Rewritten every "roll the session"         | First on resume — gives next move |
| PLAN.md      | Stable; patched on scope/phase change      | Before dispatching next task      |
| DECISIONS.md | Append-only amendments; never rewrite rows | When a Q/D needs lookup           |
| HANDOFF.md   | Append-only journal; one entry per session | When archaeology needed           |
| dispatches/  | Status header flips per-task by worker     | Before working a specific task    |

**Per-task closure checklist** — when a sub-task closes, the closure
commit MUST update **all** derived docs the change affects:

- [ ] Dispatch-doc Status header → `done`.
- [ ] Sprint matrix row in `PLAN.md` → `[x] done`.
- [ ] HANDOFF.md → append entry under today's date with summary + commit SHA.
- [ ] Cluster's flight-manual if rebuild steps changed (per cluster touched).
- [ ] Field-note Journal entry in `Universe/spike/field-notes/<area>.md` if learning landed (separate commit OK if cross-repo).
- [ ] Runbook if the change introduced or modified an operational procedure.
- [ ] ADR amendment if architectural decision shifted.
- [ ] TODO-park entry if work was deferred.
- [ ] Last `STATUS.md` may stay — gets rewritten next "roll the session".

**Session-roll commands:**

- `roll the sprint` → rewrite `STATUS.md` from current git log + dispatch-doc state. Single commit.
- `give me the resume prompt` → print `STATUS.md` Resume-prompt block verbatim.
- `start the sprint` (fresh session) → read `README.md` → `STATUS.md` → report current state, no action.
- `verify <G-id|T-id>` → run the dispatch's read-only **Verify command** block; report green/red. Required green before any operator-run gate (G-dispatch) or "awaits operator live run" T-dispatch closes. Added 2026-04-26 after sprint-2026-04-21 mid-sprint audit found 3 false-completion claims that would have been caught by a verify gate.

**Operator-bootstrap dispatch (G-dispatch) requirements:**

Every G-dispatch (`G<phase>.<seq>-<slug>.md`) declares operator manual
work that mutates live state outside the repo (sops files, Windmill
Resources, CF dashboard, kubeconfig, etc.). Schema:

- Status header: `pending` → `in-progress` → `done` like T-dispatches.
- Section `Operator steps` — numbered, copy-paste-runnable.
- Section `Acceptance criteria` — observable post-conditions.
- Section `Verify command` — single read-only command block any party
  can re-run to confirm green. Output is logged to dispatch closure block.
- Section `Closure` — Status, closing commit(s), Verify output (last
  green), sprint-doc patches owed.

Skipping the Verify section is a sprint bug — closing without a
re-runnable green command lets state lies through.

When a sprint closes, move its directory under
`infra/docs/sprints/archive/`. Archives are read-only.

## Monthly doc trim

First Monday of each month. Allot ~1 hour per area.

Per field-note file:

- [ ] Scan Journal for entries ≥30 days old.
- [ ] Distill each into an Invariant where possible; delete the entry if
      absorbed.
- [ ] Move still-useful raw entries to `journal-archive/<yyyy>-<mm>.md`.
- [ ] Update `Last invariants review` date at the top.

Per flight-manual:

- [ ] Re-verify one phase per month against live cluster. Rotate phases.
- [ ] Bump `Last rebuild-verified` on full rebuild runs.
- [ ] Delete deferred sections whose trigger has fired OR been permanently
      dropped.

Per runbook:

- [ ] Confirm `Preconditions` still match reality.
- [ ] Bump `Last verified` after next successful execution.

Per ADR:

- [ ] Reconcile with live state; open amendment or new ADR if drifted.

Log the trim pass itself as a journal entry in `infra.md` field-notes.

## When to update what (decision tree)

- Learned something about how a tool / cluster / service actually
  behaves? → **Field-note Journal entry.**
- Changed a rebuild step for one cluster? → **That cluster's
  flight-manual.** Don't touch other manuals even if the step was shared.
- Changed a single-purpose procedure? → **That runbook.**
- Changed an architectural decision? → **Amend the ADR in place** +
  add a dated resolution note.
- Starting a new sprint? → **Create `sprints/<date>/` with README +
  STATUS + PLAN + DECISIONS + HANDOFF + `dispatches/`.**
- Closing a sub-task? → **Run the per-task closure checklist** in
  §Sprint docs. Flight-manuals + field-notes update in the same
  closure work, not "later".
- Deferring an item? → **Append to `docs/TODO-park.md` with activation
  trigger.**
- Multiple places need the same fact? → **One canonical source; others
  cross-ref. Never duplicate.**

## Cross-repo ownership recap

- `infra` owns: flight-manuals, runbooks, RFCs, sprint docs, infra
  field-note entries (via Universe).
- `Universe` owns: ADRs, requirements/context/archi diagrams, all
  field-notes files (hosts them; per-area teams append).
- `windmill` owns: Windmill workspace code + its own `CLAUDE.md` +
  Windmill flight-manual if/when it gets one.
- `universe-cli` owns: CLI code + CLI field-note entries (via Universe).

When in doubt about ownership, default to whichever repo an operator
would grep to find the information.
