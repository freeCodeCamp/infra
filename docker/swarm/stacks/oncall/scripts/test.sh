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

RUNS_URL=https://github.com/freeCodeCamp/news/actions/workflows/deploy-eng.yml

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

lines_probe='import json, sys
print(len(json.load(sys.stdin)["text"].splitlines()))'

chat_lines() {
  grep '^CHATDATA ' "$log" | sed 's/^CHATDATA //' | python3 -c "$lines_probe" 2>&1
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
check "refusal is a standard warn line" \
  "$(chat_text_has '⚠️ *dispatch* · freeCodeCamp/news deploy-eng.yml · refused: outside')" 1
check "refusal is one line" "$(chat_lines)" 1

run_dispatch DISPATCH_NOW=$WED_0100
check "no policy dispatches inside window" "$(api_calls)" 1

run_dispatch DISPATCH_NOW=$THU_0605 DISPATCH_REF=release
check "ref override" "$(grep '^APIDATA ' "$log")" 'APIDATA {"ref":"release"}'

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=401 FAKE_BODY='{"message":"Bad credentials"}'
check "API 401 exits 1" "$status" 1
check "API 401 posts chat" "$(chat_calls)" 1
check "chat is JSON with status and API message" "$(chat_text_has 'HTTP 401' 'Bad credentials')" 1
check "API failure is a standard fail line" \
  "$(chat_text_has '🔴 *dispatch* · freeCodeCamp/news deploy-eng.yml · failed: HTTP 401')" 1
check "API failure links the workflow runs" \
  "$(chat_text_has "<$RUNS_URL|runs>")" 1
check "API failure is one line" "$(chat_lines)" 1

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=000
check "transport failure exits 1" "$status" 1
check "transport failure posts chat" "$(chat_calls)" 1
check "transport failure reports HTTP 000" "$(chat_text_has 'HTTP 000')" 1

tab=$(printf '\t')
cr=$(printf '\r')
run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=500 \
  FAKE_BODY="bad${tab}gate${cr} \"quoted\" back\\slash é and ✓"
check "control characters still give valid JSON" "$(chat_text_has '"quoted"' 'back\slash')" 1

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=502 FAKE_BODY="$(printf 'bad\ngateway\n<html>')"
check "multi-line API body still gives one line" "$(chat_lines)" 1
check "angle brackets are dropped from the excerpt" "$(chat_text_has 'bad gateway html')" 1

run_dispatch DISPATCH_NOW=$THU_0605 FAKE_CODE=401 GOOGLE_CHAT_WEBHOOK=
check "empty webhook still exits 1" "$status" 1
check "empty webhook posts no chat" "$(chat_calls)" 0

run_dispatch DISPATCH_NOW=$THU_0605 GITHUB_DISPATCH_TOKEN=
check "missing token exits 2" "$status" 2
check "missing token makes no API call" "$(api_calls)" 0
check "missing token posts chat" "$(chat_calls)" 1
check "config chat names the variable" "$(chat_text_has GITHUB_DISPATCH_TOKEN)" 1
check "config error is a standard fail line" \
  "$(chat_text_has '🔴 *dispatch* · freeCodeCamp/news deploy-eng.yml · misconfigured: ')" 1
check "config error is one line" "$(chat_lines)" 1

run_dispatch DISPATCH_NOW=$THU_0605 WINDOW_POLICY=sometimes
check "bad policy exits 2" "$status" 2
check "bad policy makes no API call" "$(api_calls)" 0
check "bad policy posts chat" "$(chat_calls)" 1

BUILT="Thu, 01 Oct 2026 13:24:00 +0000"
BUILT_AT=1790861040
FRI_BUILT="Fri, 02 Oct 2026 21:30:00 +0000"
SAT_0759=1791014340
SAT_0800=1791014400
WED_0759=1790755140
HOUR=3600

feed_xml() {
  printf '<rss>\n  <channel>\n    <ttl>60</ttl>\n'
  printf '    <lastBuildDate>%s</lastBuildDate>\n  </channel>\n</rss>\n' "$1"
}

run_watchdog() {
  : >"$log"
  env -i PATH="$work/bin:/usr/bin:/bin" \
    FAKE_LOG="$log" FAKE_CHAT_URL="http://chat.test/hook" FAKE_CODE=200 \
    FAKE_BODY="$(feed_xml "$BUILT")" \
    GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" \
    "$@" sh "$here/watchdog.sh" >"$work/out" 2>&1
  status=$?
}

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 5 * HOUR - 60))
check "fresh feed exits 0" "$status" 0
check "fresh feed posts no chat" "$(chat_calls)" 0
check "default feed URL" "$(grep '^API ' "$log")" "API https://www.freecodecamp.org/news/rss.xml"
check "feed GET is retried" "$(grep -c '^RETRY 2$' "$log")" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 5 * HOUR))
check "age equal to the limit is fresh" "$(chat_calls)" 0

