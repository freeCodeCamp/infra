set shell := ["bash", "-cu"]

secrets_dir := env("SECRETS_DIR", justfile_directory() + "/../infra-secrets")
crds_schema := 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Show available recipes
default:
    @just --list

# Run terraform on one or all workspaces. Examples:
#   just provision plan all
# just provision apply ops-o11y
[group('provision')]
provision cmd workspace="all":
    #!/usr/bin/env bash
    set -eu
    if [ "{{ workspace }}" = "all" ]; then
      for ws in $(find terraform -name ".terraform.lock.hcl" -exec dirname {} \; | sort); do
        echo "==> $ws: terraform {{ cmd }}"
        terraform -chdir=$ws {{ cmd }}
      done
    else
      ws="terraform/{{ workspace }}"
      [ -d "$ws" ] || { echo "Error: $ws not found"; exit 1; }
      terraform -chdir=$ws {{ cmd }}
    fi

# Run any ansible playbook (logs to ansible/.ansible/logs/).
# Example: just bootstrap k3s--single-node ops_o11y
[group('bootstrap')]
[positional-arguments]
bootstrap playbook host *args:
    #!/usr/bin/env bash
    set -eu
    mkdir -p ansible/.ansible/logs
    LOGFILE="$(pwd)/ansible/.ansible/logs/$(date +%Y%m%d-%H%M%S)-{{ playbook }}.log"
    cd ansible && uv run ansible-playbook -i inventory/digitalocean.yml play-{{ playbook }}.yml \
      -e variable_host={{ host }} {{ args }} 2>&1 | tee "$LOGFILE"
    echo "Log: $LOGFILE"

# Install ansible dependencies (one-time on operator laptop)
[group('bootstrap')]
bootstrap-tools:
    cd ansible && uv sync && uv run ansible-galaxy install -r requirements.yml

