# T15 — Phase 4 test-site smoke validation runbook + script

**Status:** done
**Worker:** w-infra
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 15](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §6.6 Phase 4 exit](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q6 (≤2 min rollback SLO — poll 30s × 2 green hits)
**Started:** 2026-04-25
**Closed:** 2026-04-25
**Closing commit(s):** (filled at commit)

---

## Files to touch

Per spec §Task 15 § Files:

- Create: `docs/runbooks/phase4-test-site-smoke.md`
- Create: `scripts/phase4-test-site-smoke.sh`
- Modify: `justfile` (add `phase4-smoke` recipe under `[group('smoke')]`)

## Acceptance criteria

Authoritative: spec §Task 15 § Acceptance Criteria. All must pass.
Summary: script exits 0 against provisioned cassiopeia + R2; runbook
covers success + failure (rollback) paths; `just phase4-smoke` invokes
script with environment pre-loaded.

## Discipline

- TDD: where the script has discrete bash functions, write `bats` or
  shell-driven tests first if practical; otherwise stub fixtures + dry-run.
- `set -euo pipefail`, `[[ ]]` conditionals, `printf` over `echo`,
  `shellcheck` clean.
- Local dry-run BEFORE any live cassiopeia call.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.
- Close: edit Status `pending → in-progress → done`, fill closure block.

---

## Closure

- **Status:** done
- **Closing commit:** (filled at commit)
- **Acceptance evidence:**
  - `shellcheck scripts/phase4-test-site-smoke.sh` — clean
  - `shellcheck scripts/tests/phase4-test-site-smoke.sh` — clean (one
    `# shellcheck disable=SC2016` directive — backticks-in-singles are
    literal docs, intended)
  - `bash -n scripts/phase4-test-site-smoke.sh` — clean
  - `just phase4-smoke-test` (static contract suite) — `OK:
phase4-test-site-smoke.sh contract satisfied`. Asserts `set -euo
pipefail`, all 7 env guards, D35 dot-scheme preview hostname, trap
    - `rclone purge` cleanup (acceptance §2544 — cleanup on success
      AND failure), no `echo -n`, no POSIX `[ ]`, shellcheck clean,
      `bash -n` clean.
  - `just --unstable --fmt --check` — exits 0
- **Deltas from spec body:**
  - Preview hostname **dot-scheme** (`test.preview.freecode.camp`),
    not the dash-scheme (`test--preview.freecode.camp`) shown in the
    spec snippet — D35 supersedes.
  - Trap upgraded from `rm -rf $TMP_DIR` only → cleanup function that
    also `rclone purge`s the test prefix on every exit path
    (acceptance §2544 — script must clean R2 on success AND failure).
    The trap-only-tmpdir form fails the contract test.
  - Env guards expanded to all 7 required vars (spec snippet only
    guarded 4).
  - `printf` over `echo -n`; `[[ ]]` over `[ ]`; matches
    `~/.claude/rules/shell.md`.
  - Q6 SLO honoured: step 4 polls 30s × 2 consecutive green hits,
    bounded by 4 attempts.
  - justfile group is `[group('smoke')]` per dispatch §Files-to-touch
    (not `cassiopeia` as the spec body suggests). Two recipes added:
    `phase4-smoke` (live gate) + `phase4-smoke-test` (static contract).
- **Live R2 / DNS run:** NOT executed by this dispatch. Script + runbook
  shipped; operator runs `just phase4-smoke` against gxy-cassiopeia
  with operator-added temp DNS per the runbook prerequisites. RFC §6.6
  Phase 4 exit fires only after that operator run is green.
- **Sprint-doc patches owed:** PLAN.md T15 matrix row flipped `[x] done`
  - STATUS.md refreshed (T15 closed, A.2 T16 next) + HANDOFF.md
    appended in this commit.
