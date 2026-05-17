set shell := ["bash", "-cu"]

secrets_dir := env("SECRETS_DIR", justfile_directory() + "/../infra-secrets")
crds_schema := 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Show available recipes
default:
    @just --list

# Run terraform on one or all workspaces. Examples:
#   just provision plan all
#   just provision apply gxy-management
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
# Example: just bootstrap k3s--install gxy_management_k3s
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
#   just release gxy-management windmill   → helm + kustomize
#   just release gxy-cassiopeia caddy      → helm only
#   just release gxy-management artemis    → helm only
#   just release ops-backoffice-tools outline → kustomize only
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
        echo "Helm: install {{ app }} (chart: $CHART_NAME) from $REPO_URL"
        helm upgrade --install {{ app }} "$CHART_NAME" \
          --repo "$REPO_URL" \
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

# Mint per-site Cloudflare R2 credentials and register them as Woodpecker
# repo-scoped secrets via the Windmill flow at
# `f/static/provision_site_r2_credentials`. Idempotent — re-running rotates
# the token. T11 (sprint 2026-04-21) + D22 (Woodpecker repo-scope) +
# D33 amended ×2 + D40 (Woodpecker is sole persistence surface).
# Requires WINDMILL_REPO (defaults to ../fCC-U/windmill).
[group('configure')]
configure-constellation SITE="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "{{ SITE }}" ]; then
      echo "Usage: just configure-constellation <site>" >&2
      echo "  <site>: lowercase alphanumeric + hyphens, 1-32 chars" >&2
      exit 2
    fi
    WINDMILL_REPO="${WINDMILL_REPO:-../fCC-U/windmill}"
    if [ ! -d "${WINDMILL_REPO}/workspaces/platform" ]; then
      echo "Error: Windmill repo not found at ${WINDMILL_REPO}." >&2
      echo "Override with WINDMILL_REPO=/abs/path/to/windmill" >&2
      exit 1
    fi
    cd "${WINDMILL_REPO}/workspaces/platform"
    echo "Registering constellation {{ SITE }} via Windmill flow..."
    bunx wmill script run f/static/provision_site_r2_credentials \
      -d '{"site":"{{ SITE }}"}'

# Apply declarative Cloudflare Notifications from cloudflare/notifications.yaml.
# Use --dry-run to preview without writing.
[group('configure')]
configure-cf-notifications *args:
    scripts/cf-notifications-apply.sh {{ args }}

# Apply declarative Uptime Robot monitors from uptime-robot/monitors.yaml.
# Use --dry-run to preview without writing.
[group('configure')]
configure-uptime-robot *args:
    scripts/uptime-robot-apply.sh {{ args }}

# Trim aged journal entries from a field-notes file into
# `journal-archive/YYYY-MM.md` siblings. Default cutoff 30 days.
# Run from a clean working tree — emits a cross-repo diff in Universe.
[group('configure')]
configure-field-notes-trim area="infra" age="30":
    python3 scripts/trim-field-notes.py \
        ../Universe/spike/field-notes/{{area}}.md \
        --age-days {{age}}

