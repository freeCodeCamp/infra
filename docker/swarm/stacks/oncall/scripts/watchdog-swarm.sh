#!/bin/sh
set -u

here=$(dirname "$0")
. "$here/lib.sh"

now=${WATCHDOG_NOW:-$(date -u +%s)}
maintenance_end_hour=6
second_read_delay=60

if in_window "$now" "$maintenance_end_hour"; then
  printf 'watchdog: maintenance window, nothing checked\n'
  exit 0
fi

if findings=$(sh "$here/swarm-check.sh"); then
  printf 'watchdog: swarm healthy\n'
  exit 0
fi

sleep "$second_read_delay"

if findings=$(sh "$here/swarm-check.sh"); then
  printf 'watchdog: swarm recovered on the second read\n'
  exit 0
fi

summary=$(printf '%s\n' "$findings" | awk 'NR > 1 { printf "; " } { printf "%s", $0 }')
chat_notify fail watchdog swarm "$summary"
printf 'watchdog: %s\n' "$summary" >&2
exit 1
