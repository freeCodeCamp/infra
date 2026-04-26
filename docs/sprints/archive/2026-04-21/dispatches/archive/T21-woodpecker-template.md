# T21 — `.woodpecker/deploy.yaml` pipeline template

**Status:** SUPERSEDED 2026-04-26 by D016. Build environment is staff choice post-pivot; CLI uploads to proxy from any environment. Woodpecker template demoted to optional reference example (not critical path). Tracked under post-MVP follow-up if staff demand surfaces.
**Worker:** w-infra
**Repo:** `~/DEV/fCC/infra` (branch: `feat/k3s-universe`)
**Spec:** [`task-gxy-cassiopeia.md` §Task 21](../../architecture/task-gxy-cassiopeia.md)
**RFC:** [`rfc-gxy-cassiopeia.md` §4.6.2 + D24 step ordering](../../architecture/rfc-gxy-cassiopeia.md)
**QA deltas:** Q1 (alias-write last step), Q7 (dual-alias prod+preview)
**Depends on:** T11 closure (worker reads R2 secret format) + T15 (smoke contract)
**Started:** —
**Closed:** —
**Closing commit(s):** —

---

## Files to touch

Per spec §Task 21 § Files:

- Create: `docs/templates/woodpecker-static-deploy.yaml` (v1 home;
  promotes to dedicated `universe-templates` repo post-MVP)

## Acceptance criteria

Authoritative: spec §Task 21 § Acceptance Criteria. All must pass.
Summary: 10-step atomic promote pipeline per D24 ordering;
`from_secret: r2_access_key_id` + `r2_secret_access_key` (repo-scoped
per D22); alias write uses `Cache-Control: no-store` + 5
`x-amz-meta-*` audit fields per §4.4.3; `purge-cache-pre` BEFORE
`write-alias`; `smoke-test` has `failure: ignore`; `revert-alias`
exits non-zero on revert.

## Discipline

- Validate: `woodpecker-cli lint <yaml>` if available, else
  `python3 -c 'import yaml; yaml.safe_load(open("<yaml>"))'`.
- No real R2 secrets in the template — placeholders + `from_secret:` only.
- Operator pushes — commit only.
- Stage specific files; title-only commit per `cmd-git-rules`.

---

## Closure (filled on completion)

- **Status:** —
- **Closing commit:** —
- **Acceptance evidence:**
  - `woodpecker-cli lint` — clean (or YAML parse — clean)
  - step ordering verified vs D24
  - `r2_access_key_id` + `r2_secret_access_key` from_secret refs present
  - `Cache-Control: no-store` on alias writes — present
- **Surprises:** —
- **Sprint-doc patches owed:** matrix row flip.
