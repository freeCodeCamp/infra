#!/usr/bin/env bash
# Import the live R2 bucket + lifecycle into local state, then toggle
# bucket-level versioning out-of-band (no terraform resource exists
# for R2 versioning in cloudflare/cloudflare 5.19.1).
#
# Pre-flight:
#   1. terraform.tfvars filled (cloudflare_account_id at minimum).
#   2. export CLOUDFLARE_API_TOKEN="..."  (R2 Read+Edit; account-scoped)
#   3. terraform init
#
# Operator-driven only — `terraform import` is hook-blocked inside
# Claude sessions (~/.claude/rules/75-terraform.md).
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?must be exported}"

ACCOUNT_ID=$(grep -E '^cloudflare_account_id' terraform.tfvars | sed -E 's/.*"([^"]+)".*/\1/')
BUCKET_NAME=$(grep -E '^# *bucket_name' terraform.tfvars | sed -E 's/.*"([^"]+)".*/\1/' || true)
BUCKET_NAME="${BUCKET_NAME:-universe-static-apps-01}"

CF_API="https://api.cloudflare.com/client/v4"
CURL=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")

echo "account_id=${ACCOUNT_ID}"
echo "bucket=${BUCKET_NAME}"
echo

# Bucket
terraform import cloudflare_r2_bucket.this "${ACCOUNT_ID}/${BUCKET_NAME}" || true

# Lifecycle (singleton per bucket; import key is account_id/bucket_name)
terraform import cloudflare_r2_bucket_lifecycle.this "${ACCOUNT_ID}/${BUCKET_NAME}" || true

echo
echo "Enabling versioning out-of-band (provider has no resource yet)..."
curl -fsS -X PUT "${CF_API}/accounts/${ACCOUNT_ID}/r2/buckets/${BUCKET_NAME}/versioning" \
  "${CURL[@]}" \
  --data-raw '{"enabled":true}' | jq .

echo
echo "Done. Run: terraform plan"
echo "Expect: zero diff if R2 state matches main.tf; non-zero means CF dashboard drift."
