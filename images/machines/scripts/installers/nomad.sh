#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT nomad.sh: $1"
}

logger "Executing"
export DEBIAN_FRONTEND=noninteractive

logger "Adding Hashicorp apt keys"
cd /tmp
curl --fail --silent --show-error --location https://apt.releases.hashicorp.com/gpg |
  gpg --dearmor |
  sudo dd of=/usr/share/keyrings/hashicorp-archive-keyring.gpg

FILE=/etc/apt/sources.list.d/hashicorp.list
if test -f "$FILE"; then
  logger "Warn: sources list $FILE already exists. Skipping sources configuration."
else
  logger "Info: sources list $FILE does not exit. Configuring sources."
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" |
    sudo tee -a /etc/apt/sources.list.d/hashicorp.list >/dev/null
fi

logger "Installing Nomad"
export NOMAD_VERSION="1.4.4-1"
sudo apt-get update
sudo apt-get install -y nomad=$NOMAD_VERSION

logger "Checking Nomad version"
nomad version

logger "Completed"
