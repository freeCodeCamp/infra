#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT do-cleanup.sh: $1"
}

logger "Executing"

DEBIAN_FRONTEND=noninteractive

logger "Cleanup"
apt-get -y autoremove
apt-get -y autoclean
apt-get -y clean
apt-get -y purge

rm -rf /tmp/*
rm -rf /ops

logger "Completed"
