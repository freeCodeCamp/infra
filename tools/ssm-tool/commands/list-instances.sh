# List instances command
list_instances_help() {
  echo "Usage: $0 list [-t|--tag TAG_NAME:TAG_VALUE]..."
  echo
  echo "Options:"
  echo "  -t, --tag TAG_NAME:TAG_VALUE  EC2 instance tag name and value for filtering (can be specified multiple times)"
  echo "  -h, --help                    Display this help menu"
}

list_instances() {
  local tag_filters=()

  while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --tag)
      shift
      IFS=':' read -ra tag <<<"$1"
      if [[ ${#tag[@]} -ne 2 ]]; then
        log_error "Invalid tag format. Use -t TAG_NAME:TAG_VALUE or --tag TAG_NAME:TAG_VALUE"
        list_instances_help
        return 1
      fi
      tag_filters+=("Name=tag:${tag[0]},Values=${tag[1]}")
      ;;
    -h | --help)
      list_instances_help
      return 0
      ;;
    *)
      log_error "Invalid option: $1"
      list_instances_help
      return 1
      ;;
    esac
    shift
  done

  if [[ ${#tag_filters[@]} -eq 0 ]]; then
    log_error "At least one tag filter is required."
    list_instances_help
    return 1
  fi

  check_dependencies "column" "sort"
  check_aws_credentials

  local query="Reservations[].Instances[] | [?State.Name != 'terminated'] | [].[InstanceId, "
  local tag_keys="Name"
  for filter in "${tag_filters[@]}"; do
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

  local aws_command="aws ec2 describe-instances"
  for filter in "${tag_filters[@]}"; do
    aws_command+=" --filters '$filter'"
  done
  aws_command+=" --query \"$query\" --output text"

  local instances
  instances=$(
    (
      echo -e "Instance-Id\tName\t${tag_keys#Name }\tState\tPrivate-IP"
      eval $aws_command
    ) | column -t | sort -k2
  )

  if [[ $(echo "$instances" | wc -l) -le 1 ]]; then
    log_error "No instances found matching the specified tags."
    return 1
  fi

  echo "$instances"
}
