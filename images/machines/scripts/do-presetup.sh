#!/bin/bash

set -e

echo "Waiting for cloud-init to update /etc/apt/sources.list"
timeout 180 /bin/bash -c \
  'until stat /var/lib/cloud/instance/boot-finished 2>/dev/null; do echo waiting ...; sleep 1; done'

# Disable interactive apt prompts
export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT do-presetup.sh: $1"
}

logger "Executing"

logger "Update the base operating system"
apt-get -y update
apt-get -y upgrade

logger "Install common dependencies"
apt-get -y install build-essential
apt-get -y install curl
apt-get -y install git
apt-get -y install jq
apt-get -y install software-properties-common
apt-get -y install tar
apt-get -y install unzip
apt-get -y install zip

logger "Completed"
