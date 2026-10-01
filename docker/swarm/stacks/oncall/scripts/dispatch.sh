#!/bin/sh
set -eu

. "$(dirname "$0")/lib.sh"

target="${DISPATCH_REPO:-?} ${DISPATCH_WORKFLOW:-?}"

config_error() {
  chat_post "🔴 dispatch misconfigured · $target
$1"
  printf 'dispatch: %s\n' "$1" >&2
  exit 2
}

for var in GITHUB_DISPATCH_TOKEN DISPATCH_REPO DISPATCH_WORKFLOW; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || config_error "$var is not set, nothing was started"
done

now=${DISPATCH_NOW:-$(date -u +%s)}

case "${WINDOW_POLICY:-none}" in
avoid)
  if in_window "$now"; then
    printf 'dispatch: skip %s, inside the maintenance window\n' "$target"
    exit 0
  fi
  ;;
require)
  if ! in_window "$now"; then
    chat_post "⚠️ dispatch refused · $target
outside the maintenance window (Wed/Sat 00:00-06:00 UTC), nothing was started"
    printf 'dispatch: refused %s, outside the maintenance window\n' "$target" >&2
    exit 1
  fi
  ;;
none) ;;
*) config_error "WINDOW_POLICY must be avoid, require or none, got '${WINDOW_POLICY}'" ;;
esac

api=${GITHUB_API_URL:-https://api.github.com}
body=$(mktemp)
trap 'rm -f "$body"' EXIT
code=$(curl -s -o "$body" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $GITHUB_DISPATCH_TOKEN" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  --max-time 30 \
  -d "{\"ref\":$(json_string "${DISPATCH_REF:-main}")}" \
  "$api/repos/$DISPATCH_REPO/actions/workflows/$DISPATCH_WORKFLOW/dispatches" || true)

case "$code" in
2??)
  printf 'dispatch: %s accepted (HTTP %s)\n' "$target" "$code"
  exit 0
  ;;
esac

chat_post "🔴 dispatch failed · $target · HTTP ${code:-000}
$(ascii_excerpt "$body" 300)"
printf 'dispatch: %s failed (HTTP %s)\n' "$target" "${code:-000}" >&2
exit 1
