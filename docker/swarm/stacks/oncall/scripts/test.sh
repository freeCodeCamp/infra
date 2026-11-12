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
dispatch_calls() { grep -c '^API .*/dispatches$' "$log"; }
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

LAST_OK='{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://github.com/freeCodeCamp/news/actions/runs/1"}]}'
LAST_FAILED='{"workflow_runs":[{"id":2,"status":"completed","conclusion":"failure","html_url":"https://github.com/freeCodeCamp/news/actions/runs/2"}]}'

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0100 FAKE_CODE=200 FAKE_BODY="$LAST_OK"
check "avoid inside window exits 0" "$status" 0
check "avoid inside window starts nothing" "$(dispatch_calls)" 0
check "avoid inside window reads the last main run" "$(grep '^API ' "$log")" \
  "API http://api.test/repos/freeCodeCamp/news/actions/workflows/deploy-eng.yml/runs?branch=main&status=completed&per_page=1"
check "avoid skip after a good run posts no chat" "$(chat_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0100 FAKE_CODE=200 FAKE_BODY="$LAST_FAILED"
check "avoid skip after a failed run exits 0" "$status" 0
check "avoid skip after a failed run starts nothing" "$(dispatch_calls)" 0
check "avoid skip after a failed run is a standard warn line" \
  "$(chat_text_has '⚠️ *dispatch* · freeCodeCamp/news deploy-eng.yml · skipped: inside the maintenance window, the last run is failure')" 1
check "avoid skip after a failed run links that run" \
  "$(chat_text_has '<https://github.com/freeCodeCamp/news/actions/runs/2|last run>')" 1
check "avoid skip warn is one line" "$(chat_lines)" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$((WED_0100 + 2 * 3600 + 5 * 60)) FAKE_CODE=200 FAKE_BODY="$LAST_FAILED"
check "second window skip after a failed run posts no chat" "$(chat_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0100 DISPATCH_REF=refs/heads/main FAKE_CODE=200 FAKE_BODY="$LAST_FAILED"
check "full ref reads runs by branch name" "$(grep -c 'runs?branch=main&' "$log")" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0100 FAKE_CODE=200 \
  FAKE_BODY='{"workflow_runs":[{"conclusion":"cancelled","html_url":"https://x.test/3"}]}'
check "avoid skip after a cancelled run posts chat" "$(chat_text_has 'the last run is cancelled')" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0100 FAKE_CODE=503 FAKE_BODY=down
check "avoid skip with an unreadable API exits 0" "$status" 0
check "avoid skip with an unreadable API posts no chat" "$(chat_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0559
check "window includes Wed 05:59" "$(dispatch_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$SAT_0000
check "window includes Sat 00:00" "$(dispatch_calls)" 0

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0600
check "window excludes Wed 06:00" "$(dispatch_calls)" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$TUE_2359
check "window excludes Tue 23:59" "$(dispatch_calls)" 1

run_dispatch WINDOW_POLICY=avoid DISPATCH_NOW=$WED_0905
check "window excludes Wed 09:05 (leading-zero hour)" "$(dispatch_calls)" 1

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
if [ -n "${FAKE_WGET_FAIL:-}" ]; then
  printf 'wget: %s: server returned error\n' "$url" >&2
  exit 1
fi
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

: >"$log"
env -i PATH="$work/nocurl" FAKE_LOG="$log" FAKE_WGET_FAIL=1 \
  GOOGLE_CHAT_WEBHOOK="http://chat.test/hook-secret" RELAY_TYPE=failure RELAY_BODY="$FAILED" \
  sh "$here/relay.sh" >"$work/out" 2>&1
check "relay with failed wget exits 0" "$?" 0
check "failed wget is logged" \
  "$(grep -c '^chat: Google Chat rejected the message (wget exit 1)$' "$work/out")" 1
check "failed wget keeps the webhook out of the output" "$(grep -c 'hook-secret' "$work/out")" 0

: >"$log"
env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$log" FAKE_CHAT_URL="http://chat.test/hook" \
  GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" \
  sh -c ". '$here/lib.sh' && chat_notify ok '<b>src' subject summary" >"$work/out" 2>&1