# Release an app to a cluster — single high-level verb covering both fresh
# install and version upgrade (helm semantics: `helm upgrade --install`).
# Smart-dispatches on what `apps/<app>/` contains:
#
#   apps/<app>/charts/<chart>/  → helm upgrade --install (with values
#                                  layering: chart defaults < production
#                                  overlay < sops sealed overlay)
#   apps/<app>/manifests/base/  → kubectl apply -k (with sops-decrypted
#                                  secrets + TLS materialized into
#                                  manifests/base/secrets/ for the
#                                  kustomization, scrubbed on exit)
#
# Both phases run when both dirs exist (helm first, kustomize second).
#
# Per-app extras: optional `apps/<app>/.deploy-flags.sh` sourced inside
# the helm phase. May export `EXTRA_HELM_ARGS` (e.g. extra `--set` /
# `--set-file` knobs the chart needs from operator-local data).
#
# Examples:
# just release ops-backoffice-tools outline → kustomize only
[group('release')]
release cluster app:
    #!/usr/bin/env bash
    set -eu
    APP_DIR="k3s/{{ cluster }}/apps/{{ app }}"
    [ -d "$APP_DIR" ] || { echo "Error: $APP_DIR not found"; exit 1; }
    ENC_DIR="{{ secrets_dir }}/k3s/{{ cluster }}"
    # Absolute paths in CLEANUP — survives `cd` later for the EXIT trap.
    APP_SECRETS_ABS="$(pwd)/$APP_DIR/manifests/base/secrets"
    CLEANUP=""
    trap 'rm -f $CLEANUP' EXIT
    export KUBECONFIG="$(pwd)/k3s/{{ cluster }}/.kubeconfig.yaml"

    # ---------------- Helm phase (if apps/<app>/charts/<chart>/) -----------
    CHART_DIR=$(find "$APP_DIR/charts" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)
    if [ -n "${CHART_DIR:-}" ] && [ -d "$CHART_DIR" ]; then
      CHART_NAME=$(basename "$CHART_DIR")
      VALUES="$CHART_DIR/values.yaml"
      [ -f "$VALUES" ] || { echo "Error: $VALUES not found"; exit 1; }
      HELM_ARGS="-f $VALUES"
      PROD_OVERLAY="$APP_DIR/values.production.yaml"
      [ -f "$PROD_OVERLAY" ] && HELM_ARGS="$HELM_ARGS -f $PROD_OVERLAY"
      SECRET_VALUES="$ENC_DIR/{{ app }}.values.yaml.enc"
      if [ -f "$SECRET_VALUES" ]; then
        TMPVALS=$(mktemp)
        sops -d --input-type yaml --output-type yaml "$SECRET_VALUES" > "$TMPVALS"
        HELM_ARGS="$HELM_ARGS -f $TMPVALS"
        CLEANUP="$CLEANUP $TMPVALS"
      fi

      # Per-app deploy-flags hook — sourced; may export EXTRA_HELM_ARGS.
      EXTRA_HELM_ARGS=""
      DEPLOY_FLAGS="$APP_DIR/.deploy-flags.sh"
      if [ -f "$DEPLOY_FLAGS" ]; then
        # shellcheck disable=SC1090
        source "$DEPLOY_FLAGS"
      fi

      REPO_FILE="$CHART_DIR/repo"
      if [ -f "$REPO_FILE" ]; then
        REPO_URL=$(cat "$REPO_FILE")
        VERSION_FILE="$CHART_DIR/version"
        # A remote chart with no --version takes whatever is current on
        # the day it runs, so two releases of the same commit can install
        # different charts. Refuse rather than resolve.
        if [ ! -f "$VERSION_FILE" ]; then
          echo "Error: $VERSION_FILE not found — a remote chart must be pinned."
          echo "  Read the live pin:  helm list -n {{ app }} -o json | jq -r '.[0].chart'"
          echo "  Then write it:      echo <version> > $VERSION_FILE"
          exit 1
        fi
        CHART_VERSION=$(cat "$VERSION_FILE")
        echo "Helm: install {{ app }} (chart: $CHART_NAME $CHART_VERSION) from $REPO_URL"
        helm upgrade --install {{ app }} "$CHART_NAME" \
          --repo "$REPO_URL" \
          --version "$CHART_VERSION" \
          -n {{ app }} --create-namespace \
          $HELM_ARGS $EXTRA_HELM_ARGS
      else
        echo "Helm: install {{ app }} (chart: $CHART_NAME) from local"
        helm upgrade --install {{ app }} "$CHART_DIR" \
          -n {{ app }} --create-namespace \
          $HELM_ARGS $EXTRA_HELM_ARGS
      fi
    fi

    # ---------------- Kustomize phase (if apps/<app>/manifests/base/) ------
    if [ -d "$APP_DIR/manifests/base" ]; then
      APP_SECRETS="$APP_DIR/manifests/base/secrets"
      mkdir -p "$APP_SECRETS"

      if [ -f "$ENC_DIR/{{ app }}.secrets.env.enc" ]; then
        sops -d --input-type dotenv --output-type dotenv "$ENC_DIR/{{ app }}.secrets.env.enc" > "$APP_SECRETS/.secrets.env"
        CLEANUP="$CLEANUP $APP_SECRETS_ABS/.secrets.env"
      fi
      # TLS: per-app override first (`<app>.tls.{crt,key}.enc`), else fall
      # back to cluster-default wildcard via `k3s/<cluster>/cluster.tls.zone`
      # marker → `infra-secrets/global/tls/<zone>.{crt,key}.enc`. Both
      # files required.
      if [ -f "$ENC_DIR/{{ app }}.tls.crt.enc" ] && [ -f "$ENC_DIR/{{ app }}.tls.key.enc" ]; then
        sops -d "$ENC_DIR/{{ app }}.tls.crt.enc" > "$APP_SECRETS/tls.crt"
        sops -d "$ENC_DIR/{{ app }}.tls.key.enc" > "$APP_SECRETS/tls.key"
        CLEANUP="$CLEANUP $APP_SECRETS_ABS/tls.crt $APP_SECRETS_ABS/tls.key"
      elif [ -f "k3s/{{ cluster }}/cluster.tls.zone" ]; then
        ZONE=$(tr -d '[:space:]' < "k3s/{{ cluster }}/cluster.tls.zone")
        ZONE_CRT="{{ secrets_dir }}/global/tls/${ZONE}.crt.enc"
        ZONE_KEY="{{ secrets_dir }}/global/tls/${ZONE}.key.enc"
        if [ -f "$ZONE_CRT" ] && [ -f "$ZONE_KEY" ]; then
          sops -d "$ZONE_CRT" > "$APP_SECRETS/tls.crt"
          sops -d "$ZONE_KEY" > "$APP_SECRETS/tls.key"
          CLEANUP="$CLEANUP $APP_SECRETS_ABS/tls.crt $APP_SECRETS_ABS/tls.key"
        fi
      fi
      if [ -f "$ENC_DIR/{{ app }}-backup.secrets.env.enc" ]; then
        sops -d --input-type dotenv --output-type dotenv "$ENC_DIR/{{ app }}-backup.secrets.env.enc" > "$APP_SECRETS/.backup-secrets.env"
        CLEANUP="$CLEANUP $APP_SECRETS_ABS/.backup-secrets.env"
      fi

      ( cd k3s/{{ cluster }} && kubectl apply -k apps/{{ app }}/manifests/base/ )
    fi

    echo "Released {{ app }} to {{ cluster }}"

