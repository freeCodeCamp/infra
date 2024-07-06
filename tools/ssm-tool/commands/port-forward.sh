# Port forwarding command
port_forward_help() {
  echo "Usage: $0 port-forward [-t|--tag TAG_NAME:TAG_VALUE]... [-p|--port PORT_NUMBER] [-l|--local-port LOCAL_PORT_NUMBER] [-y|--yes]"
  echo
  echo "Options:"
  echo "  -t, --tag TAG_NAME:TAG_VALUE  EC2 instance tag name and value for filtering (can be specified multiple times)"
  echo "  -p, --port PORT_NUMBER        Remote port number to forward"
  echo "  -l, --local-port LOCAL_PORT_NUMBER  Local port number to use"
  echo "  -y, --yes                     Bypass confirmation prompt"
  echo "  -h, --help                    Display this help menu"
}

port_forward() {
  local tag_filters=()
  local port_number=""
  local local_port_number=""
  local bypass_confirmation=false

  while [[ $# -gt 0 ]]; do
    case $1 in
    -t | --tag)
      shift
      IFS=':' read -ra tag <<<"$1"
      if [[ ${#tag[@]} -ne 2 ]]; then
        log_error "Invalid tag format. Use -t TAG_NAME:TAG_VALUE or --tag TAG_NAME:TAG_VALUE"
        port_forward_help
        return 1
      fi
      tag_filters+=("Name=tag:${tag[0]},Values=${tag[1]}")
      ;;
    -p | --port)
      shift
      port_number="$1"
      ;;
    -l | --local-port)
      shift
      local_port_number="$1"
      ;;
    -y | --yes)
      bypass_confirmation=true
      ;;
    -h | --help)
      port_forward_help
      return 0
      ;;
    *)
      log_error "Invalid option: $1"
      port_forward_help
      return 1
      ;;
    esac
    shift
  done

  if [[ ${#tag_filters[@]} -eq 0 ]]; then
    log_error "At least one tag filter is required. Use -t or --tag option to specify tags."
    port_forward_help
    return 1
  fi

  if [[ -z "$port_number" ]]; then
    log_error "Remote port number is required. Use -p or --port option to specify the port number."
    port_forward_help
    return 1
  fi

  if [[ -z "$local_port_number" ]]; then
    log_error "Local port number is required. Use -l or --local-port option to specify the local port number."
    port_forward_help
    return 1
  fi

  check_dependencies "fzf" "awk"
  check_aws_credentials

  instance_id=$(find_instance_id "${tag_filters[@]}")

  if [[ -z $instance_id ]]; then
    log_error "No running instances found matching the specified tags."
    return 1
  fi

  port_forward_command="aws ssm start-session --target \"$instance_id\" --document-name AWS-StartPortForwardingSession --parameters \"{\\\"portNumber\\\":[\\\"$port_number\\\"],\\\"localPortNumber\\\":[\\\"$local_port_number\\\"]}\""

  if ! $bypass_confirmation; then
    echo "Port forwarding command:"
    echo "$port_forward_command"
    read -rp "Do you want to proceed? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
      echo "Aborted."
      return 0
    fi
  fi

  log_info "Forwarding remote port $port_number to local port $local_port_number on instance $instance_id"
  eval "$port_forward_command"
}
