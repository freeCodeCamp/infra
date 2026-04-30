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
