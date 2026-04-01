set shell := ["bash", "-cu"]

ansible_vault := "uv run --project ansible ansible-vault"
vault_password := "--vault-password-file <(op read \"op://Service-Automation/Ansible-Vault-Password/Ansible-Vault-Password\")"

# Show available recipes
default:
    @just --list

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

# Bootstrap root .env (global tokens only — Cloudflare, Linode)
[group('secrets')]
secret-bootstrap:
    #!/usr/bin/env bash
    set -eu
    SRC="secrets/global/.env"
    [ -f "$SRC" ] || { echo "Error: $SRC not found. Get it from 1Password."; exit 1; }
    {{ansible_vault}} decrypt --output .env {{vault_password}} "$SRC"
    echo "Bootstrapped .env (global tokens)"
    echo "Run: direnv allow"

# Bootstrap a cluster .env (DO_API_TOKEN + KUBECONFIG)
[group('secrets')]
secret-bootstrap-cluster cluster team:
    #!/usr/bin/env bash
    set -eu
    SRC="secrets/do-{{team}}/.env"
    DEST="k3s/{{cluster}}/.env"
    [ -f "$SRC" ] || { echo "Error: $SRC not found. Get it from 1Password."; exit 1; }
    {{ansible_vault}} decrypt --output - {{vault_password}} "$SRC" > "$DEST"
    echo "KUBECONFIG=.kubeconfig.yaml" >> "$DEST"
    echo "Bootstrapped $DEST (team: {{team}})"
    echo "Run: cd k3s/{{cluster}} && direnv allow"

# Encrypt a secret
[group('secrets')]
secret-encrypt name:
    {{ansible_vault}} encrypt {{vault_password}} secrets/{{name}}/.env

# Decrypt a secret to stdout
[group('secrets')]
secret-decrypt name:
    {{ansible_vault}} decrypt --output - {{vault_password}} secrets/{{name}}/.env

# Decrypt a secret to a file
[group('secrets')]
secret-decrypt-to name dest:
    {{ansible_vault}} decrypt --output {{dest}} {{vault_password}} secrets/{{name}}/.env

# View a secret
[group('secrets')]
secret-view name:
    {{ansible_vault}} view {{vault_password}} secrets/{{name}}/.env

# Edit a secret
[group('secrets')]
secret-edit name:
    {{ansible_vault}} edit {{vault_password}} secrets/{{name}}/.env

# Encrypt all unencrypted .env files in secrets/
[group('secrets')]
secret-encrypt-all:
    #!/usr/bin/env bash
    set -eu
    for f in secrets/*/.env; do
      [ -f "$f" ] || continue
      if ! head -1 "$f" | grep -q '^\$ANSIBLE_VAULT'; then
        echo "Encrypting $f"
        {{ansible_vault}} encrypt {{vault_password}} "$f"
      else
        echo "Already encrypted: $f"
      fi
    done

# Verify all encrypted secrets are readable
[group('secrets')]
secret-verify-all:
    #!/usr/bin/env bash
    set -eu
    for f in secrets/*/.env; do
      [ -f "$f" ] || continue
      echo -n "$f: "
      {{ansible_vault}} view {{vault_password}} "$f" > /dev/null 2>&1 && echo "OK" || echo "FAILED"
    done

# ---------------------------------------------------------------------------
# K8s / K3s
# ---------------------------------------------------------------------------

# Deploy a K8s app (decrypt secrets → apply → clean up)
[group('k3s')]
deploy cluster app:
    #!/usr/bin/env bash
    set -eu
    SECRETS_SRC="secrets/{{app}}/.env"
    SECRETS_DST="k3s/{{cluster}}/apps/{{app}}/manifests/base/secrets/.secrets.env"

    if [ ! -f "$SECRETS_SRC" ]; then
      echo "Error: $SECRETS_SRC not found"
      echo "Create it: cp secrets/{{app}}/.env.sample secrets/{{app}}/.env && just secret-encrypt {{app}}"
      exit 1
    fi

    {{ansible_vault}} decrypt --output "$SECRETS_DST" {{vault_password}} "$SECRETS_SRC"
    trap 'rm -f "$SECRETS_DST"' EXIT

    cd k3s/{{cluster}}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    kubectl apply -k apps/{{app}}/manifests/base/
    echo "Deployed {{app}} to {{cluster}}"

# ---------------------------------------------------------------------------
# Ansible
# ---------------------------------------------------------------------------

# Install ansible and dependencies
[group('ansible')]
ansible-install:
    cd ansible && uv sync && uv run ansible-galaxy install -r requirements.yml

# Test connection to a random VM
[group('ansible')]
ansible-test inventory="linode.yml":
    #!/usr/bin/env bash
    set -eu
    cd ansible
    VM_COUNT=$(uv run ansible-inventory -i inventory/{{inventory}} --list 2>/dev/null | jq -r '._meta.hostvars | keys | length')
    echo "Found $VM_COUNT VMs"
    [ "$VM_COUNT" -eq 0 ] && echo "No VMs found" && exit 1
    RANDOM_INDEX=$(( RANDOM % VM_COUNT ))
    uv run ansible -i inventory/{{inventory}} "all[$RANDOM_INDEX]" -m ping --one-line -v

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

# List all Terraform workspaces
[group('terraform')]
tf-list:
    @find terraform -name ".terraform.lock.hcl" -exec dirname {} \; | sort

# Format Terraform files
[group('terraform')]
tf-format:
    #!/usr/bin/env bash
    set -eu
    for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \;); do
      echo "Formatting $ws"
      terraform -chdir=$ws fmt
    done

# Validate Terraform configurations
[group('terraform')]
tf-validate:
    #!/usr/bin/env bash
    set -eu
    for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \;); do
      echo "Validating $ws"
      terraform -chdir=$ws validate
    done

# Initialize Terraform workspaces
[group('terraform')]
tf-init:
    #!/usr/bin/env bash
    set -eu
    for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \;); do
      echo "Initializing $ws"
      terraform -chdir=$ws init
    done

# Initialize and upgrade Terraform workspaces
[group('terraform')]
tf-init-upgrade:
    #!/usr/bin/env bash
    set -eu
    for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \;); do
      echo "Upgrading $ws"
      terraform -chdir=$ws init -upgrade
    done

# Plan all Terraform workspaces
[group('terraform')]
tf-plan:
    #!/usr/bin/env bash
    set -eu
    for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \;); do
      echo "Planning $ws"
      terraform -chdir=$ws plan
    done
