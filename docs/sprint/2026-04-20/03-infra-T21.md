# Session 03 — T21: `.woodpecker/deploy.yaml` pipeline template

**Beads:** `gxy-static-k7d.22` · **Repo:** `fCC/infra` · **Branch:** `feat/k3s-universe`
**Blocks:** T15. **Blocked by:** T11 (per-site secrets must exist to reference).

## Why this matters

This is the canonical 10-step pipeline that every constellation copies into its
repo. Step order is load-bearing per D24:
`verify → snapshot → purge-pre → write-alias → smoke → revert`. Any
divergence risks a bad-alias window on failed promote.

The YAML is specified verbatim in RFC §4.6.2 lines 886-1213. Your job is to
transcribe, validate, and stage it as a copyable template.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC/infra
claude
```

Then paste the prompt below.

---

## Dispatch prompt

````
You are implementing beads `gxy-static-k7d.22` — T21: `.woodpecker/deploy.yaml`
pipeline template. Authoritative spec:

- `docs/rfc/gxy-cassiopeia.md` §4.6.2 (lines 886-1213) — full YAML
- `docs/tasks/gxy-cassiopeia.md` Task 21 (line 3590) — agent prompt
- `bd show gxy-static-k7d.22` — beads DESIGN block

## Environment

- cwd: `/Users/mrugesh/DEV/fCC/infra`
- branch: `feat/k3s-universe`
- python3 available (for yaml validation)

## Preconditions

1. `dp_beads_show gxy-static-k7d.12` — T11 closed (per-site secrets provisioned)
2. `dp_beads_show gxy-static-k7d.33` — T32 closed (Woodpecker reachable)
3. RFC §4.6.2 present in `docs/rfc/gxy-cassiopeia.md` — `grep -n "4.6.2" docs/rfc/gxy-cassiopeia.md`

## Execute in order

1. **Read RFC §4.6.2 end-to-end** in `docs/rfc/gxy-cassiopeia.md`. Every
   `when.evaluate` gate and every env var is specified there.
2. **Create `docs/templates/woodpecker-static-deploy.yaml`** — copy YAML from
   RFC §4.6.2 verbatim starting at `when:` through the closing brace. Prepend
   the header comment from the task doc Step 2.
3. **Validate with python yaml** — run the validation script from Task 21 Step 3:
   ```bash
   python3 -c '
   import yaml
   with open("docs/templates/woodpecker-static-deploy.yaml") as f:
       doc = yaml.safe_load(f)
   assert "steps" in doc
   names = [list(s.keys())[0] if isinstance(s, dict) else s for s in doc["steps"]] if isinstance(doc["steps"], list) else list(doc["steps"].keys())
   expected = ["compute-deploy-id","build","upload","resolve-deploy-id","verify-deploy","snapshot-previous-alias","purge-cache-pre","write-alias","smoke-test","revert-alias"]
   for e in expected: assert e in names, f"missing: {e}"
   print("OK:", names)
   '
   ```
4. **`woodpecker-cli lint`** — if available locally:
   ```bash
   command -v woodpecker-cli && woodpecker-cli lint docs/templates/woodpecker-static-deploy.yaml
   ```
   If `woodpecker-cli` is not installed, note that and rely on python validation.
5. **Stage a test constellation** — create or reuse a test repo under
   `freeCodeCamp-Universe/hello-world` (if it does not exist, flag). Copy the
   template to its `.woodpecker/deploy.yaml`. This is manual / ClickOps —
   write the instruction, do not create the GitHub repo from the session.
6. **Document** — add a section to `docs/FLIGHT-MANUAL.md` or a new
   `docs/templates/README.md` explaining how staff use the template. Keep it
   short; the authority is the RFC.

## Acceptance criteria

- `docs/templates/woodpecker-static-deploy.yaml` exists
- python yaml validation passes with all 10 expected step names
- `woodpecker-cli lint` passes (or noted as deferred if CLI unavailable)
- Template references **repo-scope** secrets, not org-scope (grep the YAML —
  no `from_secret: r2_*` at pipeline-global level; each step references via
  `when` or `environment`)
- No hardcoded `deploy.example.com`-style placeholders — uses
  `${WOODPECKER_REPO_*}` env and Woodpecker built-in vars
- Header comment present with RFC cross-reference and D24 ordering note

## TDD

Validation is the python yaml script + woodpecker-cli lint. No unit tests for
a template file.

## Constraints

- Do NOT modify the RFC in this task. If you spot a bug in RFC §4.6.2, flag it
  for the operator — spec change is a separate workflow.
- Do NOT publish the template outside the infra repo (no `universe-templates`
  repo exists yet — v1 keeps it here per task doc §Repo and CWD).
- Do NOT push.

## Output expected back to operator

1. File paths created/modified
2. python yaml validation output
3. woodpecker-cli lint output (or "CLI unavailable" note)
4. Proposed Conventional Commits message
5. "T21 ready to close" signal

## Commit policy

Prepare commit; do not push. Operator runs `/cmd-git-rules` before commit.

## When stuck

- If RFC §4.6.2 has been edited since the task was filed, reconcile: the YAML
  you ship must match the CURRENT RFC. Note any diff in the task notes.
- If a step name expected by the task doc is missing from the RFC (e.g., RFC
  renamed `snapshot` → `snapshot-previous-alias`), update the task doc
  acceptance list to match the RFC — RFC wins.
````

---

## Hand-off

When T21 closes, unblock [06-infra-T15.md](06-infra-T15.md).
