#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail

# Source common functions and variables
source "$(dirname "$0")/lib/common.sh"

# Source individual command files
source "$(dirname "$0")/commands/port-forward.sh"
source "$(dirname "$0")/commands/list-instances.sh"
source "$(dirname "$0")/commands/ssh.sh"

# Main help menu
main_help() {
  echo "Usage: $0 {port-forward|list|ssh} [options]"
  echo "Run '$0 {command} --help' for more information on a specific command."
  echo
  echo "Commands:"
  echo "  port-forward    Forward a port from an EC2 instance"
  echo "  list            List EC2 instances"
  echo "  ssh             Connect to an EC2 instance via SSH"
}

# Main function to handle command selection
main() {
  if [[ $# -eq 0 ]]; then
    main_help
    exit 1
  fi

  local command="$1"
  shift

  case "$command" in
  port-forward)
    port_forward "$@"
    ;;
  list)
    list_instances "$@"
    ;;
  ssh)
    ssh_connect "$@"
    ;;
  -h | --help)
    main_help
    ;;
  *)
    log_error "Unknown command: $command"
    main_help
    exit 1
    ;;
  esac
}

# Run the main function with all arguments
main "$@"