# Decrypt kubeconfig from infra-secrets to k3s/<cluster>/.kubeconfig.yaml.
# Run once per cluster after clone.
[group('configure')]
configure-kubeconfig cluster:
    #!/usr/bin/env bash
    set -eu
    SRC="{{ secrets_dir }}/k3s/{{ cluster }}/kubeconfig.yaml.enc"
    DST="k3s/{{ cluster }}/.kubeconfig.yaml"
    [ -f "$SRC" ] || { echo "Error: $SRC not found (cluster not yet bootstrapped?)"; exit 1; }
    umask 077
    sops -d --input-type yaml --output-type yaml "$SRC" > "$DST"
    chmod 600 "$DST"
    echo "Synced kubeconfig → $DST"

# Edit a sops-encrypted secret envelope in $EDITOR.
[group('configure')]
configure-secret name:
    sops "{{ secrets_dir }}/{{ name }}/.env.enc"

# Apply cluster policy objects (ResourceQuota/LimitRange baseline) from
# k3s/<cluster>/cluster/policy/. Idempotent server-side apply.
[group('configure')]
configure-policy cluster:
    #!/usr/bin/env bash
    set -eu
    export KUBECONFIG="$(pwd)/k3s/{{ cluster }}/.kubeconfig.yaml"
    SRC="k3s/{{ cluster }}/cluster/policy"
    [ -d "$SRC" ] || { echo "Error: $SRC not found"; exit 1; }
    kubectl apply --server-side -f "$SRC"
    kubectl get resourcequota,limitrange -A | grep -v kube-system || true

# Trim aged journal entries from a field-notes file into
# `journal-archive/YYYY-MM.md` siblings. Default cutoff 30 days.
# Run from a clean working tree — emits a cross-repo diff in Universe.
[group('configure')]
configure-field-notes-trim area="infra" age="30":
    python3 scripts/trim-field-notes.py \
        ../Architecture/spike/field-notes/{{ area }}.md \
        --age-days {{ age }}

