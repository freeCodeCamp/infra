# CLAUDE.md

freeCodeCamp.org infra-as-code: the legacy fCC estate (Linode) and the DigitalOcean `ops-o11y` cluster.

The Universe platform (`gxy-*` galaxies, artemis, Caddy-S3) was torn down in October 2026. Its docs live in `freeCodeCamp-Universe/Architecture` under `docs/infra/` (start at `REBUILD.md`). The last infra commit with the Universe code is `027d913d6f38`. The guides and RFCs here keep historical `gxy-*` examples; those paths exist only at that commit.

Related repos:

- `../infra-secrets` — sops+age vault. Hard-coded relative-path sibling (see "infra-secrets coupling" below).

## Doc ownership

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

| Path                 | Purpose                                                          |
| -------------------- | ---------------------------------------------------------------- |
| `docs/runbooks/`     | Single-purpose ops runbooks (numbered, index `00-index.md`)      |
| `docs/architecture/` | RFCs for non-trivial work                                        |
| `docs/infra-guides/` | Generic primers (k3s layout, legacy fCC ops, etc.)               |
| `docs/GUIDELINES.md` | Field-note format spec (legacy; field-notes archived 2026-05-10) |

## Working directory rule

Run every recipe from the repo root. Recipes that need a cluster take it as an arg and export `KUBECONFIG` themselves.

direnv `.envrc` hierarchy:

- root `.envrc` → org-wide tokens (`global/.env.enc` + `r2-read/.env.enc`) load on every `cd` into the repo. The session hooks keep an agent out of the plaintext.
- `ansible/.envrc` → sources root + adds `$SECRETS_DIR/do-universe/.env.enc` (DO token for the ansible DO inventory).
- `terraform/ops-o11y/.envrc` → sources root + adds `do-universe/.env.enc` and `tfstate/.env.enc` (state in R2 `infra-tfstate`).
- `k3s/ops-o11y/.envrc` → sources root + exports `KUBECONFIG`.
- `k3s/ops-backoffice-tools/.envrc` → sources root + adds `do-primary/.env.enc`.

`do-universe/` and `tfstate/` keep their Universe-era names because non-Universe work reads them. They stay as they are until someone replaces them one by one (operator 2026-10-05).

## infra-secrets coupling

Private sibling repo at hard-coded relative path `../infra-secrets` (sops + age, single org key, `.sops.yaml` regex `.*`). Root `.envrc` resolves `SECRETS_DIR=../infra-secrets`; any other layout breaks direnv loading. No secrets this repo — not even encrypted.

Layout contract + per-path consumer matrix: `docs/architecture/rfc-secrets-layout.md`.

Decrypt envelopes (`*.env.enc`): `docs/runbooks/04-secrets-decrypt.md`. sops auto-detect routes `.enc` to JSON parser and silently fails — explicit `--input-type dotenv --output-type dotenv` is required.

## Operations

**New work adds no `just` recipes (operator 2026-09-03).** The recipes are brittle and abstract too much. Write standard-toolchain commands instead: `terraform -chdir=<dir>`, `ansible-playbook <full-playbook-name>.yml`, `helm`, `kubectl`. Carry `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml` explicitly on every `kubectl` and `helm` call, so a runbook line pastes into a bare shell. The existing recipes and the docs that reference them stay as they are.

## Ansible

- Per-group config: `ansible/inventory/group_vars/<group>.yml`
- Playbooks generic orchestrators — reference variables, not literal values
- Add a group: create a group_vars file matching the DO inventory tag

## Clusters

- `ops-o11y` (inventory group `ops_o11y`): DigitalOcean droplets `ops-vm-o11y-k3s-fra1-NN` (Terraform `node_count`, default 3; runbook 14), the observability cluster and the seed of the bare-metal `mgmt` cluster. `doctl` shows it in VPC `gxy-vpc-fra1`, which keeps its Universe-era name.
- `ops-backoffice-tools`: legacy.

Verify reality with `doctl compute droplet list` before acting.

## Non-obvious conventions

- `just bootstrap` prepends `play-` + appends `.yml` to playbook arg.
