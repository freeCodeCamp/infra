# CLAUDE.md

freeCodeCamp.org infra-as-code. Primary: freeCodeCamp Universe platform (DigitalOcean + Hetzner planned, Cloudflare, R2). Legacy fCC infra (Linode, Azure) coexist, retire post-Universe.

**Galaxy design lives in Universe ADRs + spike plan. No dup design content this repo.**

## Doc ownership

Authoritative model + flow diagram auto-loaded:

@~/DEV/fCC-U/Universe/CLAUDE.md

Field notes for this repo (Infra team owns): `~/DEV/fCC-U/Universe/spike/field-notes/infra.md` — read on demand. Trim policy + format in `docs/GUIDELINES.md` §Field-note format + §Monthly doc trim. Use `just field-notes-list` / `just field-notes-trim-plan` / `just field-notes-trim` for the maintenance loop.

This repo owns:

| Path                   | Purpose                                            |
| ---------------------- | -------------------------------------------------- |
| `docs/GUIDELINES.md`   | Doc conventions, sprint protocol, monthly trim     |
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

Decrypt: `*.env.enc` envelopes need explicit `--input-type dotenv --output-type dotenv` flags (sops auto-detect on `.enc` routes to JSON parser and silently fails). Full procedure in `docs/runbooks/secrets-decrypt.md`.

## Operations

`just` lists recipes. cd into `k3s/<galaxy>/` first for cluster-scoped recipes (see Working directory rule).

## Sprint protocol

Sprint-driven work. Active sprint = newest non-archive dir under `docs/sprints/`. Multi-session work flows through sprint docs on disk, not external trackers.

**Operator vocabulary, closure checklist, sprint invariants** all live in `docs/GUIDELINES.md` §Sprint docs. Most-used phrases:

- `start the sprint` → read active `sprints/<date>/{README,STATUS}.md`, report state, wait for `go`.
- `next move?` → name next unblocked task with ID, dispatch path, blockedBy.

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

## Pre-merge checklists

- **New chart** at `k3s/<cluster>/apps/<app>/charts/` → `docs/GUIDELINES.md` §Chart pre-merge checklist (5-point: Middleware ns, NetworkPolicy CRD type, env contract, key-format round-trip, CF zone SSL).
- **New justfile recipe** → `docs/GUIDELINES.md` §Justfile slop discipline (4 rules + reviewer rule).
