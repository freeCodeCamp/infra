#!/usr/bin/env bash
set -u -o pipefail

expected_nodes="${1:?expected node count}"
expected_vmstorage="${2:?expected vmstorage count}"
namespace="${3:-o11y}"

reasons=()

nodes_out=$(k3s kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{" "}{.spec.unschedulable}{"\n"}{end}') ||
  reasons+=("kubectl failed: get nodes")
ready_nodes=$(awk '$2 == "True" { n++ } END { print n + 0 }' <<<"$nodes_out")
if [ "$ready_nodes" -ne "$expected_nodes" ]; then
  reasons+=("nodes ready $ready_nodes/$expected_nodes")
fi
while read -r name; do
  [ -n "$name" ] && reasons+=("cordoned: $name")
done < <(awk '$3 == "true" { print $1 }' <<<"$nodes_out")

etcd_out=$(k3s kubectl get --raw=/readyz/etcd) ||
  reasons+=("kubectl failed: get etcd")
if [ "$etcd_out" != "ok" ]; then
  reasons+=("etcd not ok")
fi

vmstorage_out=$(k3s kubectl -n "$namespace" get pods -l app.kubernetes.io/name=vmstorage -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}') ||
  reasons+=("kubectl failed: get vmstorage pods")
ready_vmstorage=$(awk '$2 == "True" { n++ } END { print n + 0 }' <<<"$vmstorage_out")
if [ "$ready_vmstorage" -ne "$expected_vmstorage" ]; then
  reasons+=("vmstorage ready $ready_vmstorage/$expected_vmstorage")
fi

if [ "${#reasons[@]}" -eq 0 ]; then
  echo "gate ok"
  exit 0
fi
printf '%s\n' "${reasons[@]}"
exit 1
