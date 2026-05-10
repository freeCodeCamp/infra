# Archived runbooks (2026-05-10)

Materials retired from the active runbook surface during the
universe-master-audit (2026-05-10). Kept here for historical context;
do **not** reference from new docs.

| File                                 | Why retired                                                                               |
| ------------------------------------ | ----------------------------------------------------------------------------------------- |
| `07-woodpecker-oauth-app.md`         | Woodpecker CI retired 2026-05-03 (no consumer post-D016 pivot). OAuth app no longer used. |
| `08-woodpecker-cf-access.md`         | Same — no Woodpecker, no CF Access setup to maintain.                                     |
| `09-woodpecker-bringup-checklist.md` | Same — bring-up checklist for a service no longer deployed.                               |

Woodpecker chart at `k3s/gxy-launchbase/apps/woodpecker/` is also
slated for archive; gxy-launchbase chapter §C documents the standby
state without Woodpecker.

If a future sprint reactivates a CI plane, write fresh runbooks
matching the chosen tooling — do not resurrect these.

Source-of-truth for the retire decision:
`docs/architecture/adr-drift-2026-05-10.md` §ADR-005 / §ADR-016.
