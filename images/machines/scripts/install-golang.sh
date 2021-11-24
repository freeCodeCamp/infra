#!/bin/bash
set -e

logger() {
  DT=$(date '+%Y/%m/%d %H:%M:%S')
  echo "$DT go.sh: $1"
}

logger "Executing"

DEBIAN_FRONTEND=noninteractive

cd /tmp

GOVERSION=1.6
GODOWNLOAD=https://storage.googleapis.com/golang/go${GOVERSION}.linux-amd64.tar.gz
PROFILE=/etc/profile
GODIR=/usr/local
GOROOT=$GODIR/go
GOPATH=/opt/go

export GOROOT=$GOROOT
export GOPATH=$GOPATH
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

logger "Fetching Go"
curl -L $GODOWNLOAD > go.tar.gz

logger "Installing Go"
tar -C $GODIR -xzf go.tar.gz
chmod 0755 $GOROOT
chown root:root $GOROOT

logger "Configuring Go"
cat <<EOF >>${PROFILE}

export GOROOT=$GOROOT
export GOPATH=$GOPATH
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
EOF

mkdir -p "$GOPATH/bin"
chmod 0755 $GOPATH/bin
chown root:root $GOPATH/bin

logger "Completed"
