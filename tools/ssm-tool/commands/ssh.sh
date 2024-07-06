# SSH command
ssh_connect_help() {
  echo "Usage: $0 ssh [-u|--user USER_NAME] [-t|--tag TAG_NAME:TAG_VALUE]... [-y|--yes]"
  echo
  echo "Options:"
  echo "  -u, --user USER_NAME          User name to use for SSH connection (default: freecodecamp)"
  echo "  -t, --tag TAG_NAME:TAG_VALUE  EC2 instance tag name and value for filtering (can be specified multiple times)"
  echo "  -y, --yes                     Bypass confirmation prompt"
  echo "  -h, --help                    Display this help menu"
}

ssh_connect() {
  local tag_filters=()
  local user="freecodecamp"
  local bypass_confirmation=false

  while [[ $# -gt 0 ]]; do
    case $1 in
    -u | --user)
      shift
      user="$1"
      ;;
    -t | --tag)
      shift
      IFS=':' read -ra tag <<<"$1"
      if [[ ${#tag[@]} -ne 2 ]]; then
        log_error "Invalid tag format. Use -t TAG_NAME:TAG_VALUE or --tag TAG_NAME:TAG_VALUE"
        ssh_connect_help
        return 1
      fi
      tag_filters+=("Name=tag:${tag[0]},Values=${tag[1]}")
      ;;
    -y | --yes)
      bypass_confirmation=true
      ;;
    -h | --help)
      ssh_connect_help
      return 0
      ;;
    *)
      log_error "Invalid option: $1"
      ssh_connect_help
      return 1
      ;;
    esac
    shift
  done

  if [[ ${#tag_filters[@]} -eq 0 ]]; then
    log_error "At least one tag filter is required."
    ssh_connect_help
    return 1
  fi

  check_dependencies "fzf" "awk" "ssh"
  check_aws_credentials

  instance_id=$(find_instance_id "${tag_filters[@]}")

  if [[ -z $instance_id ]]; then
    log_error "No running instances found matching the specified tags."
    return 1
  fi

  ssh_command="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ProxyCommand='aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p' \"$user@$instance_id\""

  if ! $bypass_confirmation; then
    echo "SSH command:"
    echo "$ssh_command"
    read -rp "Do you want to proceed? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
      echo "Aborted."
      return 0
    fi
  fi

  log_info "Opening SSH session to instance $instance_id"
  eval "$ssh_command"
}
