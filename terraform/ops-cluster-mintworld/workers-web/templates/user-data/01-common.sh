#!/bin/bash
set -euo pipefail

# Source the FCC logging script
if [[ -f "/usr/local/bin/fcc-logtool.sh" ]]; then
  source "/usr/local/bin/fcc-logtool.sh"
else
  echo "ERROR: fcc-logtool.sh not found." >&2
  exit 1
fi

# Setup logging for this script
fCC_setup_logtool

fCC_log INFO "Starting user-data script execution."

# Ensure script runs only once
SCRIPT_NAME=$(basename "$0")
SCRIPT_HASH=$(echo "$SCRIPT_NAME" | md5sum | awk '{print $1}')
FLAG_FILE="/var/run/user-data-$SCRIPT_HASH.flag"

if [[ -f "$FLAG_FILE" ]]; then
  fCC_log INFO "Script already executed."
  exit 0
fi
touch "$FLAG_FILE"

# Fetch metadata
fetch_metadata() {
  local retries=3
  for ((i = 0; i < retries; i++)); do
    TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    IP=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/local-ipv4")
    ROLE=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/tags/instance/Role")
    INSTANCE_ID=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/instance-id")
    REGION=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/placement/region")
    if [[ -n "$IP" && -n "$ROLE" && -n "$INSTANCE_ID" && -n "$REGION" ]]; then
      return 0
    fi
    fCC_log WARN "Retry $((i + 1))/$retries: Failed to fetch metadata. Retrying..."
    sleep 10
  done
  return 1
}

# Update hostname and EC2 Instance Name
update_hostname_and_name() {
  local NEW_HOSTNAME
  NEW_HOSTNAME="${ROLE}-$(echo "$IP" | md5sum | cut -c1-6)"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  aws ec2 create-tags --resources "$INSTANCE_ID" --tags "Key=Name,Value=$NEW_HOSTNAME" --region "$REGION"
  fCC_log INFO "Updated hostname and EC2 Instance Name to $NEW_HOSTNAME"
}

# Main execution
startup_common() {
  fetch_metadata || {
    fCC_error "Failed to fetch metadata."
    exit 1
  }
  update_hostname_and_name

  fCC_log INFO "User-data script execution completed."
}

startup_common || fCC_error "An error occurred during script execution."
