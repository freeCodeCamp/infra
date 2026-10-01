#!/bin/sh
set -u

. "$(dirname "$0")/lib.sh"

case "${RELAY_TYPE:-}" in
success | info) status=ok ;;
failure) status=fail ;;
*) status=warn ;;
esac

summary=$(printf '%s\n' "${RELAY_BODY:-}" |
  awk 'NF && $0 != "No services updated." { s = s (s == "" ? "" : "; ") $0 } END { print s }')
[ -n "$summary" ] || summary=$(printf '%s' "${RELAY_TITLE:-empty notice}" | sed 's/^\[[^]]*\] //')

chat_notify "$status" gantry "${RELAY_TRIGGER:-update}" "$summary"
