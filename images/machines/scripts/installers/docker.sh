#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT docker.sh: $1"
}

logger "Executing"
export DEBIAN_FRONTEND=noninteractive

logger "Adding Docker apt keys"
cd /tmp
curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg |
  gpg --dearmor |
  sudo dd of=/usr/share/keyrings/docker.gpg

FILE=/etc/apt/sources.list.d/docker.list
if test -f "$FILE"; then
  logger "Warn: sources list $FILE already exists. Skipping sources configuration."
else
  logger "Info: sources list $FILE does not exit. Configuring sources."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
fi

logger "Installing Docker"
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker

sh -c "echo \"DOCKER_OPTS='--dns 127.0.0.1 --dns 8.8.8.8 --dns-search service.consul'\" >> /etc/default/docker"

service docker restart

logger "Completed"
