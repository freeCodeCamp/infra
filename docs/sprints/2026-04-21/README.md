# Sprint 2026-04-21 — Universe Static-Apps MVP

**Goal:** staff team pushes to a repo → site live on gxy-cassiopeia via
R2, served by Caddy, end-to-end, production-polished, ready for real
users.

## Read order (every fresh session)

1. **[`STATUS.md`](STATUS.md)** — live cursor. Shipped / Open / Other
   state / Resume prompt. Read first.
2. **[`PLAN.md`](PLAN.md)** — sprint goal, phases + gates, sub-task
   matrix, Wave dispatch graph, success criteria, invariants.
3. **[`DECISIONS.md`](DECISIONS.md)** — locked Q1–Q8 + D33–D40
   amendment cross-refs. Read-only.
4. **[`HANDOFF.md`](HANDOFF.md)** — append-only history log (what
   shipped each session).
5. **[`dispatches/`](dispatches/)** — per-task briefs (T11–T22) with
   dispatch-doc Status header.

## Layout

```
docs/sprints/2026-04-21/
├── README.md         — this file
├── STATUS.md         — live cursor (rewritten each session-roll)
├── PLAN.md           — stable plan
├── DECISIONS.md      — locked decisions
├── HANDOFF.md        — append-only history log
├── cluster-audit.md  — cost/HA/autoscaling inventory
└── dispatches/       — per-task briefs
```

## Session protocol

See [`docs/GUIDELINES.md` §Sprint docs](../../GUIDELINES.md) and
[`infra/CLAUDE.md` §Sprint protocol](../../../CLAUDE.md) for the
minimal-prompt session-start ritual.

The prior sprint `../2026-04-20/` is archived at `../archive/2026-04-20/`.