run_watchdog WATCHDOG_NOW=$((BUILT_AT - 30 * 60))
check "build under 1h in the future is fresh" "$status" 0

run_watchdog WATCHDOG_NOW=$((BUILT_AT - 2 * HOUR))
check "build over 1h in the future exits 1" "$status" 1
check "build over 1h in the future posts chat" "$(chat_text_has 'in the future')" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 5 * HOUR + 30 * 60))
check "first stale tick exits 1" "$status" 1
check "first stale tick posts chat" "$(chat_calls)" 1
check "stale chat names build, age and limit" \
  "$(chat_text_has "$BUILT" '5h 30m' 'limit 5h')" 1
check "stale chat links the deploy runs" \
  "$(chat_text_has "<$RUNS_URL|runs>")" 1
check "stale chat is a standard fail line" \
  "$(chat_text_has '🔴 *watchdog* · news English · stale: last build ')" 1
check "stale chat is one line" "$(chat_lines)" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 6 * HOUR + 2))
check "first stale tick that starts late posts chat" "$(chat_calls)" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 6 * HOUR + 30 * 60))
check "second stale tick exits 1" "$status" 1
check "second stale tick posts no chat" "$(chat_calls)" 0

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 10 * HOUR + 30 * 60))
check "stale tick before the reminder posts no chat" "$(chat_calls)" 0

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 11 * HOUR + 30 * 60))
check "reminder tick posts chat" "$(chat_calls)" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 5 * HOUR - 60)) \
  FAKE_BODY="$(feed_xml 'Thu, 01 Oct 2026 18:54:00 +0530')"
check "positive offset is applied" "$(chat_calls)" 0

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 5 * HOUR + 60)) \
  FAKE_BODY="$(feed_xml 'Thu, 01 Oct 2026 09:24:00 -0400')"
check "negative offset is applied" "$(chat_calls)" 1

run_watchdog WATCHDOG_NOW=$SAT_0759 FAKE_BODY="$(feed_xml "$FRI_BUILT")"
check "quiet hours exit 0" "$status" 0
check "quiet hours fetch nothing" "$(api_calls)" 0

run_watchdog WATCHDOG_NOW=$WED_0759 FAKE_BODY="$(feed_xml "$FRI_BUILT")"
check "quiet hours include Wed 07:59" "$(api_calls)" 0

run_watchdog WATCHDOG_NOW=$SAT_0800 FAKE_BODY="$(feed_xml "$FRI_BUILT")"
check "first tick after quiet hours posts chat" "$(chat_calls)" 1

run_watchdog WATCHDOG_NOW=$((SAT_0800 + 2 * HOUR)) FAKE_BODY="$(feed_xml "$FRI_BUILT")"
check "later tick after quiet hours follows the reminder" "$(chat_calls)" 0

run_watchdog WATCHDOG_NOW=$((BUILT_AT + HOUR)) FAKE_CODE=503
check "feed 503 exits 1" "$status" 1
check "feed 503 posts chat" "$(chat_text_has 'feed unreadable' 'HTTP 503')" 1
check "feed error is a standard fail line" \
  "$(chat_text_has '🔴 *watchdog* · news English · feed unreadable: HTTP 503')" 1
check "feed error links the feed" \
  "$(chat_text_has '<https://www.freecodecamp.org/news/rss.xml|feed>')" 1
check "feed error is one line" "$(chat_lines)" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + HOUR)) FAKE_CODE=000
check "feed transport failure posts chat" "$(chat_text_has 'HTTP 000')" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + HOUR)) FAKE_BODY='<rss></rss>'
check "missing lastBuildDate exits 1" "$status" 1
check "missing lastBuildDate posts chat" "$(chat_text_has 'lastBuildDate')" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + HOUR)) FAKE_BODY="$(feed_xml 'yesterday')"
check "unparseable lastBuildDate posts chat" "$(chat_text_has 'yesterday')" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + HOUR)) \
  FAKE_BODY="$(feed_xml 'Thu, 01 Foo 2026 13:24:51 +0000')"
