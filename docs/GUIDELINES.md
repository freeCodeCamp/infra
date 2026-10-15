# Documentation Guidelines

Conventions for docs maintained by this repo.

## General

- Do not commit internal sprint mechanics, task IDs, agent dispatch machinery, or per-session scratch. Those live in `.scratchpad/`.

## Runbook format

- One operational concern per file. Numeric prefix orders by reader path.
- Imperative verbs. Cite exact commands, exact filenames, exact env vars.
- Cross-link to other runbooks rather than duplicating steps.
- Failure modes get their own section: symptom → cause → fix.

## RFC format (architecture/)

- One RFC per non-trivial work item. Title: `rfc-<topic>.md`.
- Status block at the top: Draft / Accepted / Superseded.
- Superseded RFCs get a single-line pointer to the successor and stay only as long as that pointer earns its keep. Otherwise, delete.
