# CLAUDE.md

freeCodeCamp.org infra-as-code. Primary: freeCodeCamp Universe platform (DigitalOcean + Hetzner planned, Cloudflare, R2). Legacy fCC infra (Linode, Azure) coexist, retire post-Universe.

**Galaxy design lives in Universe ADRs + spike plan. No dup design content this repo.**

## Doc ownership

Authoritative model + flow diagram auto-loaded:

@~/DEV/fCC-U/Universe/CLAUDE.md

Field notes for this repo (Infra team owns):

@~/DEV/fCC-U/Universe/spike/field-notes/infra.md

This repo owns:

| Path                   | Purpose                                            |
| ---------------------- | -------------------------------------------------- |
| `docs/GUIDELINES.md`   | Doc conventions + monthly trim                     |
| `docs/flight-manuals/` | Per-cluster doomsday rebuild (index `00-index.md`) |
| `docs/runbooks/`       | Single-purpose ops runbooks                        |
| `docs/architecture/`   | RFCs for non-trivial work                          |
| `docs/sprints/`        | Active sprint at top, archive below                |

## Working directory rule (HARD)

**Repo-wide `just` recipes that touch a cluster MUST run from `k3s/<galaxy>/` subfolder.** direnv `.envrc` hierarchy loads cluster-scoped tokens + `KUBECONFIG` only inside the galaxy dir:

- root `.envrc` → loads `$SECRETS_DIR/global/.env.enc` (org-wide tokens)
- `k3s/<galaxy>/.envrc` → sources root, loads `$SECRETS_DIR/do-universe/.env.enc` (DO Universe token), exports `KUBECONFIG=$(expand_path .kubeconfig.yaml)`

Run `just deploy …` from repo root → wrong DO token, no `KUBECONFIG`, helm/kubectl hit wrong cluster or fail. Always:

```
cd k3s/<galaxy>/
just <recipe>
```

Recipes that don't touch a cluster (e.g. `just play <playbook>` against ansible inventory) may run from repo root.

## infra-secrets coupling

Private sibling repo at hard-coded relative path `../infra-secrets` (sops + age, single org key, `.sops.yaml` regex `.*`). Root `.envrc` resolves `SECRETS_DIR=../infra-secrets`; any other layout breaks direnv loading. No secrets this repo — not even encrypted.

### Layout contract (consumed by `.envrc` + helm value overlays)

| Path                    | Consumer                                               |
| ----------------------- | ------------------------------------------------------ |
| `global/.env.enc`       | Root `.envrc` — org-wide tokens                        |
| `global/tls/`           | Cert material                                          |
| `do-universe/.env.enc`  | Every Universe galaxy `.envrc` — DO team token         |
| `do-primary/.env.enc`   | Legacy DO token                                        |
| `k3s/<cluster>/`        | Per-cluster kubeconfigs / sealed material              |
| `<app>/.env.enc`        | App-level overlay (e.g. `windmill/`, `outline/`)       |
| `<scope>/<app>.env.enc` | Scoped app overlay (e.g. `management/artemis.env.enc`) |
| `scratchpad/`           | Drafts — never consumed by recipes                     |

New galaxy/app: mint secret at the matching path before first `just deploy`. Adding new top-level scopes requires updating the consumer (`.envrc` line or helm `--set-file` source).

### Decrypt incantation

`.env.enc` decrypt requires explicit type flags. sops auto-detect on `.enc` extension falls back to JSON parser; dotenv envelopes silently fail (`Error unmarshalling input json: invalid character '#'`).

```
sops decrypt --input-type dotenv --output-type dotenv \
  ../infra-secrets/<scope>/<name>.env.enc
```

Helm chart secret-rendering recipes + ops scripts MUST pass both flags. Alternative (deferred): per-glob `input_type: dotenv` pin in `.sops.yaml` — current rules block has no per-path type config.

## Operations

`just` lists recipes. cd into `k3s/<galaxy>/` first for cluster-scoped recipes (see Working directory rule).

## Sprint protocol

Sprint-driven work. Active sprint = newest non-archive dir under `docs/sprints/`. Multi-session work flows through sprint docs on disk, not external trackers.

**Operator vocabulary** — full closure checklist + session-start ritual in `docs/GUIDELINES.md` §Sprint docs:

