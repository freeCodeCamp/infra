#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT nginx.sh: $1"
}

logger "Executing"

export DEBIAN_FRONTEND=noninteractive

logger "Update the box"
apt-get -y update
apt-get -y upgrade

logger "Install Nginx"

apt-get -y install nginx

logger "Configure Nginx"