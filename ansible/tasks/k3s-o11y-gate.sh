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

workloads_out=$(k3s kubectl -n "$namespace" get deployments,statefulsets,daemonsets -o jsonpath='{range .items[*]}{.kind}{"|"}{.metadata.name}{"|"}{.spec.replicas}{"|"}{.status.readyReplicas}{"|"}{.status.desiredNumberScheduled}{"|"}{.status.numberReady}{"\n"}{end}') ||
  reasons+=("kubectl failed: get workloads")
while read -r workload; do
  [ -n "$workload" ] && reasons+=("not ready: $workload")
done < <(awk -F'|' '
  NF >= 6 {
    desired = ($1 == "DaemonSet") ? $5 : $3
    ready = ($1 == "DaemonSet") ? $6 : $4
    if (ready + 0 != desired + 0) print $1 "/" $2 " " ready + 0 "/" desired + 0
  }' <<<"$workloads_out")

cutoff=$(date -u -d '-15 min' +%Y-%m-%dT%H:%M:%SZ)
pods_out=$(k3s kubectl -n "$namespace" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.ownerReferences[*].kind}{"|"}{range .status.containerStatuses[*]}{.lastState.terminated.finishedAt}{","}{end}{"\n"}{end}') ||
  reasons+=("kubectl failed: get pods")
while read -r pod; do
  [ -n "$pod" ] && reasons+=("restarted: $pod")
done < <(awk -F'|' -v cutoff="$cutoff" '
  $2 !~ /Job/ {
    n = split($3, times, ",")
    for (i = 1; i <= n; i++) {
      if (times[i] != "" && times[i] >= cutoff) {
        print $1
        break
      }
    }
  }' <<<"$pods_out")

if [ "${#reasons[@]}" -eq 0 ]; then
  echo "gate ok"
  exit 0
fi
printf '%s\n' "${reasons[@]}"
exit 1
