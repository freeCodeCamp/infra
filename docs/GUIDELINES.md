# Documentation Guidelines

Conventions for docs maintained by this repo.

## Field-note format

Field notes live upstream in `~/DEV/fCC-U/Universe/spike/field-notes/<team>.md`,
one file per team. This repo's team owns `infra.md`.

- **Append-only.** New entries at the bottom, dated `### YYYY-MM-DD — <title>`.
- **Invariants vs journal.** Top of file holds stable invariants (current
  cluster facts, validated assumptions, hard constraints). Below it, the
  journal — chronological dated entries.
- **Monthly trim** (first Monday): distill stable lessons from the journal
  into the invariants section. Mark superseded journal entries with
  `~~strikethrough~~` rather than deleting; preserve the trail.
- **Cross-references**: link to ADRs when correcting an assumption; link to
  the spike plan when a phase is unblocked. Do not duplicate ADR content.
- **No tradecraft**: do not commit internal sprint mechanics, agent dispatch
  machinery, or per-session scratch. Those live in `.scratchpad/`.

## Runbook format

- One operational concern per file. Numeric prefix orders by reader path.
- Imperative verbs. Cite exact commands, exact filenames, exact env vars.
- Cross-link to other runbooks rather than duplicating steps.
- Failure modes get their own section: symptom → cause → fix.

## Flight-manual format

- One file per galaxy. Doomsday rebuild — "if everything were deleted, how
  to build it up again."
- Phases ordered: pre-flight → provision → bootstrap → ship apps → verify.
- No design rationale. Design lives in Universe ADRs.
- Lifecycle pins (k3s, Caddy, etc.) live in `flight-manuals/00-index.md`,
  not duplicated per galaxy.

## RFC format (architecture/)

- One RFC per non-trivial work item. Title: `rfc-<topic>.md`.
- Status block at the top: Draft / Accepted / Superseded.
- Superseded RFCs get a single-line pointer to the successor and stay only
  as long as that pointer earns its keep. Otherwise, delete.

## Sprint-close discipline

Sprint STATUS docs MUST run a verifier pass before close. Absolute claims
about cross-repo state (`X commits ahead`, `Y entries in TODO-park`,
`Phase-N gates on Z`) get out of sync silently. The 2026-05-02 reality
audit found 4 such silent failures in `archive/2026-04-26/STATUS.md`:
"4 ahead" was actually 214; "5 TODO-park entries" was actually 24;
"archive gates on G3" was already complete at close; TODO-park path drift.

**Verifier checklist (run before sprint-close commit):**

1. For each tracked repo, `git rev-list --count <upstream>..HEAD` — record
   the number; if upstream missing, record "no upstream tracking".
2. For TODO-park-style enumerations, `find <path> -name '<file>'` to
   confirm the path the STATUS doc claims; `grep -c '^### '` for entry count.
3. For "gates on G-N" claims, verify the gate condition (DNS / kubectl /
   commit) before sprint-close, not at sprint-open.
4. STATUS doc should prefer **link to live command** over absolute claim
   where possible. E.g. "current ahead count: `git rev-list --count
origin/main..HEAD` (run from `infra/`)".

## Field-note discipline

Every commit changing **deployed state** (helm release, droplet count,
DNS record, secret content, cluster topology) MUST either:

1. Update `Universe/spike/field-notes/<team>.md` journal with a dated
   entry, or
2. Declare in commit body: `field-note: not-applicable (reason)`.

CI/pre-commit may grep commits for `feat(charts|infra|secrets|dns|cluster):`
patterns and warn if neither field-note diff nor the declaration is
present. Initial enforcement: convention; later: hook.

This rule fixes the "hidden gaps" pattern surfaced in the 2026-05-02
reality audit: state changed (gxy-static torn down, woodpecker consumer
retired) without a field-note alert that would have flagged the change to
future operators.

## Parking decisions — propagation rule

Every parking decision (deferring an ADR-promised capability) propagates
to **3 places** in the same commit batch:

1. **TODO-park** — entry under correct category with activation trigger
   - owner + ADR ref.
2. **The ADR** — Status field updated or "Phase notes" amendment block
   appended (e.g. `Deferred: ArgoCD deployment parked 2026-04-?? — see
TODO-park entry #N. Activation trigger: ...`).
3. **Field-notes/<team>.md journal** — dated entry recording the
   operational reality.

Single-place parking is the spec-lies-reality-honest pattern. The
2026-05-02 reality audit found ArgoCD + Zot parked in TODO-park (#1, #8)
but ADR-005, spike-plan galaxy map, and field-notes Status block all
still claimed Phase 0 / live. This rule prevents the recurrence.
