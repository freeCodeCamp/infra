#!/bin/sh
# workaround: https://github.com/moby/moby/issues/49555
set -u

. "$(dirname "$0")/lib.sh"

net_dir=${WATCHDOG_NET_DIR:-/sys/class/net}
second_read_delay=5

strays() {
  printf '%s\n' "$net_dir"/vx-* | sed 's|.*/||' | grep -E '^vx-[0-9a-f]{6}-[a-z0-9]{5}$'
}

if ! strays >/dev/null; then
  printf 'watchdog: no stray overlay device\n'
  exit 0
fi

sleep "$second_read_delay"

if ! found=$(strays); then
  printf 'watchdog: device was in transit\n'
  exit 0
fi

summary="stray overlay device $(printf '%s' "$found" | tr '\n' ' '). Delete it with ip link delete."
chat_notify fail watchdog "${NODE_NAME:-unknown node}" "$summary"
printf 'watchdog: %s\n' "$summary" >&2
exit 1
