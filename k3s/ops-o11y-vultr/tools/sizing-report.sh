#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: VM_URL=<prometheus API base> [RANGE=30d] [JOB=node] sizing-report.sh [out.md]

Writes per-role p95 and peak CPU, memory, disk and network to markdown.
VM_URL   e.g. http://127.0.0.1:8481/select/0/prometheus
         or   http://<o11y node>:30427/select/0/prometheus with VM_USER and VM_PASSWORD
RANGE    look-back window: <n>m, <n>h, <n>d or <n>w (default 30d)
JOB      scrape job of the hosts (default node)
EOF
  exit 2
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage
[ -n "${VM_URL:-}" ] || usage
RANGE=${RANGE:-30d}
JOB=${JOB:-node}
OUT=${1:-/dev/stdout}
[[ $RANGE =~ ^[0-9]+[mhdw]$ ]] || {
  echo "RANGE must look like 30d, got '$RANGE'" >&2
  exit 2
}
[[ $JOB =~ ^[a-z0-9_-]+$ ]] || {
  echo "JOB must be a plain job name, got '$JOB'" >&2
  exit 2
}

query() {
  local auth=""
  if [ -n "${VM_USER:-}" ]; then
    : "${VM_PASSWORD:?VM_PASSWORD is required with VM_USER}"
    local u=${VM_USER//\\/\\\\} p=${VM_PASSWORD//\\/\\\\}
    u=${u//\"/\\\"}
    p=${p//\"/\\\"}
    auth=$(printf 'user = "%s:%s"\n' "$u" "$p")
  fi
  printf '%s\n' "$auth" |
    curl -fsS --max-time 120 -K - --get --data-urlencode "query=$1" "$VM_URL/api/v1/query" |
    jq -e --arg col "$2" '
      if .status != "success" then error("query failed") else . end
      | [.data.result[]
         | {key: "\(.metric.env // "untagged")|\(.metric.role // "untagged")", col: $col,
            v: (.value[1] | tonumber | if isinfinite or isnan then null else . end)}]'
}

sel="job=\"$JOB\""
cpu="1 - avg by (env, role, instance) (rate(node_cpu_seconds_total{$sel,mode=\"idle\"}[5m]))"
fs="$sel,mountpoint=\"/\""
mem() {
  echo "1 - $1 node_memory_MemAvailable_bytes{$sel}[$RANGE]) / node_memory_MemTotal_bytes{$sel}"
}
disk() {
  echo "1 - $1 node_filesystem_avail_bytes{$fs}[$RANGE]) / node_filesystem_size_bytes{$fs}"
}
nic="$sel,device=~\"eth.*|en.*\""
rx="sum by (env, role, instance) (rate(node_network_receive_bytes_total{$nic}[5m])) * 8 / 1e6"
tx="sum by (env, role, instance) (rate(node_network_transmit_bytes_total{$nic}[5m])) * 8 / 1e6"

p95() { echo "max by (env, role) (quantile_over_time(0.95, ($1)[$RANGE:5m]))"; }
peak() { echo "max by (env, role) (max_over_time(($1)[$RANGE:5m]))"; }

vcpu="count by (env, role, instance) (node_cpu_seconds_total{$sel,mode=\"idle\"})"
all=$(query "count by (env, role) (up{$sel})" hosts)
all+=$(query "max by (env, role) ($vcpu)" vcpu)
all+=$(query "max by (env, role) (node_memory_MemTotal_bytes{$sel}) / 2^30" mem_gib)
for pair in "cpu=$cpu" "rx=$rx" "tx=$tx"; do
  name=${pair%%=*}
  expr=${pair#*=}
  all+=$(query "$(p95 "$expr")" "${name}_p95")
  all+=$(query "$(peak "$expr")" "${name}_peak")
done
for name in mem disk; do
  all+=$(query "max by (env, role) ($($name 'quantile_over_time(0.05,'))" "${name}_p95")
  all+=$(query "max by (env, role) ($($name 'min_over_time('))" "${name}_peak")
done
rows=$(jq -s 'add | group_by(.key)
  | map(. as $g | reduce $g[] as $r ({key: $g[0].key}; .[$r.col] = $r.v))' <<<"$all")

{
  echo "# Per-role sizing"
  echo
  echo "Range: $RANGE. Job: $JOB. Generated: $(date -u +%Y-%m-%dT%H:%MZ)."
  echo "Per role, each value is the worst host: the highest p95 and peak over the range."
  echo "CPU, memory and disk are percent used. Network is Mbit/s on the eth and en NICs."
  echo "CPU and network values are 5-minute averages; memory and disk use every sample."
  echo
  echo "| env | role | hosts | vCPU | mem GiB | CPU p95 | CPU peak | mem p95 | mem peak |" \
    "disk p95 | disk peak | rx p95 | rx peak | tx p95 | tx peak |"
  echo "|---|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|"
  jq -r '
    def n(d): if . == null then "n/a" else (. * pow(10; d) | round / pow(10; d) | tostring) end;
    def pct: if . == null then "n/a" else (. * 100 | n(1)) end;
    sort_by(.key)[]
    | (.key | split("|")) as [$env, $role]
    | [$env, $role, (.hosts | n(0)), (.vcpu | n(0)), (.mem_gib | n(1)),
       (.cpu_p95 | pct), (.cpu_peak | pct), (.mem_p95 | pct), (.mem_peak | pct),
       (.disk_p95 | pct), (.disk_peak | pct),
       (.rx_p95 | n(1)), (.rx_peak | n(1)), (.tx_p95 | n(1)), (.tx_peak | n(1))]
    | "| " + join(" | ") + " |"' <<<"$rows"
} >"$OUT"
