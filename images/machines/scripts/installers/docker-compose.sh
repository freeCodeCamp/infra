#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT docker-compose.sh: $1"
}

logger "Executing"

DEBIAN_FRONTEND=noninteractive
USER=$SSH_PROVISIONED_USER

logger "Installing Docker Compose"

# Use the latest version of Docker Compose v2.x.x - thus allowing us to use commands like: 
#
# docker compose up -d
#
mkdir -p ~/.docker/cli-plugins/
curl -sSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
docker compose version

# Below is if you want to use Docker Compose v1.x.x - which allows us to use commands like:
#
# docker-compose up -d
#

# curl -L https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "tag_name" | cut -d \" -f4)/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
# chmod +x /usr/local/bin/docker-compose

logger "Completed"