check "source loses its angle brackets" "$(chat_text_is '✅ *bsrc* · subject · summary')" 1

cat >"$work/bin/docker" <<'EOF'
#!/bin/sh
printf 'DOCKER %s\n' "$*" >> "$FAKE_LOG"
[ -z "${FAKE_DOCKER_FAIL:-}" ] || exit 1
case "$*" in
  *label=swarm.cronjob.enable=true*) printf '%s\n' "${FAKE_CRON:-}" ;;
  "service ls"*)
    if [ -n "${FAKE_RECOVER:-}" ] && [ "$(grep -c '^DOCKER service ls --format' "$FAKE_LOG")" -gt 1 ]; then
      printf '%s\n' "$FAKE_RECOVER"
    else
      printf '%s\n' "${FAKE_SERVICES:-}"
    fi
    ;;
  "service ps"*) printf '%s\n' "${FAKE_TASKS:-}" ;;
esac
EOF
chmod +x "$work/bin/docker"

cat >"$work/bin/sleep" <<'EOF'
#!/bin/sh
printf 'SLEEP %s\n' "$1" >> "$FAKE_LOG"
if [ -n "${FAKE_SLEEP_RM:-}" ]; then rm -f "$FAKE_SLEEP_RM"; fi
EOF
chmod +x "$work/bin/sleep"

run_swarm_check() {
  prefix=$1
  shift
  : >"$log"
  env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$log" "$@" \
    sh "$here/swarm-check.sh" $prefix >"$work/out" 2>&1
  status=$?
}

run_watchdog_swarm() {
  : >"$log"
  env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$log" FAKE_CHAT_URL="http://chat.test/hook" \
    GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" "$@" \
    sh "$here/watchdog-swarm.sh" >"$work/out" 2>&1
  status=$?
}

run_watchdog_vxlan() {
  : >"$log"
  env -i PATH="$work/bin:/usr/bin:/bin" FAKE_LOG="$log" FAKE_CHAT_URL="http://chat.test/hook" \
    GOOGLE_CHAT_WEBHOOK="http://chat.test/hook" WATCHDOG_NET_DIR="$work/net" \
    NODE_NAME=api-1.stg "$@" \
    sh "$here/watchdog-vxlan.sh" >"$work/out" 2>&1
  status=$?
}

HEALTHY='stg-socrates_svc-socrates-bravo|replicated|3/3 (max 1 per node)
stg-socrates_svc-redis|global|3/3
oncall_svc-cleanup|global|0/0'

run_swarm_check "" FAKE_SERVICES="$HEALTHY"
check "healthy swarm exits 0" "$status" 0
check "healthy swarm prints nothing" "$(cat "$work/out")" ""

run_swarm_check "" FAKE_SERVICES='stg-socrates_svc-socrates-bravo|replicated|2/3 (max 1 per node)'
check "replicated service below target exits 1" "$status" 1
check "replicated service below target is named" "$(cat "$work/out")" \
  "below target: stg-socrates_svc-socrates-bravo 2/3"

run_swarm_check "" FAKE_SERVICES='prd-socrates_svc-redis|global|2/3'
check "global service below target is named" "$(cat "$work/out")" \
  "below target: prd-socrates_svc-redis 2/3"

run_swarm_check "" FAKE_CRON='cron|oncall_svc-update' FAKE_SERVICES='oncall_svc-update|replicated|0/1'
check "cron service at 0/1 is not a finding" "$status" 0

run_swarm_check "" FAKE_SERVICES='gantry-1-13|replicated job|0/1 (1/1 completed)'
check "job service is not a finding" "$status" 0

run_swarm_check stg- FAKE_SERVICES='prd-api_svc-api-alpha|replicated|1/3
stg-api_svc-api-alpha|replicated|3/3'
check "prefix ignores other services" "$status" 0
check "prefix limits the task read" "$(grep -c '^DOCKER service ps .*prd-api' "$log")" 0
check "prefix keeps its own services in the task read" \
  "$(grep -c '^DOCKER service ps .*stg-api_svc-api-alpha' "$log")" 1

