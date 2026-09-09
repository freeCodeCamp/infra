#!/usr/bin/env bash
set -uo pipefail

if [[ $# -lt 1 ]]; then
  printf 'usage: FIRE_AT=<epoch> [TRIES=n] [INTERVAL=s] %s <gate-script>\n' "${0##*/}" >&2
  exit 2
fi
GATE="$1"
[[ -x "$GATE" ]] || {
  printf 'not executable: %s\n' "$GATE" >&2
  exit 2
}
: "${FIRE_AT:?FIRE_AT (epoch seconds) is required}"
TRIES="${TRIES:-5}"
INTERVAL="${INTERVAL:-420}"
LAST=$((FIRE_AT + INTERVAL * (TRIES - 1)))

printf '%s armed — first check %s, then every %ss, last %s (%s tries)\n' \
  "${GATE##*/}" "$(date -u -r "$FIRE_AT" +%FT%TZ)" "$INTERVAL" \
  "$(date -u -r "$LAST" +%FT%TZ)" "$TRIES"

while :; do
  REMAIN=$(($(date -u +%s) - FIRE_AT))
  ((REMAIN >= 0)) && break
  sleep $((REMAIN < -300 ? 300 : -REMAIN))
done

OUT=""
CODE=3
for ((i = 1; i <= TRIES; i++)); do
  OUT="$("$GATE" 2>&1)"
  CODE=$?
  if [[ "$CODE" != "3" ]]; then
    printf '%s\n' "$OUT"
    exit "$CODE"
  fi
  ((i < TRIES)) && sleep "$INTERVAL"
done

printf '%s\n' "$OUT"
printf '%s gave up after %s tries — still PENDING at %s\n' \
  "${GATE##*/}" "$TRIES" "$(date -u +%FT%TZ)"
exit 3
