#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
rules=${RULES:-$here/../cluster/victoria-logs/vmrule-logs.yaml}
image=victoriametrics/victoria-logs:v1.53.0
names='NginxUpstreamDown NginxGatewayErrors'

windows='stg-outage|2026-11-13T15:20:00Z|2026-11-13T16:20:00Z|fire
prd-api-client-deploy|2026-11-20T10:28:00Z|2026-11-20T10:46:00Z|silent
prd-news-rollout|2026-11-20T15:40:00Z|2026-11-20T15:46:00Z|silent
prd-rollout-heartbeat|2026-11-20T03:40:00Z|2026-11-20T04:00:00Z|silent'

expr_of() {
  yq -e ".spec.groups[].rules[] | select(.alert == \"$1\") | .expr" "$rules"
}

for name in $names; do
  if ! expr_of "$name" >/dev/null 2>&1; then
    echo "FAIL rule $name is missing from $rules" >&2
    exit 1
  fi
done

cid=$(docker run -d --rm -p 127.0.0.1::9428 "$image" -retentionPeriod=100y)
trap 'docker stop "$cid" >/dev/null' EXIT
port=$(docker port "$cid" 9428/tcp | head -n 1)
url=http://127.0.0.1:${port##*:}

for _ in $(seq 60); do
  curl -sf "$url/health" >/dev/null && break
  sleep 0.5
done
curl -sf "$url/health" >/dev/null

epoch() { jq -rn --arg t "$1" '$t | fromdateiso8601'; }

fail=0
while IFS='|' read -r fixture from to want; do
  file=$here/fixtures/$fixture.jsonl
  if grep -qE '(^|[^0-9.])(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+' "$file"; then
    echo "FAIL $fixture holds a private address; use 198.51.100.0/24"
    fail=1
    continue
  fi
  curl -sf -H 'Content-Type: application/stream+json' --data-binary "@$file" \
    "$url/insert/jsonline?_stream_fields=env,host,role,level,server_name&_time_field=_time"
  curl -sf -X POST "$url/internal/force_flush" >/dev/null
  lines=$(wc -l <"$file" | tr -d ' ')
  loaded=$(curl -sf "$url/select/logsql/query" \
    --data-urlencode "query=_time:[$from, $to) | stats count() as n" | jq -r '.n')
  if [ "$loaded" != "$lines" ]; then
    echo "FAIL $fixture loaded $loaded of $lines lines"
    fail=1
    continue
  fi

  start=$(epoch "$from")
  end=$(($(epoch "$to") + 300))
  for name in $names; do
    expr=$(expr_of "$name")
    fired=0
    peak=0
    t=$start
    while [ "$t" -le "$end" ]; do
      n=$(curl -sf "$url/select/logsql/stats_query" \
        --data-urlencode "query=$expr" --data-urlencode "time=$t" |
        jq '.data.result | length')
      t=$((t + 60))
      if [ "$n" -gt 0 ]; then
        fired=$((fired + 1))
      fi
      if [ "$n" -gt "$peak" ]; then
        peak=$n
      fi
    done
    got=silent
    [ "$fired" -gt 0 ] && got=fire
    verdict=PASS
    [ "$got" = "$want" ] || {
      verdict=FAIL
      fail=1
    }
    printf '%s %-22s %-19s want=%-6s got=%-6s minutes=%s peak_series=%s\n' \
      "$verdict" "$fixture" "$name" "$want" "$got" "$fired" "$peak"
  done
done <<<"$windows"
exit "$fail"