check "unknown month posts chat" "$(chat_calls)" 1

run_watchdog WATCHDOG_NOW=$((BUILT_AT + 5 * HOUR + 30 * 60)) GOOGLE_CHAT_WEBHOOK=
check "stale with empty webhook exits 1" "$status" 1
check "stale with empty webhook posts no chat" "$(chat_calls)" 0

mkdir -p "$work/nocurl"
for tool in sh dirname awk sed tr; do
  ln -s "$(command -v "$tool")" "$work/nocurl/$tool"
done
cat >"$work/nocurl/wget" <<'EOF'
#!/bin/sh
url=""
data=""
while [ $# -gt 0 ]; do
  case "$1" in
    --post-data) data=$2; shift 2 ;;
    --header) printf 'H %s\n' "$2" >> "$FAKE_LOG"; shift 2 ;;
    -O | -T) shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
printf 'CHAT %s\n' "$url" >> "$FAKE_LOG"
printf 'CHATDATA %s\n' "$data" >> "$FAKE_LOG"
EOF
chmod +x "$work/nocurl/wget"

text_probe='import json, sys
print(int(json.load(sys.stdin)["text"] == sys.argv[1]))'

chat_text_is() {
  grep '^CHATDATA ' "$log" | sed 's/^CHATDATA //' | python3 -c "$text_probe" "$1" 2>&1
}

run_relay() {
  : >"$log"
  env -i PATH="$work/bin:/usr/bin:/bin" \
    FAKE_LOG="$log" FAKE_CHAT_URL="http://chat.test/hook" \
    GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" \
    "$@" sh "$here/relay.sh" >"$work/out" 2>&1
  status=$?
}

UPDATED=$(printf '1 service(s) updated: prd-news_svc-eng\n\n\n\n')
FAILED=$(printf 'No services updated.\n\n1 service(s) update failed: prd-news_svc-eng\n%s\n' \
  '1 service(s) rollback failed: prd-news_svc-eng')

run_relay RELAY_TYPE=success RELAY_TRIGGER=webhook RELAY_BODY="$UPDATED" \
  RELAY_TITLE='[gantry] 1 service(s) updated, no failures or errors'
check "relay exits 0" "$status" 0
check "relay posts one chat" "$(chat_calls)" 1
check "relay update is a standard ok line" \
  "$(chat_text_is '✅ *gantry* · webhook · 1 service(s) updated: prd-news_svc-eng')" 1

run_relay RELAY_TYPE=failure RELAY_TRIGGER=hourly RELAY_BODY="$FAILED" \
  RELAY_TITLE='[gantry] 0 service(s) updated, 1 update failed'
check "relay failure joins the report lines" "$(chat_text_is "🔴 *gantry* · hourly · \
1 service(s) update failed: prd-news_svc-eng; 1 service(s) rollback failed: prd-news_svc-eng")" 1

run_relay RELAY_TYPE=info RELAY_BODY= \
  RELAY_TITLE='[gantry] 0 service(s) updated, no failures or errors'
check "relay falls back to the title" "$(chat_text_is \
  '✅ *gantry* · update · 0 service(s) updated, no failures or errors')" 1

run_relay RELAY_TYPE=warning RELAY_TRIGGER=hourly RELAY_BODY="$UPDATED"
check "relay warning is a warn line" "$(chat_text_has '⚠️ *gantry* · hourly · ')" 1

run_relay RELAY_TYPE=success RELAY_BODY="$UPDATED" GOOGLE_CHAT_WEBHOOK=
check "relay with empty webhook exits 0" "$status" 0
check "relay with empty webhook posts no chat" "$(chat_calls)" 0

: >"$log"
env -i PATH="$work/nocurl" FAKE_LOG="$log" GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" \
  RELAY_TYPE=success RELAY_TRIGGER=webhook RELAY_BODY="$UPDATED" \
  sh "$here/relay.sh" >"$work/out" 2>&1
check "relay without curl exits 0" "$?" 0
check "relay without curl posts with wget" "$(chat_calls)" 1
check "wget post sends JSON" \
  "$(grep -c '^H Content-Type: application/json; charset=UTF-8$' "$log")" 1
check "wget post is a standard ok line" \
  "$(chat_text_is '✅ *gantry* · webhook · 1 service(s) updated: prd-news_svc-eng')" 1

if [ "$failures" -gt 0 ]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
echo "all checks passed"
