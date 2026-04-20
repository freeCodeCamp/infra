#!/usr/bin/env bash
# scripts/uptime-robot-apply.sh — T24 apply declarative Uptime Robot monitors
#
# Reads uptime-robot/monitors.yaml and applies to Uptime Robot via API v2.
#
# Usage:
#   just uptime-robot-apply              # apply
#   just uptime-robot-apply --dry-run    # show intended diff, no writes
#
# Requires: curl, jq, yq (v4), sops+age.
# Credentials: infra-secrets/uptime-robot/api.env.enc
#   UPTIME_ROBOT_API_KEY

set -euo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

CONFIG="${CONFIG:-uptime-robot/monitors.yaml}"
SECRETS_DIR="${SECRETS_DIR:-$(git rev-parse --show-toplevel)/../infra-secrets}"
SECRET_ENC="$SECRETS_DIR/uptime-robot/api.env.enc"

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
: "${UPTIME_ROBOT_API_KEY:?UPTIME_ROBOT_API_KEY missing}"

UR_API="https://api.uptimerobot.com/v2"

# Type mapping: UR uses integers for monitor types.
#   1 = HTTP(s), 2 = Keyword, 3 = Ping, 4 = Port, 5 = Heartbeat
declare -A TYPE_MAP=([http]=1 [https]=1 [keyword]=2 [ping]=3 [port]=4 [heartbeat]=5)

# ---------------------------------------------------------------------------
# Resolve alert-contact names to IDs (getAlertContacts)
# ---------------------------------------------------------------------------
ok "fetching Uptime Robot alert contacts"
CONTACTS=$(curl -s -X POST "$UR_API/getAlertContacts" \
  -d "api_key=$UPTIME_ROBOT_API_KEY&format=json")

lookup_contact() {
  echo "$CONTACTS" | jq -r --arg name "$1" '.alert_contacts[]? | select(.friendly_name == $name) | .id' | head -1
}

DEFAULT_CONTACTS=""
DEFAULT_NAMES=$(yq -r '.defaults.alert_contacts[]' "$CONFIG")
for name in $DEFAULT_NAMES; do
  cid=$(lookup_contact "$name")
  [ -z "$cid" ] && warn "default contact not found: $name"
  DEFAULT_CONTACTS+="${cid}_0_0-"
done
DEFAULT_CONTACTS="${DEFAULT_CONTACTS%-}"   # strip trailing dash

# ---------------------------------------------------------------------------
# Existing monitors (for upsert)
# ---------------------------------------------------------------------------
EXISTING=$(curl -s -X POST "$UR_API/getMonitors" \
  -d "api_key=$UPTIME_ROBOT_API_KEY&format=json")

lookup_monitor_id() {
  echo "$EXISTING" | jq -r --arg name "$1" '.monitors[]? | select(.friendly_name == $name) | .id' | head -1
}

# ---------------------------------------------------------------------------
# Apply each monitor
# ---------------------------------------------------------------------------
NUM=$(yq '.monitors | length' "$CONFIG")
ok "found $NUM monitors in $CONFIG"

APPLIED=0
for i in $(seq 0 $((NUM-1))); do
  NAME=$(yq -r ".monitors[$i].name" "$CONFIG")
  TYPE_NAME=$(yq -r ".monitors[$i].type" "$CONFIG")
  URL=$(yq -r ".monitors[$i].url" "$CONFIG")
  INTERVAL=$(yq -r ".monitors[$i].interval_seconds // .defaults.interval_seconds" "$CONFIG")
  TIMEOUT=$(yq -r ".monitors[$i].timeout_seconds // .defaults.timeout_seconds" "$CONFIG")
  TYPE="${TYPE_MAP[$TYPE_NAME]:-}"
  [ -z "$TYPE" ] && { warn "unknown monitor type: $TYPE_NAME (skipping $NAME)"; continue; }

  COMMON=(
    "api_key=$UPTIME_ROBOT_API_KEY"
    "format=json"
    "friendly_name=$NAME"
    "url=$URL"
    "type=$TYPE"
    "interval=$INTERVAL"
    "timeout=$TIMEOUT"
    "alert_contacts=$DEFAULT_CONTACTS"
  )

  FORM=$(IFS='&'; echo "${COMMON[*]}")

  EXISTING_ID=$(lookup_monitor_id "$NAME")

  if $DRY_RUN; then
    printf '%s[dry-run]%s would %s: %s (%s %s)\n' "$YLW" "$RST" \
      "$([ -n "$EXISTING_ID" ] && echo "edit monitor $EXISTING_ID" || echo "create")" \
      "$NAME" "$TYPE_NAME" "$URL"
    continue
  fi

  if [ -n "$EXISTING_ID" ]; then
    RESP=$(curl -s -X POST "$UR_API/editMonitor" -d "$FORM&id=$EXISTING_ID")
    STATUS=$(echo "$RESP" | jq -r '.stat')
    [ "$STATUS" = "ok" ] && ok "updated: $NAME" || { warn "update failed: $NAME — $(echo "$RESP" | jq -c '.error')"; continue; }
  else
    RESP=$(curl -s -X POST "$UR_API/newMonitor" -d "$FORM")
    STATUS=$(echo "$RESP" | jq -r '.stat')
    [ "$STATUS" = "ok" ] && ok "created: $NAME" || { warn "create failed: $NAME — $(echo "$RESP" | jq -c '.error')"; continue; }
  fi
  APPLIED=$((APPLIED+1))
done

echo
if $DRY_RUN; then
  ok "dry-run complete: $NUM monitors inspected"
else
  ok "applied $APPLIED/$NUM monitors"
fi
