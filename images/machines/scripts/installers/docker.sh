#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT docker.sh: $1"
}

logger "Executing"

export DEBIAN_FRONTEND=noninteractive

logger "Installing Docker"

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker

sh -c "echo \"DOCKER_OPTS='--dns 127.0.0.1 --dns 8.8.8.8 --dns-search service.consul'\" >> /etc/default/docker"

service docker restart

logger "Completed"
