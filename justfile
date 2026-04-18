set shell := ["bash", "-cu"]

secrets_dir := env("SECRETS_DIR", justfile_directory() + "/../infra-secrets")
crds_schema := 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Show available recipes
default:
    @just --list

# ---------------------------------------------------------------------------
# Secrets (sops + age — stored in infra-secrets private repo)
# ---------------------------------------------------------------------------

# View a decrypted secret (auto-detects format from extension)
[group('secrets')]
secret-view name:
    #!/usr/bin/env bash
    set -eu
    FILE=$(find "{{secrets_dir}}/{{name}}" -name '*.enc' -type f | head -1)
    [ -f "$FILE" ] || { echo "Error: no .enc file in {{secrets_dir}}/{{name}}/"; exit 1; }
    case "$FILE" in
      *.env.enc)            sops -d --input-type dotenv --output-type dotenv "$FILE" ;;
      *.yaml.enc|*.yml.enc) sops -d --input-type yaml --output-type yaml "$FILE" ;;
      *)                    sops -d "$FILE" ;;
    esac

# Edit a secret in $EDITOR
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
        *.env.enc)            sops -d --input-type dotenv --output-type dotenv "$f" > /dev/null 2>&1 ;;
        *.yaml.enc|*.yml.enc) sops -d --input-type yaml --output-type yaml "$f" > /dev/null 2>&1 ;;
        *)                    sops -d "$f" > /dev/null 2>&1 ;;
      esac && echo "OK" || echo "FAILED"
    done

# ---------------------------------------------------------------------------
# K8s / K3s
# ---------------------------------------------------------------------------

# Decrypt kubeconfig from infra-secrets (run once after clone)
[group('k3s')]
kubeconfig-sync cluster:
    #!/usr/bin/env bash
    set -eu
    SRC="{{secrets_dir}}/k3s/{{cluster}}/kubeconfig.yaml.enc"
    DST="k3s/{{cluster}}/.kubeconfig.yaml"
    [ -f "$SRC" ] || { echo "Error: $SRC not found (cluster not yet bootstrapped?)"; exit 1; }
    umask 077
    sops -d --input-type yaml --output-type yaml "$SRC" > "$DST"
    chmod 600 "$DST"
    echo "Synced kubeconfig → $DST"

# Deploy app (decrypt secrets + TLS → kustomize apply → cleanup)
[group('k3s')]
deploy cluster app:
    #!/usr/bin/env bash
    set -eu
    ENC_DIR="{{secrets_dir}}/k3s/{{cluster}}"
    APP_SECRETS="k3s/{{cluster}}/apps/{{app}}/manifests/base/secrets"
    CLEANUP=""

    if [ -f "$ENC_DIR/{{app}}.secrets.env.enc" ]; then
      sops -d --input-type dotenv --output-type dotenv "$ENC_DIR/{{app}}.secrets.env.enc" > "$APP_SECRETS/.secrets.env"
      CLEANUP="$APP_SECRETS/.secrets.env"
      trap "rm -f $CLEANUP" EXIT
    fi
    if [ -f "$ENC_DIR/{{app}}.tls.crt.enc" ]; then
      sops -d "$ENC_DIR/{{app}}.tls.crt.enc" > "$APP_SECRETS/tls.crt"
      CLEANUP="$CLEANUP $APP_SECRETS/tls.crt"
      trap "rm -f $CLEANUP" EXIT
    fi
    if [ -f "$ENC_DIR/{{app}}.tls.key.enc" ]; then
      sops -d "$ENC_DIR/{{app}}.tls.key.enc" > "$APP_SECRETS/tls.key"
      CLEANUP="$CLEANUP $APP_SECRETS/tls.key"
      trap "rm -f $CLEANUP" EXIT
    fi
    if [ -f "$ENC_DIR/{{app}}-backup.secrets.env.enc" ]; then
      sops -d --input-type dotenv --output-type dotenv "$ENC_DIR/{{app}}-backup.secrets.env.enc" > "$APP_SECRETS/.backup-secrets.env"
      CLEANUP="$CLEANUP $APP_SECRETS/.backup-secrets.env"
      trap "rm -f $CLEANUP" EXIT
    fi

    cd k3s/{{cluster}}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    kubectl apply -k apps/{{app}}/manifests/base/
    echo "Deployed {{app}} to {{cluster}}"

