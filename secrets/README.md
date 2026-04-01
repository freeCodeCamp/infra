# Secrets

All secrets in one place. Encrypted with `ansible-vault`. One password unlocks everything.

## Layout

```
secrets/<name>/
  .env              # ansible-vault encrypted (git tracked)
  .env.sample       # plaintext template (git tracked)
```

## Setup

Get the vault password from a team member, then:

```bash
echo 'your-vault-password' > ~/.ansible-vault-password
chmod 600 ~/.ansible-vault-password
```

Or use 1Password:

```bash
--vault-password-file <(op read "op://Service-Automation/Ansible-Vault-Password/Ansible-Vault-Password")
```

## Commands

```bash
# View
ansible-vault view secrets/<name>/.env

# Edit
ansible-vault edit secrets/<name>/.env

# Create new
cp secrets/<name>/.env.sample secrets/<name>/.env
# fill in values
ansible-vault encrypt secrets/<name>/.env

# Decrypt to stdout
ansible-vault decrypt --output - secrets/<name>/.env
```

## Deploy a K8s app

```bash
cd k3s
just deploy <cluster> <app>
```

## Directories

| Directory      | Purpose                                         |
| -------------- | ----------------------------------------------- |
| `global/`      | Shared tokens (Cloudflare, Linode)              |
| `do-legacy/`   | Legacy DO team API token                        |
| `do-universe/` | Universe DO team API token + Spaces credentials |
| `ansible/`     | Playbook runtime secrets (S3, Tailscale OAuth)  |
| `appsmith/`    | Appsmith app secrets                            |
| `outline/`     | Outline app secrets                             |
| `windmill/`    | Windmill app secrets                            |
| `argocd/`      | ArgoCD app secrets                              |
| `zot/`         | Zot registry secrets (S3, htpasswd)             |
