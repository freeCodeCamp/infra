#!/bin/bash

tailnet="$1"
remove_before_date="$2"
apikey="$3"
doit="$4"

if [[ -z "$apikey" ]]; then
  echo "Tailscale API key is required"
  exit 1
fi

echo "Fetching hosts from tailnet $tailnet that have not been seen since $remove_before_date"
echo ""
echo "DANGER: This script will remove hosts from the backend. If you want to do this, pass the 'doit' param."
echo ""
echo "Doit is set to: $doit"
echo ""

echo "Getting hosts from tailnet $tailnet..."
rm -f /tmp/tailscale-hosts
curl -s "https://api.tailscale.com/api/v2/tailnet/$tailnet/devices" -u "$apikey:" | jq -r '.devices[] | "\(.lastSeen) \(.id) \(.hostname)"' >/tmp/tailscale-hosts

echo ""
echo "Preserved:"
while IFS=' ' read -r seen id hostname; do
  if [[ "$remove_before_date" < "$seen" ]]; then
    echo "Hostname: $hostname - ID: $id was last seen $seen"
  fi
done </tmp/tailscale-hosts

echo ""
echo ""
echo ""
echo "Removed:"
while IFS=' ' read -r seen id hostname; do
  if [[ "$remove_before_date" > "$seen" ]]; then
    echo "Hostname: $hostname - ID: $id was last seen $seen"
    if [[ $doit == "doit" ]]; then
      curl -s -X DELETE "https://api.tailscale.com/api/v2/device/$id" -u "$apikey:"
    fi
  fi
done </tmp/tailscale-hosts
echo ""
echo "Done"
