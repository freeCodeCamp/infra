#!/usr/bin/env bash
# Cutover `*`, `@`, `www` A records on a Cloudflare zone to a set of target IPs.
# Defaults to --dry-run. Use --apply to commit.
#
# Usage:
#   just cf-dns-cutover freecode.camp 1.2.3.4,5.6.7.8              # dry-run
#   just cf-dns-cutover freecode.camp 1.2.3.4,5.6.7.8 --apply      # commit
#
# Idempotent on re-run: deletes existing A records for the 3 names, then
# creates new ones. Proxied through Cloudflare (orange-cloud), TTL 60s.
#
# Environment:
#   CF_API_TOKEN  Zone:DNS:Edit scope

set -euo pipefail

ZONE="${1:?usage: cf-dns-cutover <zone> <ip1,ip2,...> [--dry-run|--apply]}"
IPS="${2:?missing target IPs (comma-separated, at least one)}"
MODE="${3:---dry-run}"

case "$MODE" in
  --dry-run|--apply) ;;
  *) echo "ERROR: mode must be --dry-run or --apply (got: $MODE)" >&2; exit 2 ;;
esac

: "${CF_API_TOKEN:?Set CF_API_TOKEN}"

# Validate IPs (IPv4-ish basic check — CF API rejects invalid ones anyway)
IFS=, read -ra IP_ARR <<< "$IPS"
for IP in "${IP_ARR[@]}"; do
  if ! echo "$IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    echo "ERROR: not a valid IPv4 address: $IP" >&2
    exit 2
  fi
done

ZONE_ID=$(
  curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/zones?name=${ZONE}" \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if not d["success"] or not d["result"]:
  sys.stderr.write("zone lookup failed: " + json.dumps(d.get("errors", []))[:200] + "\n"); sys.exit(2)
print(d["result"][0]["id"])'
)

echo "Zone: ${ZONE} (${ZONE_ID})"
echo "Target IPs: ${IP_ARR[*]}"
echo "Mode: ${MODE}"
echo ""

for NAME in "@" "www" "*"; do
  # Fetch existing records for this name
  FULL_NAME="${NAME}.${ZONE}"
  [ "$NAME" = "@" ] && FULL_NAME="$ZONE"

  EXISTING=$(curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${FULL_NAME}&type=A")

  IDS=$(echo "$EXISTING" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for r in d.get("result", []):
  print(r["id"])')

  for ID in $IDS; do
    if [ "$MODE" = "--apply" ]; then
      curl -fsS -X DELETE -H "Authorization: Bearer ${CF_API_TOKEN}" \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${ID}" >/dev/null
      echo "deleted ${NAME} A record (id=${ID})"
    else
      echo "[dry-run] would delete ${NAME} A record (id=${ID})"
    fi
  done

  for IP in "${IP_ARR[@]}"; do
    if [ "$MODE" = "--apply" ]; then
      curl -fsS -X POST -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"${NAME}\",\"content\":\"${IP}\",\"ttl\":60,\"proxied\":true}" \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" >/dev/null
      echo "created ${NAME} A -> ${IP}"
    else
      echo "[dry-run] would create ${NAME} A -> ${IP}"
    fi
  done
done

echo ""
if [ "$MODE" = "--dry-run" ]; then
  echo "dry-run complete — re-run with --apply to commit."
else
  echo "cutover applied. Verify: dig +short ${ZONE} @1.1.1.1"
fi
