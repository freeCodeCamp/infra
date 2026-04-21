# Sprint 2026-04-20 — Ship gxy-static-k7d

Goal: ship Woodpecker-driven static deploy pipeline end-to-end. Release
`@freecodecamp/universe-cli@0.4.0-beta.1`. Close Phase 4 of the Universe
platform rollout.

Epic: `gxy-static-k7d` (aka gxy-cassiopeia).
Spec: [`docs/rfc/gxy-cassiopeia.md`](../../rfc/gxy-cassiopeia.md).
Task breakdown: [`docs/tasks/gxy-cassiopeia.md`](../../tasks/gxy-cassiopeia.md).

## What is already done (do not redo)

- **Universe repo drift** — committed 2026-04-18/19 (9f1a3fd, 11fe346, 1a41205).
  ADR-001/002/007/013, spike-plan.md, Universe/CLAUDE.md, field-notes reflect
  D13-revised + D32 + 2026-04-20 status. No re-work needed.
- **Universe v0.4 field notes** — on local branch `docs/universe-cli-v0.4-pivot`
  (commit `e625868`), 1 ahead of origin/main. Documents SSE parser, bundle
  shrink, T20 deletions, open questions. Needs push + merge (operator).
- **universe-cli hygiene** — on origin/main (40ad837, 00002aa, 6127fcd, fe3d0b7,
  6078227). CLAUDE.md, oxlint, husky, EXIT_CREDENTIALS rename, site-name `--`
  guard, pre-pivot doc notes all in.
- **universe-cli T16/T17/T18/T19/T20 code** — IMPLEMENTED LOCALLY on `main`:
  `a7dd58e` (Woodpecker client + validation + credentials) + `f6971cf` (rewrite
  deploy/promote/rollback + delete legacy storage/deploy/credentials/resolver
  - remove @aws-sdk/client-s3 / mrmime / p-limit). Local `main` 2 ahead of
    origin/main. Bundle 1.95 MB → 812 KB. No `@aws-sdk` refs in src.
    **Only release prep missing**: version bump (still 0.3.3), CHANGELOG entry
    for 0.4.0-beta.1, push, live E2E smoke, CI publish.
- **infra T01-T05, T07-T10, T12, T13, T23, T24, T25, T31** — shipped on
  `feat/k3s-universe` branch.

## Remaining work (10 open tasks)

```
T32 (infra)  ─┐                         ┌─> T29 (Universe)
              ├─> T11 (windmill) ─┐     │
              │                   ├─> T15 (infra) ─ ┤
T14 (windmill)────────────────────┘     │          │
                                        │          │
T22 (windmill)  — standalone            │          │
T26 (infra)     — standalone            │          │
T27 (Universe)  — standalone            │          │
T28 (Universe)  — after M1 signal       │          │
                                        │          │
                       T21 (infra) ─────┘          │
                                                    │
                             universe-cli: push + live E2E + release 0.4.0-beta.1
                             (T20 code deletions already in f6971cf; only release prep left)
```

## Dispatch order (optimized for 8h)

| #   | When                | Session file                                             | Repo               | Blocking           |
| --- | ------------------- | -------------------------------------------------------- | ------------------ | ------------------ |
| 1   | T+0h                | [01-infra-T32.md](01-infra-T32.md)                       | fCC/infra          | Critical path root |
| 2   | T+0h (parallel)     | [04-windmill-T14.md](04-windmill-T14.md)                 | fCC-U/windmill     | Independent        |
| 3   | T+0h (parallel)     | [05-windmill-T22.md](05-windmill-T22.md)                 | fCC-U/windmill     | Independent        |
| 4   | T+0h (parallel)     | [07-infra-T26.md](07-infra-T26.md)                       | fCC/infra          | Independent, [S]   |
| 5   | T+0h (parallel)     | [08-universe-T27.md](08-universe-T27.md)                 | fCC-U/Universe     | Independent, [S]   |
| 6   | After T32 closes    | [02-windmill-T11.md](02-windmill-T11.md)                 | fCC-U/windmill     | Blocks T21, T15    |
| 7   | After T32 closes    | [03-infra-T21.md](03-infra-T21.md)                       | fCC/infra          | Blocks T15         |
| 8   | After T11 closes    | [08-universe-T28.md](08-universe-T28.md)                 | fCC-U/Universe     | [S]                |
| 9   | After T11+T21 close | [06-infra-T15.md](06-infra-T15.md)                       | fCC/infra          | Gates release      |
| 10  | After T15 closes    | [09-universe-cli-release.md](09-universe-cli-release.md) | fCC-U/universe-cli | Critical path tail |
| 11  | After T15 closes    | [08-universe-T29.md](08-universe-T29.md)                 | fCC-U/Universe     | [S]                |

Parallelism floor: 3 concurrent sessions (T32 + one windmill + one docs task).
Parallelism ceiling at T+0: 5 sessions (T32, T14, T22, T26, T27).

## How to run each session

Each `NN-*.md` file in this directory is a self-contained dispatch prompt.

```bash
# Open a new terminal, cd to the repo the session targets, then:
claude
# Paste the full contents of the session's .md file as the first message.
```

The session prompt tells Claude Code:

- Which beads task ID is being worked
- Which repo, which cwd
- What acceptance criteria must be met
- What commands to run to verify
- How to commit and what to do when done

Each dispatch uses `/dp-cto:plan` + `/dp-cto:run` or direct subagent dispatch.
Dispatch commands are at the bottom of each file.

## Completion definition

Today is done when:

1. All 10 remaining epic tasks are closed in beads.
2. `@freecodecamp/universe-cli@0.4.0-beta.1` is published to npm.
3. At least one test constellation has been deployed via `universe static deploy`
   through the new Woodpecker pipeline and serves from R2 via gxy-cassiopeia
   behind `*.freecode.camp`.
4. `docs/FLIGHT-MANUAL.md` covers gxy-launchbase + gxy-cassiopeia rebuild from
   zero.
5. `spike/field-notes/infra.md` has Phase 0, 1-2, and 4 entries filled with real
   measurements.

## Non-goals for today

- DNS cutover (`*.freecode.camp` gxy-static → gxy-cassiopeia). That is Phase 6
  (T25 runbook already exists; cutover execution is a separate operator day).
- Hetzner migration (T30, deferred post-M5).
- universe-cli GA release. 0.4.0-beta.1 is explicitly a beta; GA follows soak.

## Safety rails

- Every session plan ends with a **Commit policy** section — most dispatches ask
  the session to prepare commits and hand back a diff; operator commits.
- No session pushes to origin without explicit operator signal.
- CF Access setup (T32) is ClickOps — Claude writes the runbook, operator
  executes.
- DNS changes are production-impacting. T32 touches DNS; rollback is a second
  DNS edit.
