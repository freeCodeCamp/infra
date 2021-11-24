#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT docker.sh: $1"
}

logger "Executing"

DEBIAN_FRONTEND=noninteractive
USER=$SSH_PROVISIONED_USER

logger "Installing Docker Compose"

mkdir -p ~/.docker/cli-plugins/
curl -sSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
docker compose version

logger "Completed"
