#!/bin/bash

tailnet="$1"
remove_before_date="$2"
apikey="$3"
doit="$4"

if [[ -z "$apikey" ]]; then
  echo "Tailscale API key is required"
  exit 1
fi

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "DANGER: This script will remove hosts from the backend. If you want to do this, pass the 'doit' param."
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "[Info]: Fetching hosts from tailnet $tailnet that have not been seen since: $remove_before_date"
echo "[Info]: Currently 'doit' is set to: $doit"
echo "[Info]: Getting hosts from tailnet: $tailnet"
rm -f /tmp/tailscale-hosts
curl -s "https://api.tailscale.com/api/v2/tailnet/$tailnet/devices" -u "$apikey:" | jq -r '.devices[] | "\(.lastSeen) \(.id) \(.hostname)"' >/tmp/tailscale-hosts

echo "[Info]: Comparing hosts. Here are the results:"
echo ""
echo "Preserved:"
echo "----------"
echo ""
printf "%-20s %-20s %-30s\n" "ID" "Last Seen" "Machine Name"
printf "%-20s %-20s %-30s\n" "--------------------" "--------------------" "------------------------------"
while IFS=' ' read -r seen id hostname; do
  if command -v date >/dev/null; then
    # Adjust for compatibility between GNU date and BSD date
    if date --version >/dev/null 2>&1; then
      # GNU date
      remove_before_date_in_secs=$(date -d "$remove_before_date" "+%s")
      seen_in_secs=$(date -d "$seen" "+%s")
    else
      # BSD date
      remove_before_date_in_secs=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$remove_before_date" "+%s")
      seen_in_secs=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$seen" "+%s")
    fi
  fi

  if [[ "$remove_before_date_in_secs" -lt "$seen_in_secs" ]]; then
    printf "%-20s %-20s %-30s\n" "$id" "$seen" "$hostname"
  fi
done </tmp/tailscale-hosts

echo ""
echo "Removed:"
echo "--------"
echo ""
printf "%-20s %-20s %-30s\n" "ID" "Last Seen" "Machine Name"
printf "%-20s %-20s %-30s\n" "--------------------" "--------------------" "------------------------------"
while IFS=' ' read -r seen id hostname; do
  if command -v date >/dev/null; then
    # Adjust for compatibility between GNU date and BSD date
    if date --version >/dev/null 2>&1; then
      # GNU date
      remove_before_date_in_secs=$(date -d "$remove_before_date" "+%s")
      seen_in_secs=$(date -d "$seen" "+%s")
    else
      # BSD date
      remove_before_date_in_secs=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$remove_before_date" "+%s")
      seen_in_secs=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$seen" "+%s")
    fi
  fi

  if [[ "$remove_before_date_in_secs" -gt "$seen_in_secs" ]]; then
    printf "%-20s %-20s %-30s\n" "$id" "$seen" "$hostname"
    if [[ $doit == "doit" ]]; then
      # Corrected endpoint for device deletion to include tailnet
      curl -s -X DELETE "https://api.tailscale.com/api/v2/tailnet/$tailnet/device/$id" -u "$apikey:"
    fi
  fi
done </tmp/tailscale-hosts
echo ""
echo "[Info]: Done"
