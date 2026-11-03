# AGENTS.md

freeCodeCamp.org infra-as-code: the Linode estate, the Vultr fleet that replaces it, and the observability clusters.

The Universe platform (`gxy-*` galaxies, artemis, Caddy-S3) was torn down in October 2026. Its docs live in `freeCodeCamp-Universe/Architecture` under `docs/infra/` (start at `REBUILD.md`). The last infra commit with the Universe code is `027d913d6f38`. A `gxy-*` path in a guide or RFC here exists only at that commit.

## Docs

| Path                 | Purpose                                                         |
| -------------------- | --------------------------------------------------------------- |
| `docs/runbooks/`     | Single-purpose operator runbooks, numbered, index `00-index.md` |
| `docs/architecture/` | RFCs for non-trivial work, archived RFCs under `archive/`       |
| `docs/infra-guides/` | Primers: Ansible plays, k3s layout, Swarm stacks, legacy ops    |
| `docs/GUIDELINES.md` | Runbook and RFC format rules                                    |

When a change alters an operator step, update its runbook or guide in the same commit.

`.scratchpad/` is gitignored and holds internal planning. Treat it as sensitive.

## Secrets

- `../infra-secrets` is a private sibling repo at that hard-coded relative path (sops + age). The root `.envrc` sets `SECRETS_DIR=../infra-secrets`. Another layout breaks direnv. This repo holds no secrets, not even encrypted ones.
- Envelope layout, consumers and decrypt commands: `docs/runbooks/04-secrets-decrypt.md`. sops auto-detect reads `.enc` as JSON and fails, so give `--input-type dotenv --output-type dotenv`.
- The envelopes `do-universe/` and `tfstate/` keep their Universe-era names, because current work reads them. Do not rename them. The operator replaces them one at a time.
- When `CLAUDECODE` is set, each `.envrc` decrypts no envelope and loads no `.env`. This gate is not a security boundary: an agent shell also gets the environment of the shell that started it, so start the agent with `direnv exec / claude`.
- Ask the operator to run a command that needs a token or a 1Password value.

## Commands

- Run each command from the repo root, except the Ansible commands: run those from `ansible/`.
- Write standard-toolchain commands. Do not add a `justfile`.
- Use `tofu -chdir=<dir>` for the Vultr dirs (`terraform/vultr-base`, `terraform/*-vultr`), and `terraform -chdir=<dir>` for the others. The Vultr state is encrypted with `TF_VAR_state_passphrase`.
- Give `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml` on each `kubectl` and `helm` call, so a runbook line pastes into a bare shell.
- Ansible plays, inventories, inputs and setup are in `docs/infra-guides/ansible.md`. Write `ansible-playbook <play>.yml` with no `uv run` prefix. In a play, reference group variables (`ansible/inventory/group_vars/<group>.yml`), not literal values.

## Clusters

- `ops-o11y-vultr`: three Vultr VMs `ops-vm-o11y-1` to `-3`, K3s with etcd snapshots to R2. Argo CD deploys `k3s/ops-o11y-vultr/`: metrics, logs and alerts (runbook 19).
- `ops-o11y`: the DigitalOcean droplet `ops-vm-o11y-k3s-fra1-01`, with Argo CD. Its VPC keeps the Universe-era name `gxy-vpc-fra1`.
- `ops-backoffice-tools`: legacy.

Check the live state before you act: `vultr-cli instance list`, `doctl compute droplet list`, `linode-cli linodes list`, or `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl get nodes`.
