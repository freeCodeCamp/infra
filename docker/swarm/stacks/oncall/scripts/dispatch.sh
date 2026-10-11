#!/bin/sh
set -eu

. "$(dirname "$0")/lib.sh"

target="${DISPATCH_REPO:-?} ${DISPATCH_WORKFLOW:-?}"
runs="https://github.com/${DISPATCH_REPO:-}/actions/workflows/${DISPATCH_WORKFLOW:-}"

config_error() {
  chat_notify fail dispatch "$target" "misconfigured: $1"
  printf 'dispatch: %s\n' "$1" >&2
  exit 2
}

for var in GITHUB_DISPATCH_TOKEN DISPATCH_REPO DISPATCH_WORKFLOW; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || config_error "$var is not set, nothing was started"
done

now=${DISPATCH_NOW:-$(date -u +%s)}
ref=${DISPATCH_REF:-main}
api=${GITHUB_API_URL:-https://api.github.com}
body=$(mktemp)
trap 'rm -f "$body"' EXIT

warn_if_last_run_bad() {
  code=$(curl -s -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer $GITHUB_DISPATCH_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    --max-time 30 \
    "$api/repos/$DISPATCH_REPO/actions/workflows/$DISPATCH_WORKFLOW/runs?branch=${ref#refs/heads/}&status=completed&per_page=1" ||
    true)
  [ "$code" = 200 ] || return 0
  last=$(grep -o '"conclusion": *"[a-z_]*"' "$body" | head -n 1 | sed 's/.*"\([a-z_]*\)"$/\1/')
  case "$last" in
  failure | cancelled | timed_out | startup_failure) ;;
  *) return 0 ;;
  esac
  link=$(grep -o '"html_url": *"[^"]*"' "$body" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
  chat_notify warn dispatch "$target" \
    "skipped: inside the maintenance window, the last run is $last" "${link:-$runs}" "last run"
}

case "${WINDOW_POLICY:-none}" in
avoid)
  if in_window "$now"; then
    printf 'dispatch: skip %s, inside the maintenance window\n' "$target"
    in_window "$now" 3 && warn_if_last_run_bad
    exit 0
  fi
  ;;
require)
  if ! in_window "$now"; then
    chat_notify warn dispatch "$target" \
      "refused: outside the maintenance window (Wed/Sat 00:00-06:00 UTC), nothing was started" \
      "$runs" runs
    printf 'dispatch: refused %s, outside the maintenance window\n' "$target" >&2
    exit 1
  fi
  ;;
none) ;;
*) config_error "WINDOW_POLICY must be avoid, require or none, got '${WINDOW_POLICY}'" ;;
esac

code=$(curl -s -o "$body" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $GITHUB_DISPATCH_TOKEN" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --max-time 30 \
  -d "{\"ref\":$(json_string "$ref")}" \
  "$api/repos/$DISPATCH_REPO/actions/workflows/$DISPATCH_WORKFLOW/dispatches" || true)

case "$code" in
2??)
  printf 'dispatch: %s accepted (HTTP %s)\n' "$target" "$code"
  exit 0
  ;;
esac

chat_notify fail dispatch "$target" \
  "failed: HTTP ${code:-000} $(ascii_excerpt "$body" 200)" "$runs" runs
printf 'dispatch: %s failed (HTTP %s)\n' "$target" "${code:-000}" >&2
exit 1
