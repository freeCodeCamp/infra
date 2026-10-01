#!/bin/sh
set -eu

launch_new_gantry() {
  local service_name="gantry-$(date +%s)-$$"
  docker service create \
    --name "${service_name}" \
    --mode replicated-job \
    --detach=false \
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
    --env "GANTRY_NOTIFICATION_APPRISE_URL=http://svc-apprise:8000/notify" \
    --env "GANTRY_NOTIFICATION_CONDITION=on-change" \
    --env "GANTRY_NOTIFICATION_TITLE=· webhook" \
    --label "from-webhook=true" \
    --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount type=bind,source=/home/freecodecamp/.docker,target=/root/.docker \
    shizunge/gantry:2025.0813.0
  local return_value=$?
  docker service logs --raw "${service_name}"
  docker service rm "${service_name}"
  return "${return_value}"
}

main() {
  launch_new_gantry "${@}"
}

main "${@}"
