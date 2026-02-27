# Terraform/OpenTofu Secrets (Local + `op` CLI)

## Goal

Load all secrets locally from 1Password using `op` CLI. Do not store secrets in git, `.tfvars`, or backend files.

## Prerequisites

1. `op` CLI installed and signed in.
2. OpenTofu installed.
3. 1Password items created for infra credentials.

## Required Environment Variables

Backend (Cloudflare R2, S3-compatible backend auth):

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

Terraform/OpenTofu input variables (`TF_VAR_*`):

- `TF_VAR_linode_token`
- `TF_VAR_do_token`
- `TF_VAR_cloudflare_api_token`
- `TF_VAR_hcp_client_id`
- `TF_VAR_hcp_client_secret`
- `TF_VAR_password` (only stacks that require it)
- `TF_VAR_network_subdomain` (stacks that require it)
- `TF_VAR_ssh_terraform_ed25519_private_key` (only `stg-cluster-ahoyworld`)

## Example Loader Script

Create a local, untracked shell file and source it before running `tofu`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# R2 backend auth
export AWS_ACCESS_KEY_ID="$(op read 'op://YOUR_VAULT/R2 Access Key/username')"
export AWS_SECRET_ACCESS_KEY="$(op read 'op://YOUR_VAULT/R2 Access Key/password')"

# Provider/API credentials
export TF_VAR_linode_token="$(op read 'op://YOUR_VAULT/Linode Token/token')"
export TF_VAR_do_token="$(op read 'op://YOUR_VAULT/DigitalOcean Token/token')"
export TF_VAR_cloudflare_api_token="$(op read 'op://YOUR_VAULT/Cloudflare Token/token')"
export TF_VAR_hcp_client_id="$(op read 'op://YOUR_VAULT/HCP Client/id')"
export TF_VAR_hcp_client_secret="$(op read 'op://YOUR_VAULT/HCP Client/credential')"

# Stack-specific vars (export only when needed)
export TF_VAR_password="$(op read 'op://YOUR_VAULT/Linode Root Password/password')"
export TF_VAR_network_subdomain="$(op read 'op://YOUR_VAULT/Network Subdomain/value')"
export TF_VAR_ssh_terraform_ed25519_private_key="$(op read 'op://YOUR_VAULT/Terraform SSH Key/private key')"
```

## Rules

- Never commit secret material.
- Keep backend config files secret-free (bucket/key/endpoint config only).
- Rotate tokens regularly and on operator offboarding.
