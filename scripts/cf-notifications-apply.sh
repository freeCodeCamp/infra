#!/usr/bin/env bash
# scripts/cf-notifications-apply.sh — T24 apply declarative CF Notifications
#
# Reads cloudflare/notifications.yaml and applies to the freeCodeCamp-Universe
# Cloudflare account via the CF API.
#
# Usage:
#   just cf-notifications-apply              # apply
#   just cf-notifications-apply --dry-run    # show intended diff, no writes
#
# Requires: curl, jq, yq (v4), sops+age.
# Credentials: infra-secrets/cloudflare/api.env.enc
#   CF_API_TOKEN   (Zone Alerts:Edit scope)
#   CF_ACCOUNT_ID

set -euo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

CONFIG="${CONFIG:-cloudflare/notifications.yaml}"
SECRETS_DIR="${SECRETS_DIR:-$(git rev-parse --show-toplevel)/../infra-secrets}"
SECRET_ENC="$SECRETS_DIR/cloudflare/api.env.enc"

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
err() { printf '%s[ERR]%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }
ok()  { printf '%s[OK]%s %s\n' "$GRN" "$RST" "$1"; }
warn(){ printf '%s[WARN]%s %s\n' "$YLW" "$RST" "$1"; }

for cmd in curl jq yq sops; do
  command -v "$cmd" >/dev/null 2>&1 || err "missing dependency: $cmd"
done

[ -f "$CONFIG" ]     || err "config not found: $CONFIG"
[ -f "$SECRET_ENC" ] || err "secret not found: $SECRET_ENC"

eval "$(sops -d --input-type dotenv --output-type dotenv "$SECRET_ENC")"
: "${CF_API_TOKEN:?CF_API_TOKEN missing}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID missing}"

CF_API="https://api.cloudflare.com/client/v4"
AUTH=(-H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

# ---------------------------------------------------------------------------
# Resolve destination names to IDs
# ---------------------------------------------------------------------------
ok "fetching Notification Destinations for account $CF_ACCOUNT_ID"
DESTINATIONS=$(curl -s "${AUTH[@]}" \
  "$CF_API/accounts/$CF_ACCOUNT_ID/alerting/v3/destinations/webhooks" \
  "$CF_API/accounts/$CF_ACCOUNT_ID/alerting/v3/destinations/eligible")

# Build name→id lookup (webhook + email destinations)
lookup_destination() {
  local name="$1"
  curl -s "${AUTH[@]}" "$CF_API/accounts/$CF_ACCOUNT_ID/alerting/v3/destinations/webhooks" \
    | jq -r --arg name "$name" '.result[]? | select(.name == $name) | .id' \
    | head -1
}

# ---------------------------------------------------------------------------
# Apply each notification policy from YAML
# ---------------------------------------------------------------------------
NUM=$(yq '.notifications | length' "$CONFIG")
ok "found $NUM notification policies in $CONFIG"

APPLIED=0
for i in $(seq 0 $((NUM-1))); do
  NAME=$(yq -r ".notifications[$i].name" "$CONFIG")
  ALERT_TYPE=$(yq -r ".notifications[$i].alert_type" "$CONFIG")
  ENABLED=$(yq -r ".notifications[$i].enabled // true" "$CONFIG")
  DESCRIPTION=$(yq -r ".notifications[$i].description" "$CONFIG")

  DEST_IDS=()
  for dname in $(yq -r ".notifications[$i].destinations[]" "$CONFIG"); do
    did=$(lookup_destination "$dname")
    [ -z "$did" ] && { warn "destination not found: $dname (skipping policy $NAME)"; continue 2; }
    DEST_IDS+=("$did")
  done

  BODY=$(jq -n \
    --arg name "$NAME" \
    --arg alert_type "$ALERT_TYPE" \
    --argjson enabled "$ENABLED" \
    --arg description "$DESCRIPTION" \
    --argjson webhooks "$(printf '%s\n' "${DEST_IDS[@]}" | jq -R . | jq -s .)" \
    '{name: $name, alert_type: $alert_type, enabled: $enabled, description: $description, mechanisms: {webhooks: ($webhooks | map({id: .}))}}')

  if $DRY_RUN; then
    printf '%s[dry-run]%s would apply: %s (%s)\n' "$YLW" "$RST" "$NAME" "$ALERT_TYPE"
    printf '  body: %s\n' "$(echo "$BODY" | jq -c .)"
    continue
  fi

  # Upsert: list existing by name, update or create
  EXISTING_ID=$(curl -s "${AUTH[@]}" \
    "$CF_API/accounts/$CF_ACCOUNT_ID/alerting/v3/policies" \
    | jq -r --arg name "$NAME" '.result[]? | select(.name == $name) | .id' | head -1)

  if [ -n "$EXISTING_ID" ]; then
    RESP=$(curl -s "${AUTH[@]}" -X PUT \
      "$CF_API/accounts/$CF_ACCOUNT_ID/alerting/v3/policies/$EXISTING_ID" \
      -d "$BODY")
    SUCCESS=$(echo "$RESP" | jq -r '.success')
    [ "$SUCCESS" = "true" ] && ok "updated: $NAME" || { warn "update failed: $NAME — $(echo "$RESP" | jq -c '.errors')"; continue; }
  else
    RESP=$(curl -s "${AUTH[@]}" -X POST \
      "$CF_API/accounts/$CF_ACCOUNT_ID/alerting/v3/policies" \
      -d "$BODY")
    SUCCESS=$(echo "$RESP" | jq -r '.success')
    [ "$SUCCESS" = "true" ] && ok "created: $NAME" || { warn "create failed: $NAME — $(echo "$RESP" | jq -c '.errors')"; continue; }
  fi
  APPLIED=$((APPLIED+1))
done

echo
if $DRY_RUN; then
  ok "dry-run complete: $NUM policies inspected"
else
  ok "applied $APPLIED/$NUM policies"
fi
