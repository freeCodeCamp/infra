# AGENTS.md

freeCodeCamp.org infra-as-code: the Vultr fleet and the observability clusters.

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
- The envelope `tfstate/` keeps its Universe-era name, because current work reads it. Do not rename it. The operator replaces it later.
- When `CLAUDECODE` is set, each `.envrc` decrypts no envelope and loads no `.env`. This gate is not a security boundary: an agent shell also gets the environment of the shell that started it, so start the agent with `direnv exec / claude`.
- Ask the operator to run a command that needs a token or a 1Password value. These include `vultr-cli`, a `tofu` plan or apply, a play with a `community.general.onepassword` lookup, the Tailscale join, and `sops -d`.

## Commands

- Run each command from the repo root, except the Ansible commands: run those from `ansible/`.
- Write standard-toolchain commands. Do not add a `justfile`.
- Use `tofu -chdir=<dir>` for the Vultr dirs (`terraform/vultr-base`, `terraform/*-vultr`). The Vultr state is encrypted with `TF_VAR_state_passphrase`.
- Give `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml` on each `kubectl` and `helm` call, so a runbook line pastes into a bare shell.
- Ansible plays, inventories, inputs and setup are in `docs/infra-guides/ansible.md`. Write `ansible-playbook <play>.yml` with no `uv run` prefix. In a play, reference group variables (`ansible/inventory/group_vars/<group>.yml`), not literal values.
- An agent runs `ansible-playbook` from `ansible/.venv/bin` only with `--check`, and tests inventories with `-c local`.
- Write block maps in Ansible files. A Prettier reflow of a flow map (`{a: 1}`) breaks the Ansible lint.
- Cloudflare DNS: the `.net` zone is OpenTofu in the private `terraform-cloudflare` repo. The `.org` and `.dev` zones are set in the Cloudflare dashboard, except the proxied origin records in `terraform-cloudflare/cf-origin-records`. Do not add a `.org` or `.dev` record to code.

## CI gate

- Each change reaches `main` through a PR. The operator merges it after CI passes.
- Two kinds of change can go straight to `main`: a revert during an incident, and a change only to Markdown files or files under `docs/` or `.claude/`, with no file under `k3s/`, `ansible/`, `terraform/` or `.github/`.
- Before a push, run `npx prettier@3 --check` on the changed files.
- A PR to `main` needs these checks to pass: `Ansible CI Test`, `K8s -- Manifest Validation`, `Leak Check`, `OpenTofu` and `Workflow Lint`. They run on every PR. CodeFactor can stay pending.
- GitHub Actions is the CI gate. Do not run the workflows locally with `act`.
- CI does not cover a play run by hand or a `workflow_dispatch` input. Before you dispatch a workflow, check that its host pattern matches the live inventory groups.

## Clusters

- `ops-o11y-vultr`: three Vultr VMs `ops-vm-o11y-1` to `-3`, K3s with etcd snapshots to R2. Argo CD deploys `k3s/ops-o11y-vultr/`: metrics, logs and alerts (runbook 19).
- `ops-backoffice-tools`: legacy.

Check the live state before you act: `vultr-cli instance list`, `doctl compute droplet list`, or `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl get nodes`.
