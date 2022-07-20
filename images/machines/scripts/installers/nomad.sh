#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT nomad.sh: $1"
}

logger "Executing"

export DEBIAN_FRONTEND=noninteractive
cd /tmp

logger "Installing Nomad"

export NOMAD_VERSION="1.1.0"

curl -fsL -o /tmp/nomad.zip \
  https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip

unzip -o /tmp/nomad.zip -d /usr/local/bin
chmod 0755 /usr/local/bin/nomad
chown root:root /usr/local/bin/nomad

logger "Configuring Nomad"

# User config
useradd --system --home /etc/nomad.d --shell /bin/false nomad
mkdir --parents /opt/nomad
chown --recursive nomad:nomad /opt/nomad

# Sytemd config
# cp \
#   /tmp/nomad/nomad.service \
#   /etc/systemd/system/nomad.service # : <---- PreUpload

# Common config
mkdir --parents /etc/nomad.d
chmod 700 /etc/nomad.d
cp \
  /tmp/nomad/nomad.hcl \
  /etc/nomad.d/nomad.hcl # : <---- PreUpload

logger "Checking Consul version"
nomad version

logger "Completed"

# Footnotes:
#
#     [1]
#     Copy configurations for servers and clients during provisioning.
#
#     /etc/nomad.d/server.hcl
#     /etc/nomad.d/client.hcl
#
#     [2]
#     Services can be started with:
#
#     systemctl enable nomad
#     systemctl start  nomad
#     systemctl status nomad
#
#
#     [3]
#     Files marked with ": <---- PreUpload" are uploaded
#     as a part of the build.
