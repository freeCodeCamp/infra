#!/usr/bin/env bash
set -euo pipefail

allowlist=.github/leak-allowlist.txt
octet='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
ipv4="${octet}(\.${octet}){3}(/[0-9]{1,2})?"
tailnet='[a-z0-9-]+(\.[a-z0-9-]+)*\.ts\.net'

allow_paths=()
allow_patterns=()
failures=0
while IFS= read -r entry || [ -n "$entry" ]; do
  [ -n "$entry" ] || continue
  path=${entry%%|*}
  tail=${entry#*|}
  pattern=${tail%|*}
  reason=${tail##*|}
  if [ "$path" = "$entry" ] || [ "$pattern" = "$tail" ] || [ -z "$path" ] || [ -z "$pattern" ] || [ -z "$reason" ]; then
    echo "${allowlist}: each line needs a path, a pattern and a reason"
    failures=$((failures + 1))
    continue
  fi
  allow_paths+=("$path")
  allow_patterns+=("$pattern")
done <"$allowlist"

is_allowed() {
  local path=$1 value=$2 i
  for i in "${!allow_paths[@]}"; do
    if [ "${allow_paths[$i]}" = "$path" ] && printf '%s\n' "$value" | grep -qxE -- "${allow_patterns[$i]}"; then
      return 0
    fi
  done
  return 1
}

ipv4_class() {
  local a b c
  IFS=. read -r a b c _ <<<"${1%%/*}"
  if [ "$a" = 10 ]; then
    echo private-10
  elif [ "$a" = 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; then
    echo private-172
  elif [ "$a" = 192 ] && [ "$b" = 168 ]; then
    echo private-192
  elif [ "$a" = 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ]; then
    echo cgnat-100
  elif [ "$a" = 0 ] || [ "$a" = 127 ] || [ "$a" -ge 224 ] || { [ "$a" = 169 ] && [ "$b" = 254 ]; }; then
    echo reserved
  elif { [ "$a" = 192 ] && [ "$b" = 0 ] && [ "$c" = 2 ]; } || { [ "$a" = 198 ] && [ "$b" = 51 ] && [ "$c" = 100 ]; } || { [ "$a" = 203 ] && [ "$b" = 0 ] && [ "$c" = 113 ]; }; then
    echo documentation
  else
    echo public-ipv4
  fi
}

report() {
  local path=$1 line=$2 class=$3 value=$4
  if ! is_allowed "$path" "$value"; then
    echo "${path}:${line}: ${class}"
    failures=$((failures + 1))
  fi
}

scan() {
  local kind=$1 pattern=$2 status=0 hits hit path rest line text values value class
  hits=$(git grep -nIiE -e "$pattern" -- . ":!${allowlist}") || status=$?
  if [ "$status" -gt 1 ]; then
    echo "git grep failed for ${kind}"
    exit 2
  fi
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path=${hit%%:*}
    rest=${hit#*:}
    line=${rest%%:*}
    text=${rest#*:}
    if [ "$kind" = ipv4 ]; then
      values=$(printf '%s\n' "$text" | grep -oE '[0-9][0-9./]*' | sed -E 's#[./]+$##' | grep -xE -- "$pattern" || true)
    else
      values=$(printf '%s\n' "$text" | grep -oiE -- "$pattern" || true)
    fi
    while IFS= read -r value; do
      [ -n "$value" ] || continue
      if [ "$kind" = ipv4 ]; then
        class=$(ipv4_class "$value")
        case $class in
        reserved | documentation) continue ;;
        esac
      else
        class='tailnet-name'
      fi
      report "$path" "$line" "$class" "$value"
    done <<<"$values"
  done <<<"$hits"
}

scan tailnet "$tailnet"
scan ipv4 "$ipv4"

echo "leak check: ${failures} hit(s)"
[ "$failures" = 0 ]
