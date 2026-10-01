#!/bin/sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

cat >"$work/bin/curl" <<'EOF'
#!/bin/sh
out=""
url=""
data=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift 2 ;;
    -d) data=$2; shift 2 ;;
    -H) printf 'H %s\n' "$2" >> "$FAKE_LOG"; shift 2 ;;
    --retry) printf 'RETRY %s\n' "$2" >> "$FAKE_LOG"; shift 2 ;;
    -w | -X | --max-time) shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  "$FAKE_CHAT_URL") kind=CHAT; code=200 ;;
  *) kind=API; code=${FAKE_CODE:-204} ;;
esac
printf '%s %s\n' "$kind" "$url" >> "$FAKE_LOG"
printf '%s %s\n' "${kind}DATA" "$data" >> "$FAKE_LOG"
if [ -n "$out" ]; then printf '%s' "${FAKE_BODY:-}" > "$out"; fi
printf '%s' "$code"
if [ "$code" = 000 ]; then exit 7; fi
EOF
chmod +x "$work/bin/curl"

WED_0100=1790730000
WED_0559=1790747940
WED_0600=1790748000
TUE_2359=1790726340
SAT_0000=1790985600
SAT_0130=1790991000
THU_0605=1790834700
THU_0130=1790818200
WED_0905=1790759100

failures=0
log="$work/log"
status=0

run_dispatch() {
  : >"$log"
  env -i PATH="$work/bin:/usr/bin:/bin" \
    FAKE_LOG="$log" FAKE_CHAT_URL="http://chat.test/hook" \
    GITHUB_DISPATCH_TOKEN=tok DISPATCH_REPO=freeCodeCamp/news \
    DISPATCH_WORKFLOW=deploy-eng.yml GITHUB_API_URL="http://api.test" \
    GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" \
    "$@" sh "$here/dispatch.sh" >"$work/out" 2>&1
  status=$?
}

check() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: want [%s] got [%s]\n' "$1" "$3" "$2"
    sed 's/^/     | /' "$work/out" "$log"
    failures=$((failures + 1))
  fi
}

api_calls() { grep -c '^API ' "$log"; }
chat_calls() { grep -c '^CHAT ' "$log"; }

json_probe='import json, sys
text = json.load(sys.stdin)["text"]
print(int(all(arg in text for arg in sys.argv[1:])))'

chat_text_has() {
  grep '^CHATDATA ' "$log" | sed 's/^CHATDATA //' | python3 -c "$json_probe" "$@" 2>&1
}

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0100
check "avoid inside window exits 0" "$status" 0
check "avoid inside window makes no API call" "$(api_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0559
check "window includes Wed 05:59" "$(api_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$SAT_0000
check "window includes Sat 00:00" "$(api_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0600
check "window excludes Wed 06:00" "$(api_calls)" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$TUE_2359
check "window excludes Tue 23:59" "$(api_calls)" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0905
check "window excludes Wed 09:05 (leading-zero hour)" "$(api_calls)" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$THU_0605
check "avoid outside window exits 0" "$status" 0
check "avoid outside window dispatches once" "$(api_calls)" 1
check "dispatch URL" "$(grep '^API ' "$log")" \
  "API http://api.test/repos/freeCodeCamp/news/actions/workflows/deploy-eng.yml/dispatches"
check "dispatch body" "$(grep '^APIDATA ' "$log")" 'APIDATA {"ref":"main"}'
check "bearer header" "$(grep -c '^H Authorization: Bearer tok$' "$log")" 1
check "api version header" "$(grep -c '^H X-GitHub-Api-Version: 2022-11-28$' "$log")" 1
check "success posts no chat" "$(chat_calls)" 0
check "dispatch POST is never retried" "$(grep -c '^RETRY ' "$log")" 0

run_dispatch WINDOW_POLICY=require DISPATCH_NOW=$SAT_0130
check "require inside window dispatches" "$(api_calls)" 1
check "require inside window exits 0" "$status" 0

run_dispatch WINDOW_POLICY=require DISPATCH_NOW=$THU_0130
check "require outside window exits 1" "$status" 1
check "require outside window makes no API call" "$(api_calls)" 0
check "require outside window posts chat" "$(chat_calls)" 1
check "refusal names the target" "$(grep -c 'freeCodeCamp/news deploy-eng.yml' "$log")" 1

run_dispatch DISPATCH_NOW=$WED_0100
check "no policy dispatches inside window" "$(api_calls)" 1

run_dispatch DISPATCH_NOW=$THU_0605 DISPATCH_REF=release
check "ref override" "$(grep '^APIDATA ' "$log")" 'APIDATA {"ref":"release"}'

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=401 FAKE_BODY='{"message":"Bad credentials"}'
check "API 401 exits 1" "$status" 1
check "API 401 posts chat" "$(chat_calls)" 1
check "chat is JSON with status and API message" "$(chat_text_has 'HTTP 401' 'Bad credentials')" 1

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=000
check "transport failure exits 1" "$status" 1
check "transport failure posts chat" "$(chat_calls)" 1
check "transport failure reports HTTP 000" "$(chat_text_has 'HTTP 000')" 1

tab=$(printf '\t')
cr=$(printf '\r')
run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=500 \
  FAKE_BODY="bad${tab}gate${cr} \"quoted\" back\\slash é and ✓"
check "control characters still give valid JSON" "$(chat_text_has '"quoted"' 'back\slash')" 1

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=401 GOOGLE_CHAT_WEBHOOK=
check "empty webhook still exits 1" "$status" 1
check "empty webhook posts no chat" "$(chat_calls)" 0

run_dispatch DISPATCH_NOW=$THU_0605 GITHUB_DISPATCH_TOKEN=
check "missing token exits 2" "$status" 2
check "missing token makes no API call" "$(api_calls)" 0
check "missing token posts chat" "$(chat_calls)" 1
check "config chat names the variable" "$(chat_text_has GITHUB_DISPATCH_TOKEN)" 1

run_dispatch DISPATCH_NOW=$THU_0605 WINDOW_POLICY=sometimes
check "bad policy exits 2" "$status" 2
check "bad policy makes no API call" "$(api_calls)" 0
check "bad policy posts chat" "$(chat_calls)" 1

if [ "$failures" -gt 0 ]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
echo "all checks passed"