run_swarm_check "" FAKE_SERVICES="$HEALTHY" FAKE_TASKS='api-1|Rejected 5 seconds ago
api-1|Rejected less than a second ago
api-1|Rejected About a minute ago
api-2|Running 2 hours ago'
check "repeated rejections exit 1" "$status" 1
check "repeated rejections name the node" "$(cat "$work/out")" \
  "rejecting tasks: api-1 (3 in the last 15 min)"

run_swarm_check "" FAKE_SERVICES="$HEALTHY" FAKE_TASKS='api-1|Rejected 14 minutes ago
api-1|Rejected 14 minutes ago
api-2|Rejected 1 second ago'
check "two rejections are not repeated" "$status" 0

run_swarm_check "" FAKE_SERVICES="$HEALTHY" FAKE_TASKS='api-1|Rejected 15 minutes ago
api-1|Rejected 3 hours ago
api-1|Rejected About an hour ago
api-1|Rejected 2 days ago'
check "old rejections are not a finding" "$status" 0

run_swarm_check "" FAKE_DOCKER_FAIL=1
check "unreadable swarm exits 2" "$status" 2
check "unreadable swarm says so" "$(cat "$work/out")" "could not read the Swarm"

run_watchdog_swarm WATCHDOG_NOW=$SAT_0130 FAKE_SERVICES='a|replicated|1/3'
check "swarm watchdog is quiet in the window" "$status" 0
check "swarm watchdog reads nothing in the window" "$(grep -c '^DOCKER ' "$log")" 0

run_watchdog_swarm WATCHDOG_NOW=$THU_0605 FAKE_SERVICES="$HEALTHY"
check "healthy swarm watchdog exits 0" "$status" 0
check "healthy swarm watchdog posts nothing" "$(chat_calls)" 0
check "healthy swarm watchdog does not wait" "$(grep -c '^SLEEP ' "$log")" 0

run_watchdog_swarm WATCHDOG_NOW=$THU_0605 FAKE_SERVICES='a|replicated|1/3' FAKE_RECOVER='a|replicated|3/3'
check "recovered swarm watchdog exits 0" "$status" 0
check "recovered swarm watchdog posts nothing" "$(chat_calls)" 0
check "swarm watchdog waits before its second read" "$(grep -c '^SLEEP 60$' "$log")" 1

run_watchdog_swarm WATCHDOG_NOW=$THU_0605 FAKE_SERVICES='a|replicated|1/3
b|global|2/3'
check "broken swarm watchdog exits 1" "$status" 1
check "broken swarm watchdog posts once" "$(chat_calls)" 1
check "broken swarm watchdog is a standard fail line" \
  "$(chat_text_has '🔴 *watchdog* · swarm · below target: a 1/3; below target: b 2/3')" 1
check "broken swarm watchdog post is one line" "$(chat_lines)" 1

run_watchdog_swarm WATCHDOG_NOW=$THU_0605 FAKE_DOCKER_FAIL=1
check "unreadable swarm watchdog posts" "$(chat_text_has 'could not read the Swarm')" 1

mkdir -p "$work/net"
: >"$work/net/eth0"
: >"$work/net/docker_gwbridge"
: >"$work/net/vx-nothex-lhno1"
: >"$work/net/vx-001008-lhno1x"

run_watchdog_vxlan
check "no stray device exits 0" "$status" 0
check "no stray device posts nothing" "$(chat_calls)" 0

: >"$work/net/vx-001008-lhno1"
run_watchdog_vxlan
check "stray device exits 1" "$status" 1
check "stray device waits before its second read" "$(grep -c '^SLEEP 5$' "$log")" 1
check "stray device post names the node and device" \
  "$(chat_text_has '🔴 *watchdog* · api-1.stg · stray overlay device vx-001008-lhno1')" 1

run_watchdog_vxlan FAKE_SLEEP_RM="$work/net/vx-001008-lhno1"
check "device in transit exits 0" "$status" 0
check "device in transit posts nothing" "$(chat_calls)" 0

