# CLAUDE.md

freeCodeCamp.org infra-as-code. Primary: freeCodeCamp Universe platform (DigitalOcean + Hetzner planned, Cloudflare, R2). Legacy fCC infra (Linode, Azure) coexist, retire post-Universe.

Related repos:

- `../infra-secrets` — sops+age vault. Hard-coded relative-path sibling (see "infra-secrets coupling" below).
- `../artemis` — static-apps deploy proxy. Deployed via `docs/runbooks/02-deploy-artemis-service.md`.
- `~/DEV/fCC-U/Universe/` — Universe team's design repo. **Absolute path** (NOT a `..` sibling of this repo). Holds 19 ADRs at `decisions/0{01..19}-*.md` and the spike plan at `spike/spike-plan.md`.
- `~/DEV/fCC-U/windmill/` — Windmill IaC (CLI sync repo for the gxy-management Windmill workspace).

**Design lives in Universe ADRs + spike plan. No dup design content this repo.**

## Doc ownership

Authoritative model + flow diagram in `~/DEV/fCC-U/Universe/CLAUDE.md`.

Operator-runnable flight manuals live in `docs/flight-manuals/` (this repo). Index at `docs/flight-manuals/00-index.md`; read order starts with `UNIVERSE.md`.

ADR-vs-reality reconciliation: `docs/architecture/adr-drift-2026-05-10.md`.

Platform-wide live-state + automation-gap + drift snapshot (2026-05-29 snapshot — re-scout in `.scratchpad/dossier/2026-05-29-universe-doc-trim/`): `docs/architecture/universe-state-2026-05-29.md`.

Cassiopeia GA hardening RFC (Valkey KV substrate, artemis trim, ingress/DNS posture): `.archive/2026-05-26-prose-trim/rfcs-shipped/rfc-gxy-cassiopeia-ga.md`.

Pre-2026-05-10 field-notes are consolidated in `~/DEV/fCC-U/Universe/.archive/` (see `INDEX.md` for the 40-shard grid across 7 topic dirs: artemis, cassiopeia, gxy-static, windmill, universe-cli, infra, audits). New durable operator content goes into the flight-manuals or runbooks, not new field-notes.

Internal-only material (sprints, planning conventions, parked items, audit dossiers) lives in `.scratchpad/` (gitignored). Not tracked, treat as sensitive.

### Sprint state (cross-session)

`.scratchpad/sprints/<YYYY-MM-DD>-<slug>/STATUS.md` is the canonical cross-session status doc. **Read on session open. Update Done/Blocked/Next on session close.** TaskList is in-session only — STATUS.md is the persistent source of truth. Skeleton:

```md
# <slug> — STATUS

## Done

- <wave/task> — <outcome>

## Blocked / Open

- <thing> — <why> — <unblock action>

## Next

- <one concrete next step>
```

Optional siblings: `PLAN.md` (wave list, multi-wave sprints only), `dispatches/W<N>-<topic>.md` (per-wave envelopes Claude can re-read).

This repo owns:

| Path                   | Purpose                                                          |
| ---------------------- | ---------------------------------------------------------------- |
| `docs/flight-manuals/` | Per-cluster doomsday rebuild (index `00-index.md`)               |
| `docs/runbooks/`       | Single-purpose ops runbooks (numbered, index `00-index.md`)      |
| `docs/architecture/`   | RFCs for non-trivial work                                        |
| `docs/infra-guides/`   | Generic primers (k3s layout, legacy fCC ops, etc.)               |
| `docs/GUIDELINES.md`   | Field-note format spec (legacy; field-notes archived 2026-05-10) |

## Working directory rule

Post-`cd3b3a32` (lifecycle-verb refactor 2026-05-13), `just` is no longer cwd-sensitive for the `release` family. Recipes carry the cluster as an arg and self-export `KUBECONFIG` from the recipe body (`justfile:80` — `export KUBECONFIG="$(pwd)/k3s/{{ cluster }}/.kubeconfig.yaml"`). All `release`/`configure`/`inspect`/`destroy`/`backup` recipes run from repo root:

```
just release gxy-management artemis
just inspect-crds gxy-cassiopeia cnpg
just configure-kubeconfig gxy-launchbase
```

direnv `.envrc` hierarchy still loads:

- root `.envrc` → `$SECRETS_DIR/global/.env.enc` (org-wide tokens, e.g. `DO_API_TOKEN`)
- `k3s/<galaxy>/.envrc` → sources root + adds galaxy-scoped tokens (e.g. `$SECRETS_DIR/do-universe/.env.enc`) + exports `KUBECONFIG`

The galaxy-scoped `KUBECONFIG` export is now belt-and-suspenders — recipes that need it set it themselves. The galaxy-scoped DO tokens still matter for recipes that hit DO API directly (terraform `provision`, ansible `bootstrap` with DO dynamic inventory) — but those recipes either accept `cluster` as an arg (`provision`) or operate on ansible inventory unrelated to live cluster state (`bootstrap`).

Practical rule: run from repo root unless a specific recipe documents otherwise. The pre-`cd3b3a32` "cd into `k3s/<galaxy>/` first or helm hits wrong cluster" foot-gun is gone.

## infra-secrets coupling

Private sibling repo at hard-coded relative path `../infra-secrets` (sops + age, single org key, `.sops.yaml` regex `.*`). Root `.envrc` resolves `SECRETS_DIR=../infra-secrets`; any other layout breaks direnv loading. No secrets this repo — not even encrypted.

Layout contract + per-path consumer matrix: `docs/architecture/rfc-secrets-layout.md`.

Decrypt envelopes (`*.env.enc`): `docs/runbooks/04-secrets-decrypt.md`. sops auto-detect routes `.enc` to JSON parser and silently fails — explicit `--input-type dotenv --output-type dotenv` is required.

## Operations

`just` lists recipes. Run from repo root — recipes carry the galaxy as an arg and self-export `KUBECONFIG`. See Working-directory rule above.

## Ansible

- Per-galaxy config: `ansible/inventory/group_vars/<group>.yml`
- Playbooks generic orchestrators — reference variables, not literal values
- Add galaxy: create group_vars file matching DO inventory tag

## Clusters

Per-galaxy state, providers, and rollout phase live in `~/DEV/fCC-U/Universe/spike/spike-plan.md` (canonical, Universe-team-owned). Cluster-vs-ADR reconciliation: `docs/architecture/adr-drift-2026-05-10.md`. Verify reality with `doctl compute droplet list` before acting.

Inventory groups (matches `ansible/inventory/group_vars/`):

| Galaxy           | Inventory Group      | Role                                                             |
| ---------------- | -------------------- | ---------------------------------------------------------------- |
| `gxy-management` | `gxy_management_k3s` | Control plane — Windmill + artemis (`uploads.freecode.camp`)     |
| `gxy-launchbase` | `gxy_launchbase_k3s` | Standby (CNPG operator running) — woodpecker retired 2026-05-03  |
| `gxy-cassiopeia` | `gxy_cassiopeia_k3s` | Static-serve plane — Caddy-S3 fronting `*.freecode.camp` from R2 |

Retired:

- `gxy-static` — RETIRED 2026-04-27 (cutover to gxy-cassiopeia for `*.freecode.camp`). Historical journal: `~/DEV/fCC-U/Universe/.archive/gxy-static/2026-04-27-teardown.md`.

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

- Helm chart repos: `k3s/<cluster>/apps/<app>/charts/<chart>/repo` (one-line file with URL); no repo file → `just release` falls back to the local chart dir.
- `just bootstrap` prepends `play-` + appends `.yml` to playbook arg.
