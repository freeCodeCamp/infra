# Session 08b — T28: Field notes, Phase 1-2 readiness

**Beads:** `gxy-static-k7d.29` · **Repo:** `fCC-U/Universe` · Size: **[S]**
**Blocks:** nothing. **Blocked by:** T32 landing + gxy-launchbase provisioned + Woodpecker live.

## Why this matters

Captures gxy-launchbase provisioning + Woodpecker deploy outcomes — real
measurements needed for future capacity planning and ADR revisions. Append
once preconditions above are met.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC-U/Universe
claude
```

---

## Dispatch prompt

````
You are implementing beads `gxy-static-k7d.29` — T28: Update infra field notes,
Phase 1-2 readiness. Authoritative spec:

- `spike/field-notes/infra.md` (append only)
- `docs/tasks/gxy-cassiopeia.md` Task 28 (line 5017) — template
- `dp_beads_show gxy-static-k7d.29`

## Environment

- cwd: `/Users/mrugesh/DEV/fCC-U/Universe`
- Source of truth for measurements: live gxy-launchbase cluster + Woodpecker

## Preconditions — shell only, do NOT call bd

```sh
# Woodpecker reachable + CF Access live
curl -sI https://woodpecker.freecodecamp.net | head -3
# gxy-launchbase cluster up, 3 Ready
kubectl --context gxy-launchbase get nodes
# CNPG Cluster healthy
kubectl --context gxy-launchbase -n woodpecker get cluster
# At least one pipeline has completed (agent inspects Woodpecker UI or API)
````

If any precondition fails, STOP and ask operator whether to proceed with
partial measurements + explicit "not yet measured" markers.

## Execute in order

1. **Gather real measurements**:
   - Node spec actual: `kubectl --context gxy-launchbase get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory,OS:.status.nodeInfo.osImage`
   - Per-node idle RAM/CPU: `kubectl --context gxy-launchbase top nodes` (let cluster settle 1h first)
   - DO cloud-init parity vs documented baseline: diff `cloud-init/k3s-node.yaml` vs what's actually on the nodes; note any drift
   - Woodpecker server image: `kubectl --context gxy-launchbase -n woodpecker get deploy woodpecker-server -o jsonpath='{.spec.template.spec.containers[0].image}'`
   - Server RAM: `kubectl --context gxy-launchbase top pod -n woodpecker`
   - Agent RAM idle: same command, agent pod
   - CNPG restore drill: if done, note outcome; if not, mark "skipped — follow up"
   - GitHub OAuth app scopes: check the app in GitHub UI; document as "`repo`, `read:org`, `user:email`" or whatever actual is
   - CF Access state: `curl -sI https://woodpecker.freecodecamp.net | head -3`
   - First pipeline run: Woodpecker UI → Pipelines → copy number + duration + repo name
2. **Append entry** dated 2026-04-20 under Operational Findings in
   `spike/field-notes/infra.md`, heading `### gxy-launchbase + Woodpecker landed (2026-04-20)`.
3. **Fill template** from task doc Step 1 with actuals. No `<placeholder>` markers.
4. **Lessons / deviations** — free-form paragraph noting anything that diverged
   from RFC / ADR expectations (DO FRA1 substitution for Hetzner per D13,
   etc.).
5. **markdownlint clean**.

## Acceptance criteria

- Entry appended, dated 2026-04-20
- All measurements real
- CF Access state documented
- Lessons paragraph captures at least the D13-revision observation
- markdownlint clean
- Only `spike/field-notes/infra.md` modified

## TDD

No tests. `markdownlint` + `git diff` review only.

## Constraints

- Append only. No restructuring of prior entries.
- No speculative numbers.
- Do not edit ADRs or spike-plan.md.
- Do not push.

## Docs to update (primary artifact)

- `/Users/mrugesh/DEV/fCC-U/Universe/spike/field-notes/infra.md` — append
  Phase 1-2 entry dated 2026-04-20 with real kubectl-measured numbers.
  No placeholders.

## Output expected

1. `git diff spike/field-notes/infra.md`
2. markdownlint output
3. Proposed commit message
4. "T28 ready to close" signal

## When stuck

- If kubectl context `gxy-launchbase` is not configured locally, ask operator
  to provide kubeconfig access (should come via sops + `just kubeconfig-decrypt`).
- If Woodpecker has not yet run any pipeline, leave that row blank with a
  note "no pipeline runs yet — follow up at Phase 4" rather than guessing.

```

---

## Hand-off

T28 closes independently.
```
