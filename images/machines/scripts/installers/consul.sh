#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT consul.sh: $1"
}

logger "Executing"

export DEBIAN_FRONTEND=noninteractive
cd /tmp

logger "Installing Consul"

export CONSUL_VERSION="1.8.0"

curl -fsL -o /tmp/consul.zip \
  https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip

unzip -o /tmp/consul.zip -d /usr/local/bin
chmod 0755 /usr/local/bin/consul
chown root:root /usr/local/bin/consul

logger "Configuring Consul"

# User config
useradd --system --home /etc/consul.d --shell /bin/false consul
mkdir --parents /opt/consul
chown --recursive consul:consul /opt/consul

logger "Checking Consul version"
consul version

logger "Completed"
