#!/bin/bash
# File: /usr/local/bin/fcc-logtool.sh

# Set up log directory
FCC_LOG_DIR="/var/log/fcc-logs"
mkdir -p "${FCC_LOG_DIR}"

# Function to get current fCC_timestamp
fCC_timestamp() {
  date "+%Y-%m-%d_%H-%M-%S"
}

# Function to get current date (for daily log rotation)
fCC_current_date() {
  date "+%Y-%m-%d"
}

# Main logging function
fCC_log() {
  local log_level="$1"
  local message="$2"
  local script_name=$(basename "${BASH_SOURCE[1]}" .sh)
  local date=$(fCC_current_date)
  local log_file="${FCC_LOG_DIR}/${script_name}_${date}.log"

  echo "$(fCC_timestamp) [${log_level}] ${message}" | tee -a "${log_file}"
  logger -t "fcc-${script_name}" "[${log_level}] ${message}"
}

# Error logging function
fCC_error() {
  local message="$1"
  local script_name=$(basename "${BASH_SOURCE[1]}" .sh)
  local date=$(fCC_current_date)
  local error_log="${FCC_LOG_DIR}/${script_name}_${date}_error.log"

  echo "$(fCC_timestamp) [ERROR] ${message}" | tee -a "${error_log}" >&2
  logger -p user.err -t "fcc-${script_name}" "[ERROR] ${message}"
}

# Set up xtrace
enable_xtrace() {
  local script_name=$(basename "${BASH_SOURCE[1]}" .sh)
  local date=$(fCC_current_date)
  local xtrace_log="${FCC_LOG_DIR}/${script_name}_${date}_xtrace.log"
  exec 4>>"${xtrace_log}"
  BASH_XTRACEFD=4
  set -x
}

# Customize PS4 for more informative xtrace output
PS4='+ $(fCC_timestamp) ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]:+${FUNCNAME[0]}(): } '

# Function to set up logging for a script
fCC_setup_logtool() {
  # Enable xtrace logging
  enable_xtrace
}

# Export functions so they can be used in sourced scripts
export -f fCC_log fCC_error fCC_setup_logtool fCC_timestamp fCC_current_date