| Operator says               | Claude does                                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `start the sprint`          | Read active `sprints/<date>/{README,STATUS}.md`. Report state. Wait for `go`.                                |
| `roll the sprint`           | Rewrite active `STATUS.md` from git log + dispatch Status headers. Single commit.                            |
| `give me the resume prompt` | Print active `STATUS.md` Resume-prompt block verbatim.                                                       |
| `next move?`                | Per `STATUS.md` Open + `PLAN.md` Wave graph, name next unblocked task with ID, dispatch path, blockedBy.     |
| `dispatch <T-id>`           | Open `dispatches/<T-id>-*.md`. Confirm preconditions. Flip Status → `in-progress`. Begin work.               |
| `close <T-id>`              | Run closure checklist (`docs/GUIDELINES.md`): flip Status, update PLAN matrix, append HANDOFF, derived docs. |
| `verify <T-id\|G-id>`       | Run dispatch's read-only Verify block; report green/red. Required green before any operator-action gate.     |

**Invariants:**

- Decisions never silently rewritten — amendment block with date.
- HANDOFF entries never edited — append correction.
- Inter-doc conflicts surfaced on detection, not silently resolved.
- Skipping derived-doc updates on closure = sprint bug.

## Ansible

- Per-galaxy config: `ansible/inventory/group_vars/<group>.yml`
- Playbooks generic orchestrators — reference variables, not literal values
- Add galaxy: create group_vars file matching DO inventory tag

## Clusters

Per-galaxy state, providers, and rollout phase live in `~/DEV/fCC-U/Universe/spike/spike-plan.md` (canonical). Verify reality with `doctl compute droplet list` before acting.

Inventory groups (matches `ansible/inventory/group_vars/`):

| Galaxy           | Inventory Group      |
| ---------------- | -------------------- |
| `gxy-management` | `gxy_management_k3s` |
| `gxy-static`     | `gxy_static_k3s`     |
| `gxy-launchbase` | `gxy_launchbase_k3s` |
| `gxy-cassiopeia` | `gxy_cassiopeia_k3s` |

Legacy clusters (out of scope Universe baseline; retire post-Universe): `ops-backoffice-tools`, `ops-mgmt`. No touch when executing Universe work.

## Key directories

| Path             | Purpose                                      |
| ---------------- | -------------------------------------------- |
| `ansible/`       | Playbooks, roles, inventory                  |
| `k3s/<cluster>/` | Per-cluster apps, charts, manifests, configs |
| `terraform/`     | Terraform workspaces (Linode/DO)             |
| `docker/swarm/`  | Legacy Docker Swarm stacks                   |
| `cloud-init/`    | VM bootstrap configs                         |

## Non-obvious conventions

- Helm chart repos: `k3s/<cluster>/apps/<app>/charts/<chart>/repo` (one-line file with URL); no repo file → `helm-upgrade` installs from local chart dir
- `just play` prepends `play-` + appends `.yml` to playbook arg
- Gateway API listener ports must match Traefik entrypoint ports (80/443 with hostNetwork)
- PSS admission exempt: `windmill` + `tailscale` namespaces (privileged workloads)

## justfile recipe slop discipline

**No new per-app one-off recipes.** Before adding under `[group('k3s')]` / `[group('secrets')]` / `[group('smoke')]`:

1. Read full existing recipe set end-to-end (`just --list`, `wc -l justfile`). Not grep keywords.
2. Thin wrapper over `helm-upgrade` with one extra flag (e.g. `--set-file`) → **extend generic recipe** via per-app `apps/<app>/.deploy-flags.sh` sourced for `EXTRA_HELM_ARGS`. Do NOT clone helm-install body.
3. **One-time** per cluster (mint, mirror, seal) → inline in runbook. Promote to recipe only if re-run >~3×/year.
4. Sweep duplication: `git diff justfile | grep '^+' | head -50` — if `helm upgrade --install` repeated, refactor before commit.

Reviewer rule: any recipe added in same commit as new app under `k3s/<cluster>/apps/<app>/` = code smell. Flag for inline-in-runbook OR generic-recipe-extension before merge.

Background: T34 closeout (sprint-2026-04-26) — `artemis-deploy` + `mirror-artemis-secrets` violated rules 2+3. Refactor parked at `docs/TODO-park.md` §Justfile slop sweep (post-G1).
