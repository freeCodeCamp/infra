# T15 — Phase 4 test-site smoke validation runbook + script

**Status:** pending
**Worker:** w-infra
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 15](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §6.6 Phase 4 exit](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q6 (≤2 min rollback SLO — poll 30s × 2 green hits)
**Started:** —
**Closed:** —
**Closing commit(s):** —

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

## Closure (filled on completion)

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `shellcheck scripts/phase4-test-site-smoke.sh` — clean
  - `bash -n scripts/phase4-test-site-smoke.sh` — clean
  - `just phase4-smoke` dry-run — exits 0 against fixtures
- **Surprises:** —
- **Sprint-doc patches owed:** check matrix row in
  `24-static-apps-k7d.md` flips to `[x] done`.
