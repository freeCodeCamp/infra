# AGENTS.md

freeCodeCamp.org infrastructure as code: the Vultr fleet, the o11y cluster and the legacy DigitalOcean hosts. The docs index is `docs/README.md`.

- When a change alters an operator step, update its runbook or guide in the same commit.
- Run each command from the repo root, except Ansible commands: run those from `ansible/`.
- Write standard-toolchain commands. Do not add a `justfile`.
- Keep `.scratchpad/` content out of commits, pull requests and issues.

## Secrets

- Keep each secret in `../infra-secrets`, a private sibling repo (sops + age) at that relative path. The root `.envrc` defaults `SECRETS_DIR` to it. Add none to this repo, not even an encrypted one.
- When `CLAUDECODE` is set, each `.envrc` decrypts no envelope and loads no `.env`. The operator starts the agent with `direnv exec / <agent command>`.
- Ask the operator to run each command that needs a token or a 1Password value: `vultr-cli`, a `tofu` plan or apply, a play with a `community.general.onepassword` lookup, the Tailscale join, and a `sops` decrypt.
