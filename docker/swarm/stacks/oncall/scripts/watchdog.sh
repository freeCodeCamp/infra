#!/bin/sh
set -eu

. "$(dirname "$0")/lib.sh"

feed=${WATCHDOG_FEED_URL:-https://www.freecodecamp.org/news/rss.xml}
runs=https://github.com/freeCodeCamp/news/actions/workflows/deploy-eng.yml
limit=18000
remind=21600
tick=3600
quiet_until=8
now=${WATCHDOG_NOW:-$(date -u +%s)}
now=$((now - now % 60))

rfc822_epoch() {
  printf '%s\n' "$1" | awk '
    NF != 6 || $2 !~ /^[0-9][0-9]?$/ || $4 !~ /^[0-9][0-9][0-9][0-9]$/ { exit 1 }
    $5 !~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ || $6 !~ /^[+-][0-9][0-9][0-9][0-9]$/ { exit 1 }
    {
      m = index("JanFebMarAprMayJunJulAugSepOctNovDec", $3)
      if (length($3) != 3 || m == 0 || (m - 1) % 3 != 0) exit 1
      mon = (m + 2) / 3
      y = $4 - (mon <= 2)
      days = 365 * y + int(y / 4) - int(y / 100) + int(y / 400)
      days += int((153 * ((mon + 9) % 12) + 2) / 5) + $2 - 719469
      split($5, t, ":")
      off = substr($6, 2, 2) * 3600 + substr($6, 4, 2) * 60
      if (substr($6, 1, 1) == "-") off = -off
      printf "%.0f\n", days * 86400 + t[1] * 3600 + t[2] * 60 + t[3] - off
    }'
}

unreadable() {
  chat_post "🔴 news watchdog · feed unreadable
$feed
$1"
  printf 'watchdog: feed unreadable, %s\n' "$1" >&2
  exit 1
}

if in_window "$now" "$quiet_until"; then
  printf 'watchdog: quiet hours, nothing checked\n'
  exit 0
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
code=$(curl -s -o "$body" -w '%{http_code}' --max-time 30 --retry 2 "$feed" || true)
[ "$code" = 200 ] || unreadable "HTTP ${code:-000}"

stamp=$(sed -n 's:.*<lastBuildDate>\(.*\)</lastBuildDate>.*:\1:p' "$body" | head -n 1)
[ -n "$stamp" ] || unreadable "no lastBuildDate"
built=$(rfc822_epoch "$stamp") || unreadable "lastBuildDate '$stamp' is not RFC 822"

age=$((now - built))
[ "$age" -ge $((-tick)) ] || unreadable "lastBuildDate '$stamp' is in the future"

if [ "$age" -le "$limit" ]; then
  printf 'watchdog: fresh, last build %s\n' "$stamp"
  exit 0
fi

if [ $(((age - limit - 1) % remind)) -lt "$tick" ] || in_window $((now - tick)) "$quiet_until"; then
  chat_post "🔴 news stale · English
last build $stamp, $((age / 3600))h $((age % 3600 / 60))m ago (limit $((limit / 3600))h)
$feed
$runs"
fi
printf 'watchdog: stale, last build %s\n' "$stamp" >&2
exit 1
