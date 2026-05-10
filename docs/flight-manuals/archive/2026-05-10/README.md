# Archived flight manuals (2026-05-10)

Materials retired from the active flight-manual surface during the
universe-master-audit (2026-05-10). Kept here for historical context;
do **not** reference from new docs.

| File                | Why retired                                                                                                                                           |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gxy-backoffice.md` | Galaxy not provisioned. Parked per `Universe/spike/spike-plan.md §"Galaxy placement map"`. Will be re-authored fresh when the galaxy actually exists. |
| `gxy-triangulum.md` | Same — parked galaxy, no cluster, no need to keep a stub on the active surface.                                                                       |

When either galaxy is provisioned in the future, write a fresh
chapter using the post-2026-05-10 chapter shape (see
`../../UNIVERSE.md` and `../../gxy-cassiopeia.md`). Do not resurrect
the archived versions verbatim — the operator path encoded in them
predates the Valkey + artemis-decoupled-registry design.

Source-of-truth for galaxy state: `Universe/spike/spike-plan.md` and
`docs/architecture/adr-drift-2026-05-10.md`.
