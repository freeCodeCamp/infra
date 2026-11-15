# AGENTS.md

## Work

- When a change alters an operator step, update its runbook or guide in the same commit. See `docs`.
- `.scratchpad/` is gitignored and holds internal planning. Treat it as sensitive.

## Secrets

- `../infra-secrets` is a private sibling repo at that hard-codeAnother layout breaks direnv. This repo holds no secrets, not even encrypted ones.
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

Check the live state before you act: `vultr-cli instance list`, `doctl compute droplet list`, or `KUBECONFIG=k3s/<cluster>/.kubeconfig.yaml kubectl get nodes`.
