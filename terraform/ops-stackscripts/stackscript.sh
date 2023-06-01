#!/bin/sh
# <UDF name="userdata" label="user-data file contents (base64 encoded)" />
set +e +x
FILE_USERDATA="/var/lib/cloud/seed/nocloud-net/user-data"
FILE_METADATA="/var/lib/cloud/seed/nocloud-net/meta-data"
# vendor-data and network-config are optional

echo "Configuring cloud-init..."
echo "set cloud-init/datasources NoCloud" | debconf-communicate
mkdir -p /etc/cloud/cloud.cfg.d /var/lib/cloud/seed/nocloud-net/

if [ -n "$LINODE_ID" ]; then
cat > /etc/cloud/cloud.cfg.d/01-instanceid.cfg <<'EOS'
datasource:
  NoCloud:
    meta-data:
       instance-id: linode$LINODE_ID
EOS
fi

cat > /etc/cloud/cloud.cfg.d/99-warnings.cfg <<'EOS'
#cloud-config
warnings:
  dsid_missing_source: off
EOS

UMASK=$(umask)
umask 0066
echo "Creating $FILE_METADATA..."
touch "${FILE_METADATA}"

echo "Creating $FILE_USERDATA..."
touch "${FILE_USERDATA}"
echo "${USERDATA}" | base64 -d > "${FILE_USERDATA}"
umask "${UMASK}"

echo "Installing cloud-init..."
apt-get -q=2 update
apt-get -q=2 install -y cloud-init

echo "Running cloud-init... (init, config, and final)"
cloud-init init
cloud-init modules --mode=config
cloud-init modules --mode=final
