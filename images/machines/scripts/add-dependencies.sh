#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT add-dependencies.sh: $1"
}

logger "Executing"

DEBIAN_FRONTEND=noninteractive

logger "Update the box"
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
