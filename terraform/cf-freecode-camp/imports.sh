#!/usr/bin/env bash
# Import live freecode.camp Cloudflare resources into local state.
#
# Pre-flight:
#   1. Copy terraform.tfvars.sample → terraform.tfvars; fill in
#      cloudflare_api_token + ingress IPs (or set TF_VAR_* env vars).
#   2. `export TF_VAR_cloudflare_api_token=...`
#   3. `terraform init`
#
# This script is operator-driven (Terraform `import` is hook-blocked
# inside Claude sessions per ~/.claude/rules/75-terraform.md). It must
# be run from a non-Claude shell.
#
# Pulls record IDs live via the CF API then issues one `terraform
# import` per record. Re-runnable: existing imports are no-ops.

set -euo pipefail

: "${TF_VAR_cloudflare_api_token:?must be exported}"

ZONE_NAME="freecode.camp"
CF_API="https://api.cloudflare.com/client/v4"
CURL_AUTH=(-H "Authorization: Bearer ${TF_VAR_cloudflare_api_token}" -H "Content-Type: application/json")

zone_id=$(curl -fsS "${CURL_AUTH[@]}" "${CF_API}/zones?name=${ZONE_NAME}" | jq -r '.result[0].id')
[[ -n "${zone_id}" && "${zone_id}" != "null" ]] || {
  echo "zone lookup failed"
  exit 1
}
echo "zone_id=${zone_id}"

# Zone settings override is a singleton per zone — import by zone id.
terraform import cloudflare_zone_settings_override.this "${zone_id}" || true

# DNS records: map local.records key → CF DNS query.
# Pairs: <local_key>:<dns_name>:<dns_type>
records=(
  "apex_a:freecode.camp:A"
  "www_a:www.freecode.camp:A"
  "wildcard_a:*.freecode.camp:A"
  "uploads_a:uploads.freecode.camp:A"
)

for pair in "${records[@]}"; do
  IFS=':' read -r key name type <<<"${pair}"
  rid=$(curl -fsS "${CURL_AUTH[@]}" \
    "${CF_API}/zones/${zone_id}/dns_records?name=${name}&type=${type}" |
    jq -r '.result[0].id')
  if [[ -z "${rid}" || "${rid}" == "null" ]]; then
    echo "warn: ${name} ${type} not found on zone; skipping ${key}"
    continue
  fi
  echo "import cloudflare_record.this[\"${key}\"] ← ${zone_id}/${rid}"
  terraform import "cloudflare_record.this[\"${key}\"]" "${zone_id}/${rid}" || true
done

echo
echo "Done. Now run: terraform plan"
echo "Expect: zero diff if record state matches local.records, else inspect drift."
