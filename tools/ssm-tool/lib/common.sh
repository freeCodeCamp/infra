#!/bin/bash

# Common variables
LOG_DIR="/tmp/logs"
LOG_FILE="${LOG_DIR}/ssm.log"
ERROR_LOG_FILE="${LOG_DIR}/ssm-error.log"

# Create the log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Common functions
timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  echo "$(timestamp) [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
  echo "$(timestamp) [ERROR] $1" | tee -a "$ERROR_LOG_FILE" >&2
}

check_dependencies() {
  local dependencies=("$@")
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_error "Dependency '$dep' not found. Please install it and try again."
      exit 1
    fi
  done
}

check_aws_credentials() {
  if ! command -v aws &>/dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
  fi

  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS credentials are not configured properly. Please configure them using 'aws configure'."
    exit 1
  fi
}

find_instance_id() {
  local filters=("$@")
  local query="Reservations[].Instances[] | [?State.Name != 'terminated'] | [].[InstanceId, "
  local tag_keys="Name"
  for filter in "${filters[@]}"; do
    if [[ $filter =~ Name=tag:([^,]+) ]]; then
      tag_keys+=" ${BASH_REMATCH[1]}"
    fi
  done

  local tag_query=""
  for key in $tag_keys; do
    [[ -n "$tag_query" ]] && tag_query+=", "
    tag_query+="join(' ', Tags[?Key=='$key'].Value || ['-'])"
  done
  query+="$tag_query, State.Name, PrivateIpAddress]"

  local temp_file=$(mktemp)
  local aws_command="aws ec2 describe-instances"
  for filter in "${filters[@]}"; do
    aws_command+=" --filters '$filter'"
  done
  aws_command+=" --query \"$query\" --output text"

  if ! eval $aws_command >"$temp_file" 2>&1; then
    log_error "Error querying AWS EC2 instances: $(cat "$temp_file")"
    rm "$temp_file"
    return 1
  fi

  if [[ $(wc -l <"$temp_file") -le 1 ]]; then
    rm "$temp_file"
    return 0
  fi

  instance_id=$(
    (
      echo -e "Instance-Id\tName\t${tag_keys#Name }\tState\tPrivate-IP"
      cat "$temp_file"
    ) |
      column -t | sort -k2 |
      fzf --header-lines=1 |
      awk '{print $1}'
  )

  rm "$temp_file"
  echo "$instance_id"
}