# Install or upgrade a Helm chart (overlays secret values from infra-secrets if present)
[group('k3s')]
helm-upgrade cluster app:
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{cluster}}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    CHART_DIR=$(find "apps/{{app}}/charts" -maxdepth 1 -mindepth 1 -type d | head -1)
    [ -d "$CHART_DIR" ] || { echo "Error: no chart dir in apps/{{app}}/charts/"; exit 1; }
    CHART_NAME=$(basename "$CHART_DIR")
    VALUES="$CHART_DIR/values.yaml"
    [ -f "$VALUES" ] || { echo "Error: $VALUES not found"; exit 1; }
    HELM_ARGS="-f $VALUES"
    CLEANUP=""
    SECRET_VALUES="{{secrets_dir}}/k3s/{{cluster}}/{{app}}.values.yaml.enc"
    if [ -f "$SECRET_VALUES" ]; then
      TMPVALS=$(mktemp)
      sops -d --input-type yaml --output-type yaml "$SECRET_VALUES" > "$TMPVALS"
      HELM_ARGS="$HELM_ARGS -f $TMPVALS"
      CLEANUP="$TMPVALS"
      trap "rm -f $CLEANUP" EXIT
    fi

    REPO_FILE="$CHART_DIR/repo"
    if [ -f "$REPO_FILE" ]; then
      REPO_URL=$(cat "$REPO_FILE")
      echo "Installing {{app}} (chart: $CHART_NAME) from $REPO_URL"
      helm upgrade --install {{app}} "$CHART_NAME" \
        --repo "$REPO_URL" \
        -n {{app}} --create-namespace \
        $HELM_ARGS
    else
      echo "Installing {{app}} (chart: $CHART_NAME) from local directory"
      helm upgrade --install {{app}} "$CHART_DIR" \
        -n {{app}} --create-namespace \
        $HELM_ARGS
    fi

# Ad-hoc Windmill PostgreSQL backup (local file)
[group('k3s')]
windmill-backup cluster:
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{cluster}}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    mkdir -p .backups
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    FILENAME="windmill-${TIMESTAMP}.sql.gz"
    PG_POD=$(kubectl get pod -n windmill -l app=windmill-postgresql-demo-app -o jsonpath='{.items[0].metadata.name}')
    [ -n "${PG_POD}" ] || { echo "Error: no PostgreSQL pod found in windmill namespace"; exit 1; }
    echo "Backing up Windmill PostgreSQL from ${PG_POD}..."
    kubectl exec -n windmill "${PG_POD}" -- bash -c 'PGPASSWORD="${POSTGRES_PASSWORD}" pg_dumpall -U postgres --clean --if-exists' | gzip > ".backups/${FILENAME}"
    FILESIZE=$(stat -f%z ".backups/${FILENAME}" 2>/dev/null || stat -c%s ".backups/${FILENAME}")
    [ "${FILESIZE}" -gt 100 ] || { echo "Error: backup file too small (${FILESIZE} bytes) — likely empty dump"; exit 1; }
    echo "Saved: .backups/${FILENAME} (${FILESIZE} bytes)"

# Validate K8s manifests with kubeconform
[group('k3s')]
k8s-validate version="1.32.0":
    kubeconform \
      -summary \
      -output text \
      -strict \
      -ignore-missing-schemas \
      -kubernetes-version {{version}} \
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

# Run any ansible playbook (logs to ansible/.ansible/logs/)
[group('ansible')]
[positional-arguments]
play playbook host *args:
    #!/usr/bin/env bash
    set -eu
    mkdir -p ansible/.ansible/logs
    LOGFILE="$(pwd)/ansible/.ansible/logs/$(date +%Y%m%d-%H%M%S)-{{playbook}}.log"
    cd ansible && uv run ansible-playbook -i inventory/digitalocean.yml play-{{playbook}}.yml \
      -e variable_host={{host}} {{args}} 2>&1 | tee "$LOGFILE"
    echo "Log: $LOGFILE"

# Install ansible dependencies
[group('ansible')]
ansible-install:
    cd ansible && uv sync && uv run ansible-galaxy install -r requirements.yml

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

# Run terraform on one or all workspaces
[group('terraform')]
tf cmd workspace="all":
    #!/usr/bin/env bash
    set -eu
    if [ "{{workspace}}" = "all" ]; then
      for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \; | sort); do
        echo "==> $ws: terraform {{cmd}}"
        terraform -chdir=$ws {{cmd}}
      done
    else
      ws="terraform/{{workspace}}"
      [ -d "$ws" ] || { echo "Error: $ws not found"; exit 1; }
      terraform -chdir=$ws {{cmd}}
    fi

# List terraform workspaces
[group('terraform')]
tf-list:
    @find terraform -name ".terraform.lock.hcl" -exec dirname {} \; | sort

# ---------------------------------------------------------------------------
# Storage (R2 buckets, access keys)
# ---------------------------------------------------------------------------

# Verify an R2 bucket is provisioned correctly (exists, rw/ro keys work, ro cannot write).
# Reads credentials from infra-secrets/<bucket-cluster>/r2-{rw,ro}.env.enc via sops.
[group('storage')]
r2-bucket-verify bucket:
    scripts/r2-bucket-verify.sh {{bucket}}

# ---------------------------------------------------------------------------
# Monitoring (Cloudflare Notifications + Uptime Robot)
# ---------------------------------------------------------------------------

# Apply declarative Cloudflare Notifications from cloudflare/notifications.yaml.
# Use --dry-run to preview without writing.
[group('monitoring')]
cf-notifications-apply *args:
    scripts/cf-notifications-apply.sh {{args}}

# Apply declarative Uptime Robot monitors from uptime-robot/monitors.yaml.
# Use --dry-run to preview without writing.
[group('monitoring')]
uptime-robot-apply *args:
    scripts/uptime-robot-apply.sh {{args}}
