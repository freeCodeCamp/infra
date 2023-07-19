#!/bin/bash

tailnet="$1"
remove_before_date="$2"
apikey="$3"
doit="$4"

echo "Removing hosts from tailnet $tailnet that have not been seen since $remove_before_date"
echo ""
echo "Doit is set to: $doit"
echo ""
echo "DANGER: This script will remove hosts from the backend. If you want to do this, pass the 'doit' param."

curl -s "https://api.tailscale.com/api/v2/tailnet/$tailnet/devices" -u "$apikey:" | jq -r '.devices[] |  "\(.lastSeen) \(.id) \(.hostname)"' |
  while read seen id hostname; do
    if [[ $seen < $remove_before_date ]]; then
      echo Hostname: $hostname - ID: $id " was last seen " $seen " deleting it from the backend"
      if [[ $doit == "doit" ]]; then
        curl -s -X DELETE "https://api.tailscale.com/api/v2/device/$id" -u "$apikey:"
      fi
    else
      echo Hostname: $hostname - ID: $id " was last seen " $seen " keeping it"
    fi
  done

echo "Done"
