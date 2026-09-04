#!/usr/bin/env bash
set -euo pipefail

: "${TAILSCALE_OAUTH_CLIENT_ID:?TAILSCALE_OAUTH_CLIENT_ID not set}"
: "${TAILSCALE_OAUTH_CLIENT_SECRET:?TAILSCALE_OAUTH_CLIENT_SECRET not set}"

printf 'client_id=%s&client_secret=%s' "${TAILSCALE_OAUTH_CLIENT_ID}" "${TAILSCALE_OAUTH_CLIENT_SECRET}" |
  curl -sS -f https://api.tailscale.com/api/v2/oauth/token --data-binary @- |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