# Verify encrypted secrets:
#   stage 1 — each `*.enc` decrypts with the operator's age key
#   stage 2 — path-layout contract per `docs/architecture/rfc-secrets-layout.md`
#             (universe-scope under `k3s/<gxy-*>/`, platform-wide under
#             `global/`, do-context creds under `do-*/`, per-app namespace
#             stubs at `<app>/.env.enc`; archive/legacy paths allowed)
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
        # Universe k3s clusters — RFC §"Cluster-local"
        k3s/gxy-management/*.values.yaml.enc|k3s/gxy-launchbase/*.values.yaml.enc|k3s/gxy-cassiopeia/*.values.yaml.enc) ;;
        k3s/gxy-management/*.secrets.env.enc|k3s/gxy-launchbase/*.secrets.env.enc|k3s/gxy-cassiopeia/*.secrets.env.enc) ;;
        k3s/gxy-management/*-backup.secrets.env.enc|k3s/gxy-launchbase/*-backup.secrets.env.enc|k3s/gxy-cassiopeia/*-backup.secrets.env.enc) ;;
        k3s/gxy-management/*.tls.crt.enc|k3s/gxy-management/*.tls.key.enc) ;;
        k3s/gxy-launchbase/*.tls.crt.enc|k3s/gxy-launchbase/*.tls.key.enc) ;;
        k3s/gxy-cassiopeia/*.tls.crt.enc|k3s/gxy-cassiopeia/*.tls.key.enc) ;;
        k3s/gxy-management/kubeconfig.yaml.enc|k3s/gxy-launchbase/kubeconfig.yaml.enc|k3s/gxy-cassiopeia/kubeconfig.yaml.enc) ;;
        # Platform-wide — RFC §"Two explicit scopes"
        global/.env.enc) ;;
        global/tls/*.crt.enc|global/tls/*.key.enc) ;;
        # DO contexts
        do-primary/.env.enc|do-universe/.env.enc) ;;
        # Per-app platform-wide namespace stubs / r2 reader
        windmill/.env.enc|outline/.env.enc|appsmith/.env.enc|r2-read/.env.enc) ;;
        # Pre-Universe artemis SoT (audit F42 — flagged for unification)
        management/artemis.env.enc) ;;
        # Legacy (retire post-Universe per RFC)
        archive/*|docker/oldeworld/*|k8s/o11y/*|k3s/ops-backoffice-tools/*) ;;
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

# Wait for a CNPG Cluster CR to become Ready, then surface health
# beyond Ready: instance/primary roll, replica streaming lag, WAL
# archive freshness, last successful barman backup age.
#
# Optional env (warn thresholds; exit code stays 0 unless wait fails):
#   BACKUP_WARN_HOURS    default 26 (1 day + 2h slack)
#   WAL_WARN_SECONDS     default 300 (5min)
[group('verify')]
verify-cnpg cluster namespace name timeout="5m":
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    : "${BACKUP_WARN_HOURS:=26}"
    : "${WAL_WARN_SECONDS:=300}"
    NS={{ namespace }}
    NAME={{ name }}

    echo "Waiting for CNPG Cluster ${NS}/${NAME} (timeout {{ timeout }})..."
    kubectl -n "$NS" wait --for=condition=Ready "cluster/${NAME}" --timeout={{ timeout }}

    echo "--- cluster summary ---"
    kubectl -n "$NS" get "cluster/${NAME}" \
      -o jsonpath='instances={.status.instances} readyInstances={.status.readyInstances} primary={.status.currentPrimary}{"\n"}'

    echo "--- pods ---"
    kubectl -n "$NS" get pods -l "cnpg.io/cluster=${NAME}" -o wide

    echo "--- last successful backup ---"
    LAST_BACKUP=$(kubectl -n "$NS" get "cluster/${NAME}" -o jsonpath='{.status.lastSuccessfulBackup}' 2>/dev/null || true)
    if [[ -z "$LAST_BACKUP" ]]; then
      echo "WARN: no lastSuccessfulBackup recorded yet"
    else
      LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${LAST_BACKUP%.*}Z" "+%s" 2>/dev/null || date -d "$LAST_BACKUP" "+%s" 2>/dev/null || echo 0)
      NOW_EPOCH=$(date "+%s")
      AGE_H=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))
      echo "lastSuccessfulBackup=$LAST_BACKUP (age ${AGE_H}h)"
      [[ "$AGE_H" -lt "$BACKUP_WARN_HOURS" ]] || echo "WARN: backup older than ${BACKUP_WARN_HOURS}h"
    fi

    echo "--- first recoverability point (PITR floor) ---"
    kubectl -n "$NS" get "cluster/${NAME}" -o jsonpath='{.status.firstRecoverabilityPoint}{"\n"}'

    PRIMARY=$(kubectl -n "$NS" get "cluster/${NAME}" -o jsonpath='{.status.currentPrimary}')
    if [[ -n "$PRIMARY" ]]; then
      echo "--- WAL archive freshness (primary=$PRIMARY) ---"
      kubectl -n "$NS" exec -c postgres "$PRIMARY" -- \
        psql -tA -U postgres -c "SELECT EXTRACT(EPOCH FROM (now() - last_archived_time))::int FROM pg_stat_archiver;" 2>/dev/null \
        | awk -v warn="$WAL_WARN_SECONDS" '{
            if ($1 == "") print "WARN: pg_stat_archiver returned no row";
            else if ($1+0 > warn) printf "WARN: last WAL archive %ss ago (>%ss)\n", $1, warn;
            else printf "OK: last WAL archive %ss ago\n", $1;
          }'

      echo "--- replica streaming lag (from primary) ---"
      kubectl -n "$NS" exec -c postgres "$PRIMARY" -- \
        psql -tA -U postgres -c "SELECT application_name, state, COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn)::text, 'n/a') AS bytes_lag FROM pg_stat_replication;" 2>/dev/null \
        | awk -F'|' 'NF>0 {printf "  %-20s state=%s lag_bytes=%s\n", $1, $2, $3}' \
        || echo "  (no replicas connected — single-instance cluster)"
    else
      echo "WARN: currentPrimary unset; skipping WAL + replica probes"
    fi

# Validate K8s manifests with kubeconform.
#
# Two stages:
#   1. raw manifests in k3s/ + k8s/ (kustomize bases, plain YAML) —
#      chart templates excluded because Go template syntax isn't YAML.
#   2. first-party chart templates rendered via `helm template` against
#      each chart's values.production.yaml + a stub set for the
#      sops-only required keys, then piped to kubeconform.
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
      k3s/ k8s/ || fail=1

    echo "=== stage 2: rendered chart templates ==="
    KC_ARGS=(
      -summary -output text -strict -ignore-missing-schemas
      -kubernetes-version "{{ version }}"
      -schema-location default
      -schema-location "{{ crds_schema }}"
    )
    for entry in \
      "gxy-management:artemis:--set,secretEnv.R2_ENDPOINT=x,--set,secretEnv.R2_ACCESS_KEY_ID=x,--set,secretEnv.R2_SECRET_ACCESS_KEY=x,--set,secretEnv.GH_CLIENT_ID=x,--set,secretEnv.JWT_SIGNING_KEY=x,--set,secretEnv.VALKEY_PASSWORD=x" \
      "gxy-management:valkey:--set,secretEnv.VALKEY_PASSWORD=x" \
      "gxy-cassiopeia:caddy:--set,r2.accessKeyId=x,--set,r2.secretAccessKey=y,--set,r2.bucket=z,--set,r2.endpoint=https://example" \
      ; do
      galaxy="${entry%%:*}"
      rest="${entry#*:}"
      app="${rest%%:*}"
      stubs="${rest#*:}"
      IFS=',' read -ra STUB_ARR <<<"$stubs"
      chart="k3s/${galaxy}/apps/${app}/charts/${app}"
      values="k3s/${galaxy}/apps/${app}/values.production.yaml"
      [[ -d "$chart" && -f "$values" ]] || { echo "skip ${galaxy}/${app} (chart or values absent)"; continue; }
      echo "--- ${galaxy}/${app} ---"
      if ! helm template "$app" "$chart" --values "$values" "${STUB_ARR[@]}" | kubeconform "${KC_ARGS[@]}"; then
        fail=1
      fi
    done
    exit "$fail"

# Verify an R2 bucket is provisioned correctly (exists, rw/ro keys work, ro
# cannot write). Reads credentials from
# infra-secrets/<bucket-cluster>/r2-{rw,ro}.env.enc via sops.
[group('verify')]
verify-r2 bucket:
    scripts/r2-bucket-verify.sh {{ bucket }}

# Artemis post-deploy E2E. Source of truth for E2E correctness lives in the
# artemis repo at `internal/integration/` (build-tagged Go suite, `make
# integration`). This recipe is a thin wrapper that points the suite at a
# deployed artemis. See `docs/runbooks/03-artemis-postdeploy-check.md`.
#
# Required env (or fall through to defaults):
#   ARTEMIS_URL    default https://uploads.freecode.camp
#   ARTEMIS_REPO   default $HOME/DEV/fCC/artemis
#   GH_TOKEN       default `gh auth token`
#   SITE           default test
#   ROOT_DOMAIN    default freecode.camp
[group('verify')]
verify-artemis:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${ARTEMIS_URL:=https://uploads.freecode.camp}"
    : "${ARTEMIS_REPO:=$HOME/DEV/fCC/artemis}"
    : "${SITE:=test}"
    : "${ROOT_DOMAIN:=freecode.camp}"
    GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"

    printf '[1/3] healthz %s/healthz\n' "$ARTEMIS_URL"
    if ! curl -fsS -o /dev/null --max-time 10 "$ARTEMIS_URL/healthz"; then
      printf 'FAIL: %s/healthz unreachable\n' "$ARTEMIS_URL" >&2
      exit 1
    fi

    if [[ -z "$GH_TOKEN" ]]; then
      printf 'FAIL: GH_TOKEN unset and `gh auth token` returned empty\n' >&2
      exit 2
    fi

    printf '[2/3] valkey-reach + jwt-mint — GET /api/sites + POST /api/deploy/init\n'
    # /api/sites hits the Valkey-backed registry; a 200 confirms artemis
    # holds a live read connection. JWT mint check follows so we surface
    # auth-side failure separately from Valkey-side failure.
    SITES_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
      -H "Authorization: Bearer ${GH_TOKEN}" "${ARTEMIS_URL}/api/sites")
    if [[ "$SITES_CODE" != "200" ]]; then
      printf 'FAIL: GET /api/sites returned %s (expected 200; Valkey reachable + staff team gated)\n' "$SITES_CODE" >&2
      exit 1
    fi
    JWT_BODY=$(curl -sS --max-time 10 \
      -H "Authorization: Bearer ${GH_TOKEN}" \
      -H 'content-type: application/json' \
      -d "{\"site\":\"${SITE}\"}" \
      "${ARTEMIS_URL}/api/deploy/init")
    if ! echo "$JWT_BODY" | grep -qE '"token"|"deployId"'; then
      printf 'FAIL: /api/deploy/init body lacked token/deployId — %s\n' "$JWT_BODY" >&2
      exit 1
    fi
    printf '  /api/sites=200; /api/deploy/init returned JWT envelope\n'

    if [[ ! -d "$ARTEMIS_REPO" ]]; then
      printf 'FAIL: ARTEMIS_REPO=%s not a directory\n' "$ARTEMIS_REPO" >&2
      exit 2
    fi

    printf '[3/3] artemis E2E — repo=%s url=%s site=%s\n' \
      "$ARTEMIS_REPO" "$ARTEMIS_URL" "$SITE"
    cd "$ARTEMIS_REPO"
    ARTEMIS_URL="$ARTEMIS_URL" GH_TOKEN="$GH_TOKEN" \
      SITE="$SITE" ROOT_DOMAIN="$ROOT_DOMAIN" \
      make integration

# Caddy cluster-side health on cassiopeia: chart pods 3/3, Gateway +
# HTTPRoute programmed, e2e curl against a probe site.
#
# Optional env:
#   PROBE_SITE     default test
#   ROOT_DOMAIN    default freecode.camp
[group('verify')]
verify-caddy cluster="gxy-cassiopeia":
    #!/usr/bin/env bash
    set -euo pipefail
    : "${PROBE_SITE:=test}"
    : "${ROOT_DOMAIN:=freecode.camp}"
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"

    printf '[1/4] caddy pods in caddy ns\n'
    READY=$(kubectl -n caddy get pods -l app.kubernetes.io/name=caddy \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' | grep -c true || true)
    TOTAL=$(kubectl -n caddy get pods -l app.kubernetes.io/name=caddy --no-headers | wc -l | tr -d ' ')
    printf '    ready=%s total=%s\n' "$READY" "$TOTAL"
    [[ "$READY" -ge 1 && "$READY" -eq "$TOTAL" ]] || { echo "FAIL: caddy pods not all Ready"; exit 1; }

    printf '[2/4] gateway caddy-gateway Programmed\n'
    GW=$(kubectl -n caddy get gateway caddy-gateway \
      -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')
    [[ "$GW" == "True" ]] || { echo "FAIL: Gateway Programmed=$GW"; exit 1; }

    printf '[3/4] httproute caddy Accepted + ResolvedRefs\n'
    ACC=$(kubectl -n caddy get httproute caddy \
      -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}')
    RES=$(kubectl -n caddy get httproute caddy \
      -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}')
    [[ "$ACC" == "True" && "$RES" == "True" ]] || { echo "FAIL: HTTPRoute Accepted=$ACC ResolvedRefs=$RES"; exit 1; }

    URL="https://${PROBE_SITE}.${ROOT_DOMAIN}/"
    printf '[4/4] e2e %s\n' "$URL"
    HTTP=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 10 "$URL") || true
    [[ "$HTTP" == "200" ]] || { echo "FAIL: $URL returned $HTTP (expected 200)"; exit 1; }

    echo "OK: caddy chart healthy on {{ cluster }}; ${URL} → 200"

# Verify the locally-built caddy-s3 image lists both in-tree modules AND does
# NOT list the third-party caddy.fs.s3 (D32 — no third-party Caddy plugins).
# Runs the image under emulation since the host is usually arm64.
[group('verify')]
verify-caddy-s3:
    #!/usr/bin/env bash
    set -euo pipefail
    TAG="dev-$(git rev-parse --short HEAD)"
    IMG="ghcr.io/freecodecamp/caddy-s3:${TAG}"
    MODULES=$(docker run --rm --platform linux/amd64 "${IMG}" caddy list-modules)
    echo "${MODULES}" | grep -q '^http.handlers.r2_alias$' || { echo "FAIL: http.handlers.r2_alias not listed"; exit 1; }
    echo "${MODULES}" | grep -q '^caddy.fs.r2$' || { echo "FAIL: caddy.fs.r2 not listed"; exit 1; }
    ! echo "${MODULES}" | grep -q '^caddy.fs.s3$' || { echo "FAIL: caddy.fs.s3 present (D32 violated)"; exit 1; }
    echo "OK: http.handlers.r2_alias + caddy.fs.r2 present; caddy.fs.s3 absent"

# k6 load test — pick a scenario from `loadtest/scenarios/`.
#
# Scenarios:
#   caddy-serve         high-RPS GET against served production site
#   caddy-serve-preview high-RPS GET against preview alias
#   artemis-whoami      moderate-RPS GH-bearer probe of /api/whoami
#   artemis-deploy      sustained init+upload+finalize bursts (write-heavy)
#
# Required env: see `loadtest/README.md` per scenario.
[group('test')]
test-loadtest scenario:
    #!/usr/bin/env bash
    set -euo pipefail
    SCRIPT="loadtest/scenarios/{{ scenario }}.js"
    if [[ ! -f "$SCRIPT" ]]; then
      printf 'FAIL: scenario %s not found at %s\n' '{{ scenario }}' "$SCRIPT" >&2
      printf 'available:\n' >&2
      ls loadtest/scenarios/*.js 2>/dev/null | sed 's|loadtest/scenarios/||;s|\.js||;s|^|  |' >&2
      exit 2
    fi
    if ! command -v k6 >/dev/null 2>&1; then
      printf 'FAIL: k6 not on PATH (brew install k6)\n' >&2
      exit 2
    fi
    k6 run "$SCRIPT"

# Static contract test for `configure-constellation` recipe.
[group('test')]
test-constellation:
    bash scripts/tests/constellation-register.sh

# Round-trip verification for the windmill backup pipeline. Lists the
# newest S3 object under `windmill/<cluster>/`, downloads it to a temp
# file, asserts the gzip is well-formed and ends with the postgres
# `cluster dump complete` sentinel. Does NOT restore — that path lives
# in `docs/runbooks/06-windmill-pg-backup.md`.
[group('test')]
test-windmill-backup-restore cluster="gxy-management":
    #!/usr/bin/env bash
    set -euo pipefail
    S3_ENV="{{ secrets_dir }}/k3s/{{ cluster }}/windmill-backup.secrets.env.enc"
    [ -f "$S3_ENV" ] || { echo "FAIL: missing $S3_ENV"; exit 1; }
    set -a
    source <(sops -d --input-type dotenv --output-type dotenv "$S3_ENV")
    set +a
    PREFIX="windmill/{{ cluster }}"
    NEWEST=$(AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
      aws s3 ls "s3://${S3_BUCKET}/${PREFIX}/" --endpoint-url "$S3_ENDPOINT" \
      | awk '$4 ~ /\.sql\.gz$/ {print $4}' | sort | tail -1)
    [ -n "$NEWEST" ] || { echo "FAIL: no .sql.gz under s3://${S3_BUCKET}/${PREFIX}/"; exit 1; }
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    DEST="${TMP}/${NEWEST}"
    echo "Downloading s3://${S3_BUCKET}/${PREFIX}/${NEWEST}"
    AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
      aws s3 cp "s3://${S3_BUCKET}/${PREFIX}/${NEWEST}" "$DEST" \
      --endpoint-url "$S3_ENDPOINT" --only-show-errors
    SIZE=$(stat -f%z "$DEST" 2>/dev/null || stat -c%s "$DEST")
    [ "$SIZE" -gt 100 ] || { echo "FAIL: backup too small ($SIZE bytes)"; exit 1; }
    gunzip -t "$DEST" || { echo "FAIL: gunzip integrity check"; exit 1; }
    gunzip -c "$DEST" | tail -1 \
      | grep -q 'PostgreSQL database cluster dump complete' \
      || { echo "FAIL: completion sentinel missing"; exit 1; }
    echo "OK: ${NEWEST} (${SIZE} bytes) gunzip-clean + sentinel present"

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
        ../Universe/spike/field-notes/{{area}}.md --list

# Dry-run: show which dated journal entries would be archived by
# `configure-field-notes-trim`. Default cutoff 30 days. Override with `age=N`.
[group('inspect')]
inspect-field-notes-trim area="infra" age="30":
    python3 scripts/trim-field-notes.py \
        ../Universe/spike/field-notes/{{area}}.md \
        --age-days {{age}} --dry-run

# Windmill backup CronJob health on gxy-management: schedule, last
# successful run, recent job pods, local `.backups/` artefact list.
# Operator-runnable read-only probe — never triggers a new backup.
[group('inspect')]
inspect-windmill-backup cluster="gxy-management":
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    NS=windmill
    CJ=windmill-backup
    echo "=== {{ cluster }} / ${NS}/${CJ} ==="
    echo "--- cronjob ---"
    kubectl -n "$NS" get cronjob "$CJ" -o wide 2>&1 || { echo "(not found — CronJob absent)"; exit 1; }
    echo "--- schedule + last run ---"
    kubectl -n "$NS" get cronjob "$CJ" \
      -o jsonpath='schedule={.spec.schedule}{"\n"}lastSchedule={.status.lastScheduleTime}{"\n"}lastSuccessful={.status.lastSuccessfulTime}{"\n"}'
    echo "--- recent job pods (latest 5) ---"
    kubectl -n "$NS" get pods -l job-name --sort-by=.status.startTime 2>&1 | tail -6 || true
    echo "--- local .backups/ ---"
    if [ -d .backups ]; then
      ls -lh .backups 2>/dev/null | tail -10 || echo "(empty)"
    else
      echo "(no .backups/ dir in $(pwd))"
    fi

# Ad-hoc Windmill PostgreSQL backup (local file).
#
# Dumps pg_dumpall INSIDE the pod to a temp file (so the dump finishes
# before we pull it) and only then copies it down via `kubectl cp`. This
# avoids a known failure mode where a streaming `kubectl exec ... | gzip
# > file.sql.gz` silently truncates mid-dump if the exec connection is
# interrupted — the gzip closes cleanly, the file looks fine, but the
# trailing DDL (triggers, ACLs) is missing. Seen during the 2026-04-22
# gxy-mgmt rename dogfood. Always validate with the "PostgreSQL database
# cluster dump complete" sentinel before trusting the artefact.
[group('backup')]
backup-windmill cluster:
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    mkdir -p .backups
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    FILENAME="windmill-${TIMESTAMP}.sql.gz"
    PG_POD=$(kubectl get pod -n windmill -l app=windmill-postgresql-demo-app -o jsonpath='{.items[0].metadata.name}')
    [ -n "${PG_POD}" ] || { echo "Error: no PostgreSQL pod found in windmill namespace"; exit 1; }
    echo "Backing up Windmill PostgreSQL from ${PG_POD}..."
    REMOTE="/tmp/${FILENAME}"
    kubectl exec -n windmill "${PG_POD}" -- bash -c "PGPASSWORD=\"\${POSTGRES_PASSWORD}\" pg_dumpall -U postgres --clean --if-exists | gzip > ${REMOTE}"
    kubectl exec -n windmill "${PG_POD}" -- bash -c "gunzip -c ${REMOTE} | tail -1" | grep -q 'PostgreSQL database cluster dump complete' \
      || { echo "Error: in-pod dump missing completion sentinel — aborting"; exit 1; }
    kubectl cp "windmill/${PG_POD}:${REMOTE}" ".backups/${FILENAME}"
    kubectl exec -n windmill "${PG_POD}" -- rm -f "${REMOTE}"
    FILESIZE=$(stat -f%z ".backups/${FILENAME}" 2>/dev/null || stat -c%s ".backups/${FILENAME}")
    [ "${FILESIZE}" -gt 100 ] || { echo "Error: backup file too small (${FILESIZE} bytes) — likely empty dump"; exit 1; }
    gunzip -c ".backups/${FILENAME}" | tail -1 | grep -q 'PostgreSQL database cluster dump complete' \
      || { echo "Error: copied backup missing completion sentinel — aborting"; rm -f ".backups/${FILENAME}"; exit 1; }
    echo "Saved: .backups/${FILENAME} (${FILESIZE} bytes)"

    # Upload to the same S3 prefix the nightly CronJob targets so an
    # ad-hoc operator dump is recoverable through the same restore path
    # documented in `docs/runbooks/06-windmill-pg-backup.md`. Creds come
    # from the same sops envelope the chart's secretGenerator consumes.
    S3_ENV="{{ secrets_dir }}/k3s/{{ cluster }}/windmill-backup.secrets.env.enc"
    if [ -f "$S3_ENV" ]; then
      echo "Uploading to S3 (mirroring CronJob path)..."
      set -a
      source <(sops -d --input-type dotenv --output-type dotenv "$S3_ENV")
      set +a
      S3_PATH="windmill/{{ cluster }}/${FILENAME}"
      AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
        aws s3 cp ".backups/${FILENAME}" "s3://${S3_BUCKET}/${S3_PATH}" \
        --endpoint-url "$S3_ENDPOINT"
      AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
        aws s3 ls "s3://${S3_BUCKET}/${S3_PATH}" --endpoint-url "$S3_ENDPOINT" \
        | grep -q "${FILENAME}" \
        || { echo "Error: S3 head-list did not surface the uploaded object"; exit 1; }
      echo "Uploaded: s3://${S3_BUCKET}/${S3_PATH}"
    else
      echo "WARN: ${S3_ENV} not found — local-only backup (CronJob path NOT mirrored)"
    fi

# Ad-hoc Valkey snapshot (local file). Triggers BGSAVE in the pod,
# polls LASTSAVE until the timestamp advances, then `kubectl cp`s the
# resulting `dump.rdb` out to `.backups/valkey-<timestamp>.rdb`.
#
# BGSAVE is non-blocking but fork-heavy; on a single-replica AOF-on
# Valkey this is the safest operator-runnable snapshot. For nightly
# RDB→R2 mirror see the chart (T18) — this recipe is the manual
# escape hatch.
[group('backup')]
backup-valkey cluster="gxy-management":
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    mkdir -p .backups
    NS=valkey
    POD=$(kubectl -n "$NS" get pod -l app.kubernetes.io/name=valkey -o jsonpath='{.items[0].metadata.name}')
    [ -n "$POD" ] || { echo "Error: no valkey pod in $NS namespace"; exit 1; }
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    FILENAME="valkey-${TIMESTAMP}.rdb"

    BEFORE=$(kubectl exec -n "$NS" "$POD" -- valkey-cli LASTSAVE | tr -d '[:space:]')
    echo "Triggering BGSAVE on ${POD} (lastsave=${BEFORE})..."
    kubectl exec -n "$NS" "$POD" -- valkey-cli BGSAVE >/dev/null

    for i in $(seq 1 30); do
      sleep 2
      NOW=$(kubectl exec -n "$NS" "$POD" -- valkey-cli LASTSAVE | tr -d '[:space:]')
      if [ "$NOW" != "$BEFORE" ]; then
        echo "BGSAVE complete (lastsave=${NOW}, ${i} polls)"
        break
      fi
    done
    [ "$NOW" != "$BEFORE" ] || { echo "Error: BGSAVE LASTSAVE did not advance after 60s"; exit 1; }

    kubectl cp "${NS}/${POD}:/data/dump.rdb" ".backups/${FILENAME}"
    FILESIZE=$(stat -f%z ".backups/${FILENAME}" 2>/dev/null || stat -c%s ".backups/${FILENAME}")
    [ "${FILESIZE}" -gt 100 ] || { echo "Error: snapshot too small (${FILESIZE} bytes)"; rm -f ".backups/${FILENAME}"; exit 1; }
    echo "Saved: .backups/${FILENAME} (${FILESIZE} bytes)"

# Build the caddy-s3 image locally and tag with dev-<sha>. Platform pinned to
# linux/amd64 — DO droplets run on AMD64, and buildx defaults to the host
# architecture (arm64 on Apple Silicon → exec format error in cluster).
# GitHub Actions (`.github/workflows/docker--caddy-s3.yml`) builds the
# canonical `ghcr.io/freecodecamp/caddy-s3:{sha}` tag on push (build-
# residency principle: platform pillars build outside Universe).
[group('build')]
build-caddy-s3:
    #!/usr/bin/env bash
    set -euo pipefail
    TAG="dev-$(git rev-parse --short HEAD)"
    docker buildx build \
        --platform linux/amd64 \
        --load \
        -t "ghcr.io/freecodecamp/caddy-s3:${TAG}" \
        docker/images/caddy-s3/
    echo "Built: ghcr.io/freecodecamp/caddy-s3:${TAG} (linux/amd64)"

# Build the postgres-awscli image locally (postgres:18-bookworm + baked
# awscli for the windmill backup CronJob). GitHub Actions
# (`.github/workflows/docker--postgres-awscli.yml`) builds the canonical
# `ghcr.io/freecodecamp/postgres-awscli:{sha}` tag on workflow_dispatch.
[group('build')]
build-postgres-awscli:
    #!/usr/bin/env bash
    set -euo pipefail
    TAG="dev-$(git rev-parse --short HEAD)"
    docker buildx build \
        --platform linux/amd64 \
        --load \
        -t "ghcr.io/freecodecamp/postgres-awscli:${TAG}" \
        docker/images/postgres-awscli/
    echo "Built: ghcr.io/freecodecamp/postgres-awscli:${TAG} (linux/amd64)"

# Reset a CNPG Cluster: delete the CR, all PVCs, and pods. DESTRUCTIVE.
# After reset, re-run `just release {{cluster}} {{app}}` to recreate.
[group('destroy')]
destroy-cnpg cluster namespace name:
    #!/usr/bin/env bash
    set -eu
    cd k3s/{{ cluster }}
    export KUBECONFIG="$(pwd)/.kubeconfig.yaml"
    echo "Deleting CNPG Cluster {{ namespace }}/{{ name }} ..."
    kubectl -n {{ namespace }} delete cluster/{{ name }} --ignore-not-found
    echo "Waiting for cluster pods to terminate ..."
    kubectl -n {{ namespace }} wait --for=delete pod -l cnpg.io/cluster={{ name }} --timeout=120s 2>/dev/null || true
    echo "Deleting PVCs for {{ name }} ..."
    kubectl -n {{ namespace }} delete pvc -l cnpg.io/cluster={{ name }} --ignore-not-found
    kubectl -n {{ namespace }} get pvc -o name | grep -E "{{ name }}-[0-9]+$" | xargs -r kubectl -n {{ namespace }} delete --ignore-not-found
    echo 'Done. Re-run "just release {{ cluster }} <app>" to recreate.'

# Tear down a Universe galaxy: runs the k3s--teardown playbook, optionally
# deletes droplets via doctl. Preserves shared infra (VPC, firewall, R2).
# DESTRUCTIVE — operator-fired only.
#
# Galaxy slug → inventory group via `tr '-' '_' + _k3s` suffix:
#   gxy-management → gxy_management_k3s
#
# Set `delete_droplets=true` to also `doctl compute droplet delete --tag-name`.
# Idempotent: re-runnable if first attempt aborts mid-stream.
[group('destroy')]
destroy-galaxy galaxy delete_droplets="false":
    #!/usr/bin/env bash
    set -euo pipefail
    GALAXY="{{ galaxy }}"
    case "$GALAXY" in
      gxy-management|gxy-launchbase|gxy-cassiopeia) ;;
      *) echo "Refusing: unknown galaxy '$GALAXY' (expected one of gxy-{management,launchbase,cassiopeia})"; exit 1 ;;
    esac
    INVENTORY_GROUP=$(echo "$GALAXY" | tr '-' '_')_k3s

    echo "==> k3s teardown via ansible: $INVENTORY_GROUP"
    just bootstrap k3s--teardown "$INVENTORY_GROUP"

    if [[ "{{ delete_droplets }}" == "true" ]]; then
      DROPLET_TAG="${GALAXY}-k3s"
      echo "==> doctl compute droplet delete --tag-name $DROPLET_TAG --force"
      doctl compute droplet delete --tag-name "$DROPLET_TAG" --force
    else
      echo "==> Skipping droplet delete (pass delete_droplets=true to remove DO droplets)"
    fi

    echo "Done. Shared infra (VPC, firewall, R2) preserved."
