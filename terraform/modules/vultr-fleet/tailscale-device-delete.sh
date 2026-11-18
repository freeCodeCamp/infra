#!/usr/bin/env bash
set -euo pipefail

# https://tailscale.com/docs/features/oauth-clients
# https://api.tailscale.com/api/v2?outputOpenapiSchema=true

host=${1:?usage: tailscale-device-delete.sh <hostname>}
: "${TAILSCALE_DEVICES_OAUTH_CLIENT_ID:?TAILSCALE_DEVICES_OAUTH_CLIENT_ID is not set}"
: "${TAILSCALE_DEVICES_OAUTH_CLIENT_SECRET:?TAILSCALE_DEVICES_OAUTH_CLIENT_SECRET is not set}"

api=https://api.tailscale.com/api/v2
tag=tag:added-by-ops

token=$(printf 'client_id=%s&client_secret=%s' \
  "$TAILSCALE_DEVICES_OAUTH_CLIENT_ID" "$TAILSCALE_DEVICES_OAUTH_CLIENT_SECRET" |
  curl -fsS --data-binary @- "$api/oauth/token" | jq -er '.access_token')

auth() {
  printf 'Authorization: Bearer %s\n' "$token"
}

ids=$(auth | curl -fsS -H @- "$api/tailnet/-/devices?tags=$tag" |
  jq -r --arg h "$host" '
    .devices[]
    | select(.hostname == $h
        or ((.name | split(".")[0]) | test("^" + $h + "(-[0-9]+)?$")))
    | "\(.nodeId) \(.name)"')

if [ -z "$ids" ]; then
  printf 'tailscale: no %s device for %s\n' "$tag" "$host"
  exit 0
fi

while read -r id name; do
  code=$(auth | curl -sS -o /dev/null -w '%{http_code}' -X DELETE -H @- "$api/device/$id")
  case $code in
  200) printf 'tailscale: deleted %s %s (200)\n' "$id" "$name" ;;
  404) printf 'tailscale: already gone %s %s (404)\n' "$id" "$name" ;;
  *)
    printf 'tailscale: delete %s %s failed: HTTP %s\n' "$id" "$name" "$code" >&2
    exit 1
    ;;
  esac
done <<<"$ids"
