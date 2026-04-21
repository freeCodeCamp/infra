# Session 07 — T26: FLIGHT-MANUAL update for gxy-launchbase + gxy-cassiopeia

**Beads:** `gxy-static-k7d.27` · **Repo:** `fCC/infra` · Size: **[S]**
**Blocks:** nothing. **Blocked by:** nothing — run parallel at T+0.

## Why this matters

`docs/FLIGHT-MANUAL.md` is the SINGULAR doomsday rebuild doc. Every phase from
T05 onward must be recoverable from this manual with no external context. The
existing gxy-static + gxy-management sections are the template.

## Start session

```bash
cd /Users/mrugesh/DEV/fCC/infra
claude
```

---

## Dispatch prompt

```
You are implementing beads `gxy-static-k7d.27` — T26: Migration constraint docs
update (FLIGHT-MANUAL). Authoritative spec:

- `docs/tasks/gxy-cassiopeia.md` Task 26 (line 4794) — step-by-step
- `dp_beads_show gxy-static-k7d.27`

## Environment

- cwd: `/Users/mrugesh/DEV/fCC/infra`
- branch: `feat/k3s-universe`

## Execute in order

1. **Read current `docs/FLIGHT-MANUAL.md`** — match existing tone, depth,
   structure. Existing gxy-static and gxy-management sections are the template.
2. **Add Part: gxy-launchbase (CI galaxy, 3× DO FRA1 s-4vcpu-8gb-amd)** with
   subsections matching the existing format:
   - Pre-flight
   - Phase 1: Infrastructure (OpenTofu via `k3s/gxy-launchbase/terraform/`)
   - Phase 2: Cluster bootstrap (Ansible `just play k3s--bootstrap -e target_hosts=gxy_launchbase_k3s`)
   - Phase 3: CNPG + Postgres Cluster CR
   - Phase 4: Woodpecker install (chart + secrets + HTTPRoute + CiliumNetworkPolicy)
   - Phase 5: DNS + Cloudflare Access (links to `docs/runbooks/woodpecker-cf-access.md` — created in T32)
   - Phase 6: OAuth app provisioning (links to `docs/runbooks/woodpecker-oauth-app.md` from T10)
   - Backups (CNPG WAL-G to R2 via `cnpg-backup.yaml`)
   - Usage (how to trigger a first pipeline)
3. **Add Part: gxy-cassiopeia (production static galaxy, 3× DO FRA1)** with:
   - Pre-flight
   - Phase 1: Infrastructure
   - Phase 2: Cluster bootstrap
   - Phase 3: Caddy Helm chart install
   - Phase 4: R2 bucket provisioning (link to `docs/runbooks/r2-bucket-setup.md`)
   - Phase 5: CF DNS + origin allow-list (link to T14 cron + manifest)
   - Phase 6: First deploy via Woodpecker pipeline (link to template from T21)
   - Troubleshooting: alias cache invalidation, R2 503s, CF cache purge
4. **Migration constraint section** — append a short section "Post-M5 Hetzner
   migration" pointing to T30 (deferred) with the constraint that Talos/k0s
   evaluation must complete before migration.
5. **Cross-link in existing sections** — e.g., if `docs/runbooks/` has a
   cutover doc from T25, link to it from gxy-cassiopeia Phase 6.
6. **markdownlint** — `markdownlint docs/FLIGHT-MANUAL.md` passes.

## Acceptance criteria

- `docs/FLIGHT-MANUAL.md` contains new Parts for gxy-launchbase + gxy-cassiopeia
- Every `just` recipe referenced exists (grep the justfile; if a recipe is
  missing, the fix is to ADD the recipe, not to describe a raw command in the
  manual)
- Every `docs/runbooks/` link resolves (check with `ls docs/runbooks/`)
- Every `k3s/gxy-<galaxy>/apps/<app>/` path referenced exists
- markdownlint clean
- The TOC (if present) is updated
- Reads like the existing sections — same verbosity, same command fence style,
  same header hierarchy

## TDD

No unit tests. Verification:
1. `markdownlint docs/FLIGHT-MANUAL.md`
2. Link-check: `grep -oE '\[.+?\]\([^)]+\)' docs/FLIGHT-MANUAL.md | awk -F'[()]' '{print $2}' | while read p; do test -e "$p" || echo "BROKEN: $p"; done`
3. Justfile recipes referenced: `grep -oE 'just [a-z-]+' docs/FLIGHT-MANUAL.md | sort -u | awk '{print $2}' | while read r; do grep -q "^$r" justfile || echo "MISSING: $r"; done`

## Constraints

- Do NOT put raw ansible-playbook / kubectl / helm incantations in the manual.
  Wrap them in justfile recipes first (per `.claude/rules/docs-ops.md`).
- Do NOT put design rationale in the manual — that lives in ADRs and the RFC.
- Do NOT push.

## Docs to update

This task IS a docs update. Primary artifact:

- `/Users/mrugesh/DEV/fCC/infra/docs/FLIGHT-MANUAL.md` — new gxy-launchbase
  + gxy-cassiopeia Parts.

Secondary: if the edit surfaces a missing justfile recipe or a broken
runbook link, fix at source — justfile or `docs/runbooks/*.md`. No
field-notes update unless a genuine operational finding surfaces during
the edit (e.g., a path inconsistency worth flagging for Universe team).

## Output expected

1. Diff of FLIGHT-MANUAL.md
2. Any new justfile recipes
3. Link-check + justfile-recipe-check output (both clean)
4. Proposed commit message
5. "T26 ready to close" signal

## Commit policy

Prepare commit; do not push.

## When stuck

- If a phase references a runbook that does NOT exist yet (T14 allow-list,
  T24 monitors), link to the beads task ID with a "TBD when <task id> closes"
  note; do not fabricate runbook contents.
- If gxy-cassiopeia does not yet have terraform/ scaffolding for Phase 1, note
  that the manual currently assumes manual DO UI provisioning, and flag the
  follow-up to the operator. Do not write terraform code in this session.
```

---

## Hand-off

T26 closes independently.
