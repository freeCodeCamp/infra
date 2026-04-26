# Sprint 2026-04-26 — HANDOFF (history log)

Append-only dated log of what shipped each session. **Not a resume doc** — see [`STATUS.md`](STATUS.md) for live cursor and resume prompt. Plan + decisions live in [`PLAN.md`](PLAN.md) + [`DECISIONS.md`](DECISIONS.md).

Convention:

- One entry per session at top of "Journal".
- Dated `YYYY-MM-DD — <one-line summary>`.
- Body: what shipped, what failed, what blocked, links to commits.
- Never edit past entries — append correction entry referencing the original.

## Journal

### 2026-04-26 (late evening) — Sprint opens at branch point

Governing session in `~/DEV/fCC/infra` (branch `feat/k3s-universe`).

**Predecessor:** [`../archive/2026-04-21/`](../archive/2026-04-21/).
That sprint shipped Wave A.1 (Caddy `r2_alias` D35 dot-scheme + R2
single-bucket layout + Phase 4 smoke harness) green. Wave A.2
(`universe-cli@feat/woodpecker-pivot`) shipped but is archaeology
post-pivot. Wave A.3 (T11 per-site R2 token mint) SUPERSEDED by D016
deploy-proxy plane (logged in archived sprint HANDOFF 2026-04-26
evening + this sprint DECISIONS D43).

**This sprint scope:** Phase 1 sub-deliverables P1.1 + P1.7 + P1.8
(deploy-proxy svc + universe-cli v0.4 + `platform.yaml` v2 schema). T22
cleanup cron carried forward (post-T31 live verification).

**Authority:** Broken ownership for tonight's session per operator
command 2026-04-26 evening. Session governs cross-repo (Universe ADRs

- universe-cli + windmill + new uploads repo) without per-team
  round-trip. Logged here for transparency. Teams can amend post-hoc via
  append-only blocks.

**Sprint state delta this commit:**

- Created sprint dir `docs/sprints/2026-04-26/` with README, STATUS, PLAN, DECISIONS, HANDOFF (this file).
- Moved 6 active dispatches from prior sprint dir: T22 + T30–T34.
- Archived prior sprint dir → `docs/sprints/archive/2026-04-21/` (full content preserved; closure entry appended to its HANDOFF).
- DECISIONS D43 row + Q9–Q15 brainstorm rationale landed.
- PLAN: Phase 1 sub-deliverables + dispatch graph clean-rewritten (no pre/post pivot mixing).
- STATUS: live cursor focused on T30→T34→T22 sequence; resume prompt rewritten.
- README: read order + layout + predecessor pointer + authority model.

**Carries forward (commits not pushed):** all Phase 0 foundation + Wave
A.1 commits + T11 artifact at `windmill@010d577`. Operator pushes at
sprint close (4 repos + new uploads remote).

**Next move:** open T30. Write `~/DEV/fCC-U/Universe/decisions/016-deploy-proxy.md`.
Single Universe commit. Then T31 (uploads svc Go scaffold + endpoints + tests).

**Tooling verified for incoming work:** Go 1.26.2 darwin/arm64
(`/opt/homebrew/bin/go`). Universe-cli toolchain (Bun + vitest + oxfmt

- oxlint + tsup + husky) unchanged. ctx-mode v1.0.98 healthy
  (`ctx_doctor` PASS).
