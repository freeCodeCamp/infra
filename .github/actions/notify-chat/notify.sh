#!/usr/bin/env bash
set -u

if [ -z "${PROXY_ENDPOINT:-}" ] || [ -z "${HMAC_SECRET:-}" ]; then
  echo "::warning::DevOps Alerts proxy endpoint or GitHub credential is empty -- no notification sent"
  exit 0
fi

case "${STATUS:-}" in
  ok | warn | fail) ;;
  *)
    echo "::warning::notify-chat status must be ok, warn or fail, got '${STATUS:-}'"
    STATUS=fail
    ;;
esac

if [ -z "${NOTIFICATION_KEY:-}" ]; then
  echo "::warning::notify-chat notification_key is empty -- no notification sent"
  exit 0
fi

if ! PROXY_ENDPOINT="$PROXY_ENDPOINT" python3 - <<'PY'
import os
from urllib.parse import urlsplit

endpoint = os.environ["PROXY_ENDPOINT"]
parts = urlsplit(endpoint)
valid = (
    endpoint == endpoint.strip()
    and not any(ord(character) < 33 or ord(character) == 127 for character in endpoint)
    and parts.scheme == "https"
    and bool(parts.hostname)
    and not parts.username
    and not parts.password
    and not parts.query
    and not parts.fragment
    and parts.path == "/v1/events/github-actions"
)
raise SystemExit(0 if valid else 1)
PY
then
  echo "::warning::DevOps Alerts proxy endpoint is invalid -- no notification sent"
  exit 0
fi

LINK=${LINK:-${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-0}}
export LINK
if [ "$STATUS" = ok ]; then
  DETAILS=""
fi

body=$(mktemp) || {
  echo "::warning::notify-chat could not allocate a request file -- no notification sent"
  exit 0
}
headers=$(mktemp) || {
  rm -f "$body"
  echo "::warning::notify-chat could not allocate a header file -- no notification sent"
  exit 0
}
response=$(mktemp) || {
  rm -f "$body" "$headers"
  echo "::warning::notify-chat could not allocate a response file -- no notification sent"
  exit 0
}
trap 'rm -f "$body" "$headers" "$response"' EXIT
if ! chmod 600 "$body" "$headers" "$response"; then
  echo "::warning::notify-chat could not secure temporary files -- no notification sent"
  exit 0
fi

if ! BODY_FILE="$body" python3 - <<'PY'
import json
import os

payload = {
    "schema": "fcc.github-actions-event/v1",
    "status": os.environ["STATUS"],
    "source": os.environ["SOURCE"],
    "subject": os.environ["SUBJECT"],
    "summary": os.environ["SUMMARY"],
    "details": os.environ.get("DETAILS") or None,
    "link": os.environ.get("LINK") or None,
    "link_label": os.environ.get("LINK_LABEL") or "run",
    "repository": os.environ.get("GITHUB_REPOSITORY", ""),
    "run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", ""),
    "notification_key": os.environ["NOTIFICATION_KEY"],
}
with open(os.environ["BODY_FILE"], "wb") as target:
    target.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode())
PY
then
  echo "::warning::notify-chat could not encode the request -- no notification sent"
  exit 0
fi

timestamp=$(date -u +%s) || {
  echo "::warning::notify-chat could not create a timestamp -- no notification sent"
  exit 0
}
if ! signature=$(BODY_FILE="$body" TIMESTAMP="$timestamp" python3 - <<'PY'
import hashlib
import hmac
import os

with open(os.environ["BODY_FILE"], "rb") as source:
    body = source.read()
signed = os.environ["TIMESTAMP"].encode() + b"." + body
print("sha256=" + hmac.new(os.environ["HMAC_SECRET"].encode(), signed, hashlib.sha256).hexdigest())
PY
)
then
  echo "::warning::notify-chat could not sign the request -- no notification sent"
  exit 0
fi
unset HMAC_SECRET
if ! printf 'Content-Type: application/json\nX-FCC-Timestamp: %s\nX-FCC-Signature: %s\n' \
  "$timestamp" "$signature" > "$headers"; then
  echo "::warning::notify-chat could not prepare request headers -- no notification sent"
  exit 0
fi

code=$(curl -s -o "$response" -w '%{http_code}\n' \
  -X POST \
  -H "@$headers" \
  --max-time 30 \
  --retry 2 \
  --retry-max-time 120 \
  --data-binary "@$body" \
  -- "$PROXY_ENDPOINT" | tail -n1 || true)
case "$code" in
  '' | *[!0-9]*) code=000 ;;
esac

if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
  echo "DevOps Alerts proxy accepted the notification (HTTP $code)"
  exit 0
fi

echo "::error::DevOps Alerts proxy rejected the notification (HTTP $code) -- the run result is unaffected"
exit 0