mkdir -p "$work/gbin"
cat >"$work/gbin/docker" <<'EOF'
#!/bin/sh
printf '%s %s\n' "$1" "$2" >> "$FAKE_LOG"
case "$1 $2" in
  "service create") printf '%s\n' "$*" >> "$FAKE_LOG.args"; echo "create-id"; exit "${FAKE_CREATE_RC:-0}" ;;
  "service ps")
    n=$(cat "$FAKE_LOG.n" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$FAKE_LOG.n"
    state=$(echo "$FAKE_PS_STATES" | tr ',' '\n' | sed -n "${n}p")
    [ -n "$state" ] || state=$(echo "$FAKE_PS_STATES" | tr ',' '\n' | tail -n 1)
    echo "$state 3 seconds ago"
    exit 0 ;;
  "service logs") echo "gantry-log-line"; exit "${FAKE_LOGS_RC:-0}" ;;
  "service rm") exit "${FAKE_RM_RC:-0}" ;;
esac
EOF
cat >"$work/gbin/sleep" <<'EOF'
#!/bin/sh
printf 'sleep %s\n' "$1" >> "$FAKE_LOG"
EOF
chmod +x "$work/gbin/docker" "$work/gbin/sleep"

run_gantry() {
  : >"$log"
  rm -f "$log.n" "$log.args"
  env -i PATH="$work/gbin:/usr/bin:/bin" FAKE_LOG="$log" "$@" \
    sh "$here/../run_gantry.sh" test-arg >"$work/out" 2>&1
  status=$?
}

run_gantry FAKE_PS_STATES=Running,Running,Complete
check "gantry complete exits 0" "$status" 0
check "gantry complete polls until the state is Complete" "$(grep -c '^service ps$' "$log")" 3
check "gantry complete sleeps between polls" "$(grep -c '^sleep 5$' "$log")" 2
check "gantry complete prints the job logs" "$(grep -c '^gantry-log-line$' "$work/out")" 1
check "gantry complete removes the job" "$(grep -c '^service rm$' "$log")" 1
check "gantry job does not restart a failed task" "$(grep -c -e '--restart-condition none' "$log.args")" 1
check "gantry job is created detached" "$(grep -c -e ' --detach ' "$log.args")" 1

run_gantry FAKE_PS_STATES=Running,Failed
check "gantry failed task exits 1" "$status" 1
check "gantry failed task prints the job logs" "$(grep -c '^gantry-log-line$' "$work/out")" 1
check "gantry failed task removes the job" "$(grep -c '^service rm$' "$log")" 1

run_gantry FAKE_PS_STATES=Rejected
check "gantry rejected task exits 1" "$status" 1
check "gantry rejected task removes the job" "$(grep -c '^service rm$' "$log")" 1

run_gantry FAKE_PS_STATES=Running,Shutdown
check "gantry shutdown task exits 1" "$status" 1

run_gantry FAKE_PS_STATES=Running GANTRY_JOB_DEADLINE=10 GANTRY_JOB_POLL=5
check "gantry deadline exits 2" "$status" 2
check "gantry deadline says the result is unknown" \
  "$(grep -c '^Gantry still running after 10 s; result unknown$' "$work/out")" 1
check "gantry deadline names the job it left running" "$(grep -c '^Gantry job gantry-.* left running$' "$work/out")" 1
check "gantry deadline does not remove the job" "$(grep -c '^service rm$' "$log")" 0
check "gantry deadline does not read the logs" "$(grep -c '^service logs$' "$log")" 0

run_gantry FAKE_CREATE_RC=3 FAKE_PS_STATES=Complete
check "gantry create failure keeps the create exit code" "$status" 3
check "gantry create failure does not poll" "$(grep -c '^service ps$' "$log")" 0

run_gantry FAKE_PS_STATES=Complete FAKE_LOGS_RC=1 FAKE_RM_RC=1
check "log and rm failure do not hide success" "$status" 0

run_gantry FAKE_PS_STATES=Failed FAKE_LOGS_RC=1 FAKE_RM_RC=1
check "log and rm failure do not hide the failure" "$status" 1

if [ "$failures" -gt 0 ]; then
  printf '%s check(s) failed\n' "$failures"
  exit 1
fi
echo "all checks passed"
