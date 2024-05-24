#!/bin/bash

# Set Bash options for strict error handling and debugging
set -euo pipefail
set -x

# Define the base directory for logs
LOG_DIR="/var/log/fcc-setup-logs"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Define log files
LOG_FILE="${LOG_DIR}/user-data.log"
ERROR_LOG_FILE="${LOG_DIR}/user-data-error.log"
XTRACE_LOG="${LOG_DIR}/user-data-xtrace.log"

# Redirect output to logs
exec > >(tee -a "${LOG_FILE}") 2> >(tee -a "${ERROR_LOG_FILE}" >&2)
exec 4>>"${XTRACE_LOG}"
BASH_XTRACEFD=4

# Customizing PS4 for xtrace output
PS4='+ $BASH_SOURCE:$LINENO:${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

# Function to add timestamp
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Logging functions
log() { echo "$(timestamp) [$1] $2"; }

## ------------------- Main Script ------------------- ##

# Ensure script runs only once
ensure_run_once() {
  local flag_file="/var/run/user-data-flag"
  if [[ -f "${flag_file}" ]]; then
    log INFO "User-data script has already been executed."
    exit 0
  fi
  touch "${flag_file}"
}

# Manage Nomad service
manage_nomad_service() {
  log INFO "Attempting to enable and start nomad.service..."
  systemctl enable nomad.service
  systemctl daemon-reload
  systemctl start nomad.service
  log INFO "Checking the status of nomad.service:"
  systemctl status nomad.service | tee -a /var/log/nomad-service-status.log
}

# Manage Consul service
manage_consul_service() {
  log INFO "Attempting to enable and start consul.service..."
  systemctl enable consul.service
  systemctl daemon-reload
  systemctl start consul.service
  log INFO "Checking the status of consul.service:"
  systemctl status consul.service
}

# Update hostname
update_hostname_with_role() {
  local retries=3
  local delay=5 # Delay in seconds
  local token=""
  local ip=""
  local role_tag=""

  # Retry logic for token and metadata retrieval
  for ((i = 0; i < retries; i++)); do
    # Fetch token if not already successful
    if [[ -z "$token" ]]; then
      token=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
      [[ -z "$token" ]] && log WARN "Failed to fetch token. Retrying in ${delay}s..." && sleep $delay && continue
    fi

    # Fetch IP and Role Tag using the token
    ip=$(curl -sS -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/local-ipv4")
    role_tag=$(curl -sS -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/tags/instance/Role")

    if [[ -n "$ip" && -n "$role_tag" ]]; then
      break
    else
      log WARN "Retry $((i + 1))/$retries: Failed to fetch metadata. Retrying in ${delay}s..."
      sleep $delay
      ip="" # Reset to ensure retry attempts for both
      role_tag=""
    fi
  done

  if [[ -z "$ip" || -z "$role_tag" ]]; then
    log ERROR "Failed to retrieve necessary metadata after $retries attempts."
    return 1
  fi

  # Generate hostname using IP hash
  local ip_hash=$(echo "$ip" | md5sum | cut -d' ' -f1)
  local new_hostname="${role_tag}-${ip_hash:0:6}"
  log INFO "Updating hostname to $new_hostname..."
  hostnamectl set-hostname "$new_hostname"
}

# Main execution block
main() {
  log INFO "Starting user-data script execution."
  ensure_run_once
  update_hostname_with_role
  manage_nomad_service
  # manage_consul_service
  log INFO "User-data script execution completed."
}

main || {
  log ERROR "An error occurred during user-data script execution."
  exit 1
}
