set shell := ["bash", "-cu"]

secrets_dir := env("SECRETS_DIR", justfile_directory() + "/../infra-secrets")
sops_config := secrets_dir + "/.sops.yaml"
crds_schema := 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Show available recipes
default:
    @just --list

# ---------------------------------------------------------------------------
# Secrets (sops + age — stored in infra-secrets private repo)
# ---------------------------------------------------------------------------

# View a secret
[group('secrets')]
secret-view name:
    sops -d --input-type dotenv --output-type dotenv "{{secrets_dir}}/{{name}}/.env.enc"

# Edit a secret
[group('secrets')]
secret-edit name:
    sops "{{secrets_dir}}/{{name}}/.env.enc"

# Verify all encrypted secrets are readable
[group('secrets')]
secret-verify-all:
    #!/usr/bin/env bash
    set -eu
    for f in $(find "{{secrets_dir}}" -name '*.enc' -type f | sort); do
      echo -n "$f: "
      case "$f" in
        *.env.enc)       sops -d --input-type dotenv --output-type dotenv "$f" > /dev/null 2>&1 ;;
        *.yaml.enc|*.yml.enc) sops -d --input-type yaml --output-type yaml "$f" > /dev/null 2>&1 ;;
        *)               sops -d "$f" > /dev/null 2>&1 ;;
      esac && echo "OK" || echo "FAILED"
    done

# ---------------------------------------------------------------------------
# K8s / K3s
# ---------------------------------------------------------------------------

# Deploy a K8s app (decrypt secrets → apply → clean up)
[group('k3s')]
deploy cluster app:
    #!/usr/bin/env bash
    set -eu
    SECRETS_SRC="{{secrets_dir}}/k3s/{{cluster}}/{{app}}.secrets.env.enc"
    SECRETS_DST="k3s/{{cluster}}/apps/{{app}}/manifests/base/secrets/.secrets.env"

    [ -f "$SECRETS_SRC" ] || { echo "Error: $SECRETS_SRC not found"; exit 1; }

    sops -d --input-type dotenv --output-type dotenv "$SECRETS_SRC" > "$SECRETS_DST"
    trap 'rm -f "$SECRETS_DST"' EXIT

    cd k3s/{{cluster}}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    kubectl apply -k apps/{{app}}/manifests/base/
    echo "Deployed {{app}} to {{cluster}}"

# Validate K8s manifests with kubeconform
[group('k3s')]
k8s-validate:
    kubeconform \
      -summary \
      -output text \
      -strict \
      -ignore-missing-schemas \
      -kubernetes-version 1.30.0 \
      -schema-location default \
      -schema-location '{{crds_schema}}' \
      -ignore-filename-pattern 'kustomization\.yaml' \
      -ignore-filename-pattern '\.kubeconfig\.yaml' \
      -ignore-filename-pattern 'values\.yaml' \
      -ignore-filename-pattern 'operator-values\.yaml' \
      -ignore-filename-pattern 'pnpm-lock\.yaml' \
      -ignore-filename-pattern 'pss-admission\.yaml' \
      -ignore-filename-pattern 'audit-policy\.yaml' \
      -ignore-filename-pattern '\.sample' \
      -ignore-filename-pattern 'node_modules' \
      -ignore-filename-pattern '\.json' \
      -ignore-filename-pattern 'dashboards/' \
      k3s/ k8s/

# ---------------------------------------------------------------------------
# Ansible
# ---------------------------------------------------------------------------

# Run galaxy playbook (decrypt vault → run → clean up)
[group('ansible')]
galaxy-play galaxy_name host:
    #!/usr/bin/env bash
    set -eu
    VAULT_SRC="{{secrets_dir}}/ansible/vault-k3s.yaml.enc"
    VAULT_DST="ansible/vars/vault-k3s.yml"
    [ -f "$VAULT_SRC" ] || { echo "Error: $VAULT_SRC not found"; exit 1; }
    sops -d --input-type yaml --output-type yaml "$VAULT_SRC" > "$VAULT_DST"
    trap 'rm -f "$VAULT_DST"' EXIT
    cd ansible
    uv run ansible-playbook -i inventory/digitalocean.yml play-k3s--galaxy.yml \
      -e variable_host={{host}} \
      -e galaxy_name={{galaxy_name}}

# Install Tailscale on hosts
[group('ansible')]
tailscale-install host inventory="digitalocean.yml":
    cd ansible && uv run ansible-playbook -i inventory/{{inventory}} play-tailscale--0-install.yml \
      -e variable_host={{host}}

# Connect hosts to Tailscale network (with SSH)
[group('ansible')]
tailscale-up host inventory="digitalocean.yml":
    cd ansible && uv run ansible-playbook -i inventory/{{inventory}} play-tailscale--1b-up-with-ssh.yml \
      -e variable_host={{host}}

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
