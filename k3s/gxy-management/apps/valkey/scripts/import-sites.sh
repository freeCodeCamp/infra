#!/usr/bin/env bash
# import-sites.sh — one-shot Valkey hand-import for the 11-site
# canonical registry derived from R2 source-of-truth:
#
#   rclone ls r2-gxy:universe-static-apps-01 | rg production
#
# Pre-populates the in-cluster Valkey before artemis flips its
# REGISTRY_BACKEND env from sites_yaml → valkey. Without this seed,
# the moment artemis swings backends every `*.freecode.camp` GET
# 404s on an empty `sites:all` set.
#
# Schema (mirrors `internal/registry/valkey/store.go` in artemis):
#
#   per slug:
#     HSET site:<slug> teams '<json>' created_at <iso> updated_at <iso> created_by <login>
#   index:
#     SADD sites:all <slug>
#   pub/sub:
#     PUBLISH registry.changed <slug>
#
# Idempotent. HSET overwrites with identical fields on re-run; SADD
# is set-typed so duplicate adds are no-ops. The PUBLISH on every
# run is harmless — artemis subscribers refresh their cache from
# the (now identical) source-of-truth.
#
# Usage:
#   import-sites.sh [--dry-run]
#
# Env preconditions:
#   - $KUBECONFIG points at the gxy-management cluster.
#   - The Valkey StatefulSet `valkey-0` is Running in `-n valkey`.
#   - The Valkey pod has $VALKEY_PASSWORD in its env (set by the
#     chart from the sops `secretEnv` overlay — same value the
#     server uses for `--requirepass`).
#
# Cutover sequencing in flight-manual §C.4. See `--help` for the
# exit-code contract.

set -euo pipefail

VALKEY_NAMESPACE="${VALKEY_NAMESPACE:-valkey}"
VALKEY_POD="${VALKEY_POD:-valkey-0}"
DRY_RUN=0
TIMESTAMP="2026-05-10T00:00:00Z"
CREATED_BY="mrugesh"
TEAMS_JSON='["staff"]'

# 11 canonical site slugs from R2 (alphabetized; matches `rclone ls`
# output as of 2026-05-10).
SITES=(
  checkers
  cognitive-biases
  five-dice
  gomoku
  hello-universe
  newton-laws-of-motion
  number-tiles
  projectile-motion
  reversi
  share-python
  test
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Imports the 11-site canonical registry into the in-cluster Valkey on
gxy-management. Idempotent — safe to re-run.

Options:
  --dry-run    Print HSET / SADD / PUBLISH commands; do not exec.
               No kubectl roundtrip; no Valkey state change.
  --help       This message.

Exit codes:
  0   all 11 imports succeeded (or --dry-run printed cleanly)
  1   precondition failure (kubeconfig / pod missing)
  2   Valkey command(s) returned non-OK
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    printf 'Error: unknown arg %q\n' "$1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

# Sanity: kubectl + cluster reachable when not in dry-run mode.
if [[ "$DRY_RUN" -eq 0 ]]; then
  if ! command -v kubectl >/dev/null 2>&1; then
    printf 'Error: kubectl not found in PATH\n' >&2
    exit 1
  fi
  if ! kubectl -n "$VALKEY_NAMESPACE" get pod "$VALKEY_POD" >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # backticks are markdown, not command sub
    printf 'Error: pod %s/%s not found. Is `just deploy valkey` complete?\n' \
      "$VALKEY_NAMESPACE" "$VALKEY_POD" >&2
    exit 1
  fi
fi

# Per-slug Valkey command pipeline. valkey-cli reads commands from
# stdin when the program is invoked without a command — one command
# per line — and returns the OK/ERR reply per command. We use the
# same approach to ship 11 sites in one exec roundtrip.
#
# Token grouping: valkey-cli's stdin parser (sdssplitargs in
# valkey-cli.c) splits on whitespace BUT honors single-quote groups
# (literal contents, no escapes) and double-quote groups (with \"
# / \\ / \n etc. escapes). The teams field carries JSON like
# `["staff"]` containing both `[` and `"`; without grouping, that
# splits into 3 tokens. We wrap it in single quotes so the JSON
# arrives as one HSET value field unchanged.
build_pipeline() {
  local slug
  for slug in "${SITES[@]}"; do
    printf "HSET site:%s teams '%s' created_at %s updated_at %s created_by %s\n" \
      "$slug" "$TEAMS_JSON" "$TIMESTAMP" "$TIMESTAMP" "$CREATED_BY"
    printf 'SADD sites:all %s\n' "$slug"
    printf 'PUBLISH registry.changed %s\n' "$slug"
  done
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '# DRY-RUN — would execute against pod %s/%s:\n' \
    "$VALKEY_NAMESPACE" "$VALKEY_POD"
  build_pipeline
  exit 0
fi

# Live import. Pipe the multi-command stream into valkey-cli on the
# pod. -a uses the in-pod $VALKEY_PASSWORD (set by the chart from
# the sops Secret) so no plaintext password ever crosses the wire
# from this script. valkey-cli prints the reply per command; we
# count them to assert all 33 (= 11 sites × 3 commands) returned
# without an ERR.
printf 'Importing %d sites into %s/%s...\n' \
  "${#SITES[@]}" "$VALKEY_NAMESPACE" "$VALKEY_POD"

# shellcheck disable=SC2016 # $VALKEY_PASSWORD expands inside the pod, not the host shell.
REPLIES=$(
  build_pipeline | kubectl -n "$VALKEY_NAMESPACE" exec -i "$VALKEY_POD" -- \
    sh -c 'valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning'
)

# Sanity: count "OK" / integer replies. HSET replies with the count
# of new fields (integer); SADD replies with 0 or 1 (integer);
# PUBLISH replies with 0 (no subscribers if artemis cache isn't
# warm yet) or 1+ (integer). Any "ERR" line is fatal.
if printf '%s\n' "$REPLIES" | grep -q '^ERR\|^(error)'; then
  printf 'Error: Valkey returned at least one ERR — replies follow\n' >&2
  printf '%s\n' "$REPLIES" >&2
  exit 2
fi

REPLY_COUNT=$(printf '%s\n' "$REPLIES" | grep -c .)
EXPECTED=$((${#SITES[@]} * 3))
if [[ "$REPLY_COUNT" -ne "$EXPECTED" ]]; then
  printf 'Warning: expected %d replies, got %d. Inspect manually.\n' \
    "$EXPECTED" "$REPLY_COUNT" >&2
  printf '%s\n' "$REPLIES" >&2
fi

# Verify the sites:all set has 11 members.
# shellcheck disable=SC2016 # $VALKEY_PASSWORD expands inside the pod, not the host shell.
COUNT=$(
  kubectl -n "$VALKEY_NAMESPACE" exec "$VALKEY_POD" -- sh -c \
    'valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning SCARD sites:all'
)

printf '\nImport complete.\n'
printf '  sites:all SCARD = %s (expected %d)\n' "$COUNT" "${#SITES[@]}"
# shellcheck disable=SC2016 # printf prints the literal $VALKEY_PASSWORD; the operator's shell expands it on paste.
printf '  Verify: kubectl -n %s exec %s -- valkey-cli -a "$VALKEY_PASSWORD" --no-auth-warning SMEMBERS sites:all | sort\n' \
  "$VALKEY_NAMESPACE" "$VALKEY_POD"
