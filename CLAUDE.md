# CLAUDE.md

freeCodeCamp.org infrastructure-as-code. Primary target: freeCodeCamp Universe platform (DigitalOcean + Hetzner planned, Cloudflare, R2). Legacy freeCodeCamp infra (Linode, Azure) coexist, retire post-Universe.

**Galaxy design flow from Universe ADRs + spike plan (see Doc Index). No dup design content this repo.**

## CRIT — justfile recipe slop discipline (2026-04-27, T34 closeout)

**No new per-app one-off recipes.** Before adding any recipe under `[group('k3s')]` / `[group('secrets')]` / `[group('smoke')]`:

1. Read the **full** existing recipe set end-to-end (`just --list`, `wc -l justfile`). Not just grep keywords.
2. If the new operation is a thin wrapper over `helm-upgrade` with one extra flag (e.g. `--set-file`), **extend the generic recipe** via a per-app convention (e.g. optional `apps/<app>/.deploy-flags.sh` sourced for `EXTRA_HELM_ARGS`). Do NOT clone the helm-install body into a per-app recipe.
3. If the new operation is **one-time** per cluster (mint, mirror, seal), put the commands **inline in the runbook**. Only promote to a recipe if it gets re-run more than ~3× per year.
4. Sweep for duplication after adding any recipe: `git diff justfile | grep '^+' | head -50` — if you see `helm upgrade --install` repeated, refactor before commit.

Violation example (T34, sprint-2026-04-26): `artemis-deploy` cloned the helm-install body of `helm-upgrade` purely to inject `--set-file sites=...`. `mirror-artemis-secrets` was a one-time mint dressed up as a recipe. Both were avoidable. Both convoluted the justfile + cost operator time + tokens. Refactor parked at TODO-park §Justfile slop sweep (post-G1).

Reviewer rule (candidate): any recipe added in the same commit as a new app under `k3s/<cluster>/apps/<app>/` is a code smell — flag for inline-in-runbook OR generic-recipe-extension before merge.

## Doc Index

Cross-repo docs, strict ownership. Full model in [Universe/CLAUDE.md](~/DEV/fCC-U/Universe/CLAUDE.md). Info flow: field notes → ADRs → spike plan.

### Universe repo (`~/DEV/fCC-U/Universe`) — Universe team owns

| Doc                             | Purpose                                         |
| ------------------------------- | ----------------------------------------------- |
| `CLAUDE.md`                     | Source/index — doc-ownership model live here    |
| `decisions/001-015`             | Architecture Decision Records (15 ADRs)         |
| `spike/spike-plan.md`           | Master delivery plan + galaxy placement map     |
| `spike/field-notes/infra.md`    | Infra team operational findings (this team own) |
| `spike/field-notes/windmill.md` | Windmill team operational findings              |

### This repo (`~/DEV/fCC/infra`) — Infra team owns

| Doc                    | Purpose                                                              |
| ---------------------- | -------------------------------------------------------------------- |
| `docs/GUIDELINES.md`   | Canonical doc conventions + monthly trim discipline                  |
| `docs/flight-manuals/` | Per-cluster doomsday rebuild manuals (index at `00-index.md`)        |
| `docs/runbooks/`       | Single-purpose operational runbooks (DNS cutover, R2 provision, etc) |
| `docs/architecture/`   | RFCs for non-trivial infra work                                      |
| `docs/sprints/`        | Per-sprint plans + dispatches (active sprint at top, archive below)  |

### Windmill repo (`~/DEV/fCC-U/windmill`) — Windmill team owns

| Doc                     | Purpose                  |
| ----------------------- | ------------------------ |
| `docs/FLIGHT-MANUAL.md` | Windmill rebuild runbook |

## Secrets

Private sibling repo `../infra-secrets` (sops+age). direnv auto-loads tokens on cd into cluster dirs. No secrets this repo — not even encrypted.

**`.env.enc` decrypt requires explicit type flags.** sops auto-detects from `.enc` extension and falls back to JSON parser; dotenv envelopes silently fail (`Error unmarshalling input json: invalid character '#'`). Canonical incantation:

```
sops decrypt --input-type dotenv --output-type dotenv \
  ../infra-secrets/<scope>/<name>.env.enc
```

Helm chart secret-rendering recipes + ops scripts MUST pass both flags. Alternative: pin `input_type: dotenv` per-glob in `.sops.yaml` (deferred — current rules block has no per-path type config).

## Operations

Run `just` see all recipes. cd into cluster dir first so direnv load right tokens.

## Sprint protocol (auto-loaded session contract)

This repo runs sprint-driven work. Active sprint = newest dir under
`docs/sprints/` (not `archive/`). All multi-session work flows through
sprint docs on disk, not external trackers.

**Minimal-prompt vocabulary** — operator says one of:

