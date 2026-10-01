utc_clock() {
  date -u -d "@$1" '+%u %H' 2>/dev/null || date -u -r "$1" '+%u %H'
}

in_window() {
  clock=$(utc_clock "$1")
  case "${clock% *}" in
  3 | 6) [ "${clock#* }" -lt "${2:-6}" ] ;;
  *) return 1 ;;
  esac
}

ascii_excerpt() {
  head -c "$2" "$1" | LC_ALL=C tr -cd '\n\040-\176'
}

json_string() {
  printf '%s' "$1" |
    tr -d '\001-\011\013-\037' |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
    awk 'BEGIN { ORS = ""; print "\"" } NR > 1 { print "\\n" } { print } END { print "\"" }'
}

chat_post() {
  if [ -z "${GOOGLE_CHAT_WEBHOOK:-}" ]; then
    printf 'chat: GOOGLE_CHAT_WEBHOOK is empty, message not sent\n' >&2
    return 0
  fi
  chat_code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json; charset=UTF-8' \
    --max-time 30 --retry 2 \
    -d "{\"text\":$(json_string "$1")}" \
    "$GOOGLE_CHAT_WEBHOOK" || true)
  case "$chat_code" in
  2??) return 0 ;;
  esac
  printf 'chat: Google Chat rejected the message (HTTP %s)\n' "${chat_code:-000}" >&2
}

one_line() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '<>' | tr -s ' '
}

chat_notify() {
  case "$1" in
  ok) icon='✅' ;;
  warn) icon='⚠️' ;;
  *) icon='🔴' ;;
  esac
  text="$icon *$2* · $(one_line "$3") · $(one_line "$4")"
  [ -z "${5:-}" ] || text="$text · <$5|${6:-open}>"
  chat_post "$text"
}
