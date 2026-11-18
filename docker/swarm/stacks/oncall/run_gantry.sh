#!/bin/sh
set -eu

launch_new_gantry() {
  local service_name="gantry-$(date +%s)-$$"
  rc=0
  elapsed=0
  docker service create \
    --name "${service_name}" \
    --mode replicated-job \
    --restart-condition none \
    --detach \
    --constraint "node.role==manager" \
    --network oncall_default \
    --env "GANTRY_NODE_NAME=$(hostname)" \
    --env "GANTRY_SLEEP_SECONDS=0" \
    --env "GANTRY_LOG_LEVEL=INFO" \
    --env "GANTRY_SERVICES_FILTERS=${GANTRY_SERVICES_FILTERS:-}" \
    --env "GANTRY_SERVICES_EXCLUDED=${GANTRY_SERVICES_EXCLUDED:-}" \
    --env "GANTRY_SERVICES_EXCLUDED_FILTERS=${GANTRY_SERVICES_EXCLUDED_FILTERS:-}" \
    --env "GANTRY_UPDATE_NUM_WORKERS=3" \
    --env "GANTRY_MANIFEST_NUM_WORKERS=5" \
    --env "GANTRY_MANIFEST_CMD=buildx" \
    --env "GANTRY_CLEANUP_IMAGES=true" \
    --env "GANTRY_ROLLBACK_ON_FAILURE=true" \
    --env "GANTRY_UPDATE_TIMEOUT_SECONDS=300" \
    --env "GANTRY_UPDATE_OPTIONS=--with-registry-auth" \
    --env "GANTRY_NOTIFICATION_APPRISE_URL=http://svc-chat-relay:9000/hooks/gantry?trigger=webhook" \
    --env "GANTRY_NOTIFICATION_CONDITION=on-change" \
    --label "from-webhook=true" \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount type=bind,source=/home/freecodecamp/.docker,target=/root/.docker \
    shizunge/gantry:2026.0415.1 || return "$?"
  while :; do
    state=$(docker service ps "${service_name}" --format '{{.CurrentState}}' || true)
    case "${state}" in
    Complete*) break ;;
    Failed* | Rejected* | Shutdown*)
      rc=1
      break
      ;;
    esac
    if [ "${elapsed}" -ge "${GANTRY_JOB_DEADLINE:-330}" ]; then
      echo "Gantry still running after ${GANTRY_JOB_DEADLINE:-330} s; result unknown" >&2
      echo "Gantry job ${service_name} left running" >&2
      return 2
    fi
    sleep "${GANTRY_JOB_POLL:-5}"
    elapsed=$((elapsed + ${GANTRY_JOB_POLL:-5}))
  done
  docker service logs --raw "${service_name}" || true
  docker service rm "${service_name}" || true
  return "${rc}"
}

main() {
  launch_new_gantry "${@}"
}

main "${@}"