| Operator says               | Claude does                                                                                                                                                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `start the sprint`          | Read active `sprints/<date>/README.md` → `STATUS.md`. Report current state. No action until told `go`.                                                                                                                                      |
| `roll the sprint`           | Rewrite active sprint's `STATUS.md` from current git log + dispatch-doc Status headers. Single commit. No push.                                                                                                                             |
| `give me the resume prompt` | Print active sprint `STATUS.md` Resume-prompt block verbatim. Nothing else.                                                                                                                                                                 |
| `next move?`                | Per active sprint `STATUS.md` Open + `PLAN.md` Wave graph, name next unblocked task. Show: task ID, dispatch path, blockedBy, ready y/n.                                                                                                    |
| `dispatch <T-id>`           | Open `dispatches/<T-id>-*.md`. Confirm preconditions met. Flip Status header to `in-progress`. Begin work per dispatch brief.                                                                                                               |
| `close <T-id>`              | Run per-task closure checklist (`docs/GUIDELINES.md` §Sprint docs): flip dispatch Status, update PLAN matrix, append HANDOFF entry, update derived docs (flight-manual / field-note / runbook / ADR / TODO-park as applicable). One commit. |
| `verify <T-id\|G-id>`       | Run the dispatch's read-only Verify command block; report green/red. Required green before any "operator runs X" gate or G-dispatch closes. Added 2026-04-26 (sprint-2026-04-21 audit recovery).                                            |

**Session-start ritual** (executed on `start the sprint`):

1. `ls docs/sprints/` — pick newest non-archive dir.
2. Read `README.md` for read-order.
3. Read `STATUS.md` — live cursor.
4. Skim `PLAN.md` Wave graph + `DECISIONS.md` summary table.
5. Report: current wave, last shipped, next unblocked task, blockers.
6. Wait for operator. No action.

**Per-task closure discipline** — when any sub-task closes, the closure
commit MUST update derived docs the change affects:

- Dispatch-doc Status header → `done`.
- Sprint matrix row in `PLAN.md` → `[x] done`.
- `HANDOFF.md` → append dated entry with summary + commit SHA.
- Cluster flight-manual (`docs/flight-manuals/gxy-<name>.md`) if rebuild steps changed.
- Field-note Journal (`~/DEV/fCC-U/Universe/spike/field-notes/<area>.md`) if learning landed (separate commit; cross-repo).
- Runbook (`docs/runbooks/<verb>-<noun>.md`) if procedure introduced/modified.
- ADR amendment (`~/DEV/fCC-U/Universe/decisions/NNN-*.md`) if decision shifted.
- TODO-park (`docs/TODO-park.md`) if work deferred with activation trigger.

Skipping derived-doc updates is a **sprint bug**, not a deferral.

**Invariants:**

- Operator pushes. Session never `git push` / `gh pr create` / `npm publish`.
- Decisions never silently rewritten — always amendment block with date.
- HANDOFF entries never edited — always append correction entry.
- Conflicts between docs surfaced on detection, not silently resolved.

## Ansible

- Per-galaxy config in `ansible/inventory/group_vars/<group>.yml`
- Playbooks generic orchestrators — reference variables, not literal values
- Add galaxy: create group_vars file match DO inventory tag

## Clusters

State match Universe spike plan as of 2026-04-20. Verify reality with `doctl compute droplet list` before acting.

### Universe galaxies

| Galaxy           | Provider          | Inventory Group      | State          | Per spec                                |
| ---------------- | ----------------- | -------------------- | -------------- | --------------------------------------- |
| `gxy-management` | DO FRA1           | `gxy_management_k3s` | Live           | ArgoCD + Windmill + Zot (ADR-003/005)   |
| `gxy-static`     | DO FRA1           | `gxy_static_k3s`     | Live — sandbox | Retires at `gxy-cassiopeia` cutover     |
| `gxy-launchbase` | DO FRA1 → Hetzner | `gxy_launchbase_k3s` | Planned        | Woodpecker + CNPG (ADR-003)             |
| `gxy-cassiopeia` | DO FRA1 → Hetzner | `gxy_cassiopeia_k3s` | Planned        | Static v2 + `caddy.fs.r2` (ADR-007 D32) |
| `gxy-triangulum` | Hetzner BM        | —                    | Future         | Production constellations (post-M5)     |
| `gxy-backoffice` | TBD               | —                    | Future         | O11y stack (ADR-015)                    |

### Legacy (out of scope Universe baseline; retires post-Universe)

| Cluster                | Role               |
| ---------------------- | ------------------ |
| `ops-backoffice-tools` | Legacy fCC tooling |
| `ops-mgmt`             | Legacy fCC mgmt    |

No touch legacy clusters when executing Universe baseline work.

## Key Directories

| Path             | Purpose                                      |
| ---------------- | -------------------------------------------- |
| `ansible/`       | Playbooks, roles, inventory                  |
| `k3s/<cluster>/` | Per-cluster apps, charts, manifests, configs |
| `terraform/`     | Terraform workspaces (Linode/DO)             |
| `docker/swarm/`  | Legacy Docker Swarm stacks                   |
| `cloud-init/`    | VM bootstrap configs                         |

## Non-obvious Conventions

- Helm chart repos stored `k3s/<cluster>/apps/<app>/charts/<chart>/repo` (one-line file with URL); no repo file → `helm-upgrade` install from local chart dir
- `.envrc` hierarchy: root load global tokens, cluster dirs load team-specific DO token
- `just play` prepend `play-` + append `.yml` to playbook name arg
- Gateway API listener ports must match Traefik entrypoint ports (80/443 with hostNetwork)
- PSS admission exempt `windmill` + `tailscale` namespaces (privileged workloads)
