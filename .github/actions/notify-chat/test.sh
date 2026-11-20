#!/usr/bin/env bash
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
: > "$CAPTURE_HEADERS"
output=
body_file=
endpoint=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output=$2
      shift 2
      ;;
    -H)
      case "$2" in
        @*) cat "${2#@}" >> "$CAPTURE_HEADERS" ;;
        *) printf '%s\n' "$2" >> "$CAPTURE_HEADERS" ;;
      esac
      shift 2
      ;;
    --data-binary)
      body_file=${2#@}
      shift 2
      ;;
    -w | -X | --max-time | --retry)
      shift 2
      ;;
    -s | --)
      shift
      ;;
    *)
      endpoint=$1
      shift
      ;;
  esac
done
printf '%s' "$endpoint" > "$CAPTURE_ENDPOINT"
cp "$body_file" "$CAPTURE_BODY"
printf '%s' "${MOCK_RESPONSE_BODY:-safe response}" > "$output"
printf '%s\n' "${MOCK_HTTP_CODE:-202}"
EOF
chmod +x "$TMP/bin/curl"

export PATH="$TMP/bin:$PATH"
export CAPTURE_HEADERS="$TMP/headers"
export CAPTURE_ENDPOINT="$TMP/endpoint"
export CAPTURE_BODY="$TMP/body"
export PROXY_ENDPOINT='https://proxy.invalid/v1/events/github-actions'
export HMAC_SECRET='test-hmac-secret'
export NOTIFICATION_KEY='housekeeping-summary'
export STATUS='fail'
export SOURCE='housekeeping'
export SUBJECT='Wed 21 Oct'
export SUMMARY='ANOMALY: nginx unavailable'
export DETAILS=$'pxy-1\n  inactive'
export LINK='https://github.com/freeCodeCamp/infra/actions/runs/123'
export LINK_LABEL='run'
export GITHUB_REPOSITORY='freeCodeCamp/infra'
export GITHUB_RUN_ID='123'
export GITHUB_RUN_ATTEMPT='2'

output=$(bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'accepted the notification (HTTP 202)'

HMAC_SECRET="$HMAC_SECRET" CAPTURE_HEADERS="$CAPTURE_HEADERS" CAPTURE_BODY="$CAPTURE_BODY" python3 - <<'PY'
import hashlib
import hmac
import json
import os

body = open(os.environ["CAPTURE_BODY"], "rb").read()
headers = dict(
    line.rstrip("\n").split(": ", 1)
    for line in open(os.environ["CAPTURE_HEADERS"], encoding="utf-8")
)
payload = json.loads(body)
assert payload["schema"] == "fcc.github-actions-event/v1"
assert payload["status"] == "fail"
assert payload["details"] == "pxy-1\n  inactive"
assert payload["repository"] == "freeCodeCamp/infra"
assert payload["run_id"] == "123"
assert payload["run_attempt"] == "2"
assert payload["notification_key"] == "housekeeping-summary"
timestamp = headers["X-FCC-Timestamp"]
expected = "sha256=" + hmac.new(
    os.environ["HMAC_SECRET"].encode(),
    timestamp.encode() + b"." + body,
    hashlib.sha256,
).hexdigest()
assert hmac.compare_digest(headers["X-FCC-Signature"], expected)
PY

LINK=''
export LINK
output=$(bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'accepted the notification (HTTP 202)'
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["link"] == "https://github.com/freeCodeCamp/infra/actions/runs/123"' "$CAPTURE_BODY"

rm -f "$CAPTURE_BODY"
HMAC_SECRET='' output=$(HMAC_SECRET='' bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'credential is empty'
test ! -e "$CAPTURE_BODY"

HMAC_SECRET='test-hmac-secret'
PROXY_ENDPOINT='http://proxy.invalid/v1/events/github-actions?credential=bad'
export HMAC_SECRET PROXY_ENDPOINT
output=$(bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'proxy endpoint is invalid'
test ! -e "$CAPTURE_BODY"
PROXY_ENDPOINT='https://proxy.invalid/v1/events/github-actions'
export PROXY_ENDPOINT

HMAC_SECRET='test-hmac-secret'
export HMAC_SECRET
STATUS='invalid'
export STATUS
output=$(bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'status must be ok, warn or fail'
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "fail"' "$CAPTURE_BODY"

STATUS='ok'
DETAILS='must not be sent for ok'
MOCK_HTTP_CODE=503
MOCK_RESPONSE_BODY='sensitive provider response'
export STATUS DETAILS MOCK_HTTP_CODE MOCK_RESPONSE_BODY
output=$(bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'rejected the notification (HTTP 503)'
if printf '%s' "$output" | grep -q 'proxy.invalid\|sensitive provider response'; then
  echo 'failure output leaked endpoint or response body' >&2
  exit 1
fi
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["details"] is None' "$CAPTURE_BODY"

MOCK_HTTP_CODE=000
export MOCK_HTTP_CODE
output=$(bash "$HERE/notify.sh")
printf '%s' "$output" | grep -q 'rejected the notification (HTTP 000)'

ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
if grep -q 'GOOGLE_CHAT_WEBHOOK' "$ROOT/.github/actions/notify-chat/action.yml" "$ROOT/.github/actions/notify-chat/notify.sh" "$ROOT/.github/workflows/ansible--housekeeping.yml" "$ROOT/.github/workflows/ansible--verify-nginx.yml"; then
  echo 'GitHub notifier still references the direct Chat credential' >&2
  exit 1
fi
test "$(grep -R -h 'notification_key:' "$ROOT/.github/workflows/ansible--housekeeping.yml" "$ROOT/.github/workflows/ansible--verify-nginx.yml" | wc -l)" -eq 3

echo 'notify-chat checks passed'
