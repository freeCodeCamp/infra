#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT nomad.sh: $1"
}

logger "Executing"

DEBIAN_FRONTEND=noninteractive


logger "Installing Nomad"

NOMAD_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/nomad | jq -r .current_version)
curl --silent --remote-name https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip
unzip -qq "nomad_${NOMAD_VERSION}_linux_amd64.zip"
sudo chown root:root nomad
sudo mv nomad /usr/local/bin/
nomad version
rm -f "nomad_${NOMAD_VERSION}_linux_amd64.zip"


logger "Completed"