# Verify encrypted secrets:
#   stage 1 — each `*.enc` decrypts with the operator's age key
#   stage 2 — path-layout contract per `docs/architecture/rfc-secrets-layout.md`
#             (platform-wide under
#             `global/`, do-context creds under `do-*/`, per-app namespace
# stubs at `<app>/.env.enc`; archive/legacy paths allowed)
[group('verify')]
verify-secrets:
    #!/usr/bin/env bash
    set -uo pipefail
    fail=0

    echo "=== stage 1: decryptability ==="
    for f in $(find "{{ secrets_dir }}" -name '*.enc' -type f | sort); do
      printf '%s: ' "$f"
      case "$f" in
        *.env.enc)            sops -d --input-type dotenv --output-type dotenv "$f" > /dev/null 2>&1 ;;
        *.yaml.enc|*.yml.enc) sops -d --input-type yaml --output-type yaml "$f" > /dev/null 2>&1 ;;
        *)                    sops -d "$f" > /dev/null 2>&1 ;;
      esac && echo "OK" || { echo "FAILED"; fail=1; }
    done

    echo "=== stage 2: path-layout contract ==="
    SECRETS_ROOT="{{ secrets_dir }}"
    unknown=0
    while IFS= read -r f; do
      rel="${f#${SECRETS_ROOT}/}"
      case "$rel" in
        # Platform-wide — RFC §"Two explicit scopes"
        global/.env.enc) ;;
        global/tls/*.crt.enc|global/tls/*.key.enc) ;;
        # DO contexts
        do-primary/.env.enc|do-universe/.env.enc) ;;
        # Per-app platform-wide namespace stubs / r2 reader
        outline/.env.enc|appsmith/.env.enc|r2-read/.env.enc) ;;
        # Legacy (retire post-Universe per RFC)
        archive/*|k3s/ops-backoffice-tools/*) ;;
        # Operator scratchpad (dev-only)
        scratchpad/*) ;;
        *)
          printf 'UNKNOWN: %s\n' "$rel"
          unknown=$((unknown + 1))
          ;;
      esac
    done < <(find "${SECRETS_ROOT}" -name '*.enc' -type f | sort)
    if [ "$unknown" -gt 0 ]; then
      printf 'WARN: %d path(s) outside layout contract — see docs/architecture/rfc-secrets-layout.md\n' "$unknown"
    else
      echo "OK: all .enc files match the layout contract"
    fi

    exit "$fail"

# Show app namespace status (deploys, sts, pods, secrets, recent warnings).
[group('verify')]
verify-app cluster app:
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    NS={{ app }}
    echo "=== {{ cluster }} / {{ app }} ==="
    echo "--- deployments ---"
    kubectl -n "$NS" get deploy -o wide 2>&1 || true
    echo "--- statefulsets ---"
    kubectl -n "$NS" get sts -o wide 2>&1 || true
    echo "--- pods ---"
    kubectl -n "$NS" get pods -o wide 2>&1 || true
    echo "--- services ---"
    kubectl -n "$NS" get svc 2>&1 || true
    echo "--- secrets ---"
    kubectl -n "$NS" get secrets 2>&1 || true
    echo "--- recent warning events ---"
    kubectl -n "$NS" get events --field-selector type=Warning --sort-by=.lastTimestamp 2>&1 | tail -10 || true

# Validate K8s manifests with kubeconform.
#
# Two stages:
#   1. raw manifests in k3s/ (kustomize bases, plain YAML) —
#      chart templates excluded because Go template syntax isn't YAML.
#   2. first-party chart templates rendered via `helm template` against
#      each chart's values.production.yaml + a stub set for the
# sops-only required keys, then piped to kubeconform.
[group('verify')]
verify-manifests version="1.32.0":
    #!/usr/bin/env bash
    set -uo pipefail
    fail=0

    echo "=== stage 1: raw manifests ==="
    kubeconform \
      -summary \
      -output text \
      -strict \
      -ignore-missing-schemas \
      -kubernetes-version {{ version }} \
      -schema-location default \
      -schema-location '{{ crds_schema }}' \
      -ignore-filename-pattern 'kustomization\.yaml' \
      -ignore-filename-pattern '\.kubeconfig\.yaml' \
      -ignore-filename-pattern 'values(\.[^/]+)?\.yaml' \
      -ignore-filename-pattern 'operator-values\.yaml' \
      -ignore-filename-pattern 'pnpm-lock\.yaml' \
      -ignore-filename-pattern 'pss-admission\.yaml' \
      -ignore-filename-pattern 'audit-policy\.yaml' \
      -ignore-filename-pattern '\.sample' \
      -ignore-filename-pattern 'node_modules' \
      -ignore-filename-pattern '\.json' \
      -ignore-filename-pattern 'dashboards/' \
      -ignore-filename-pattern 'charts/.*/(Chart\.yaml|templates/)' \
      k3s/ || fail=1

    exit "$fail"

# View a decrypted secret (auto-detects format from extension).
[group('inspect')]
inspect-secret name:
    #!/usr/bin/env bash
    set -eu
    FILE=$(find "{{ secrets_dir }}/{{ name }}" -name '*.enc' -type f | head -1)
    [ -f "$FILE" ] || { echo "Error: no .enc file in {{ secrets_dir }}/{{ name }}/"; exit 1; }
    case "$FILE" in
      *.env.enc)            sops -d --input-type dotenv --output-type dotenv "$FILE" ;;
      *.yaml.enc|*.yml.enc) sops -d --input-type yaml --output-type yaml "$FILE" ;;
      *)                    sops -d "$FILE" ;;
    esac

# Show installed CRDs filtered by group (e.g. cnpg, gateway).
[group('inspect')]
inspect-crds cluster filter:
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    kubectl get crd | grep -i {{ filter }}

# List terraform workspaces.
[group('inspect')]
inspect-tf:
    @find terraform -name ".terraform.lock.hcl" -exec dirname {} \; | sort

# List canonical journal entries (### YYYY-MM-DD —) in a field-notes file
# with their ages in days. Useful before running `configure-field-notes-trim`.
[group('inspect')]
inspect-field-notes area="infra":
    python3 scripts/trim-field-notes.py \
        ../Architecture/spike/field-notes/{{ area }}.md --list

# Dry-run: show which dated journal entries would be archived by
# `configure-field-notes-trim`. Default cutoff 30 days. Override with `age=N`.
[group('inspect')]
inspect-field-notes-trim area="infra" age="30":
    python3 scripts/trim-field-notes.py \
        ../Architecture/spike/field-notes/{{ area }}.md \
        --age-days {{ age }} --dry-run

