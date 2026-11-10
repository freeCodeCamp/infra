#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: alert-drill.sh --dry-run|--send [rule-file ...]

Sends one test alert for each rule through Alertmanager. Each alert is marked
DRILL and ends by itself after 15 minutes. The Watchdog rule is left out.
--dry-run  print the alert names and send nothing
--send     send the alerts
With no rule file, it reads every rule file of the cluster.
EOF
  exit 2
}

[ $# -ge 1 ] || usage
MODE=$1
shift
case "$MODE" in
--dry-run | --send) ;;
*) usage ;;
esac

ROOT=$(git rev-parse --show-toplevel)
KUBECONFIG=${KUBECONFIG:-$ROOT/k3s/ops-o11y-vultr/.kubeconfig.yaml}
export KUBECONFIG
[ $# -ge 1 ] || set -- "$ROOT"/k3s/ops-o11y-vultr/cluster/*/vmrule-*.yaml

RULES=$(yq -o=json -I=0 '[.spec.groups[].rules[] | select(.alert and .alert != "Watchdog") | {"alert": .alert, "severity": .labels.severity, "runbook_url": .annotations.runbook_url}]' "$@" | jq -cs 'add')
if [ "$(jq length <<<"$RULES")" -eq 0 ]; then
  echo "no alert rules in: $*" >&2
  exit 1
fi
ENDS_AT=$(date -u -v+15M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+15 minutes' +%Y-%m-%dT%H:%M:%SZ)
PAYLOAD=$(jq -c --arg ends "$ENDS_AT" 'map({
  labels: {alertname: "DRILL-\(.alert)", severity: .severity, drill: "true"},
  annotations: {summary: "DRILL: test alert for \(.alert). No action needed.", runbook_url: .runbook_url},
  endsAt: $ends
})' <<<"$RULES")

if [ "$MODE" = "--dry-run" ]; then
  jq -r '.[].labels | "\(.alertname)\t\(.severity)"' <<<"$PAYLOAD"
  exit 0
fi

URL=http://127.0.0.1:19093
kubectl -n o11y port-forward svc/vmalertmanager-vm 19093:9093 >/dev/null &
FORWARD=$!
trap 'kill "$FORWARD" 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do
  curl -fs --max-time 1 -o /dev/null "$URL/-/ready" && break
  sleep 0.5
done
if ! kill -0 "$FORWARD" 2>/dev/null; then
  echo "kubectl port-forward stopped; port 19093 may be in use" >&2
  exit 1
fi
curl -fsS --max-time 10 -H 'Content-Type: application/json' -d "$PAYLOAD" "$URL/api/v2/alerts"
echo "sent $(jq length <<<"$PAYLOAD") test alerts; they end at $ENDS_AT"
