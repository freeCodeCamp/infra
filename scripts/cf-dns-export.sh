#!/usr/bin/env bash
# Export current DNS records for a Cloudflare zone as JSON (cutover snapshot).
#
# Usage:
#   just cf-dns-export freecode.camp > /tmp/snapshot-pre-cutover.json
#
# Environment:
#   CF_API_TOKEN  Zone:DNS:Read scope minimum

set -euo pipefail

ZONE="${1:?usage: cf-dns-export <zone-name>}"
: "${CF_API_TOKEN:?Set CF_API_TOKEN}"

ZONE_ID=$(
  curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/zones?name=${ZONE}" \
  | python3 -c 'import json,sys
d = json.load(sys.stdin)
if not d["success"]:
  sys.stderr.write("CF API error: " + str(d.get("errors")) + "\n"); sys.exit(2)
if not d["result"]:
  sys.stderr.write("zone not found: check token scope and zone name\n"); sys.exit(2)
print(d["result"][0]["id"])'
)

# Paginate if we grow past per_page; 200 is the CF max.
curl -fsS -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?per_page=200"
