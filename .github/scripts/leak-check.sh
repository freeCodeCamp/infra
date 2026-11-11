#!/usr/bin/env bash
set -euo pipefail

allowlist=.github/leak-allowlist.txt
octet='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
cidr='(/[0-9]{1,2})?'
classes=(
  "tailnet-name;name;[a-z0-9-]+(\.[a-z0-9-]+)*\.ts\.net"
  "fleet-domain;name;([a-z0-9-]+\.)*freecodecamp\.net"
  "private-10;ip;10(\.${octet}){3}${cidr}"
  "private-172;ip;172\.(1[6-9]|2[0-9]|3[01])(\.${octet}){2}${cidr}"
  "private-192;ip;192\.168(\.${octet}){2}${cidr}"
  "cgnat-100;ip;100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])(\.${octet}){2}${cidr}"
)

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

for entry in "${classes[@]}"; do
  IFS=';' read -r class kind pattern <<<"$entry"
  status=0
  hits=$(git grep -nIiE -e "$pattern" -- . ":!${allowlist}") || status=$?
  if [ "$status" -gt 1 ]; then
    echo "git grep failed for ${class}"
    exit 2
  fi
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path=${hit%%:*}
    rest=${hit#*:}
    line=${rest%%:*}
    text=${rest#*:}
    if [ "$kind" = ip ]; then
      values=$(printf '%s\n' "$text" | grep -oE '[0-9][0-9./]*' | sed -E 's#[./]+$##' | grep -xE -- "$pattern" || true)
    else
      values=$(printf '%s\n' "$text" | grep -oiE -- "$pattern" || true)
    fi
    while IFS= read -r value; do
      [ -n "$value" ] || continue
      if ! is_allowed "$path" "$value"; then
        echo "${path}:${line}: ${class}"
        failures=$((failures + 1))
      fi
    done <<<"$values"
  done <<<"$hits"
done

echo "leak check: ${failures} hit(s)"
[ "$failures" = 0 ]
