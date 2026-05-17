#!/usr/bin/env bash
# Import the live VPC + cloud-firewall + droplets per galaxy into
# local state. Operator-driven only — `terraform import` is
# hook-blocked inside Claude sessions (~/.claude/rules/75-terraform.md).
#
# Pre-flight:
#   1. terraform.tfvars filled (ssh_key_ids + operator_ssh_cidrs).
#   2. export DIGITALOCEAN_TOKEN="..."
#      (use the galaxy-scoped token from
#      $SECRETS_DIR/do-universe/.env.enc, NOT the legacy DO_API_TOKEN).
#   3. terraform init
#
# Pulls live ids via `doctl` then issues per-resource imports.
# Re-runnable (already-imported resources are no-ops).
set -euo pipefail

: "${DIGITALOCEAN_TOKEN:?must be exported (galaxy-scoped)}"

# Map galaxy -> short tag used by doctl --tag-name. Matches the
# `tags[0]` field in var.galaxies.
declare -A GALAXY_TAGS=(
  ["gxy-management"]="_gxy-management-k3s"
  ["gxy-launchbase"]="_gxy-launchbase-k3s"
  ["gxy-cassiopeia"]="_gxy-cassiopeia-k3s"
)

for galaxy in "${!GALAXY_TAGS[@]}"; do
  tag="${GALAXY_TAGS[$galaxy]}"
  echo "=== ${galaxy} (tag=${tag}) ==="

  # VPC
  vpc_id=$(doctl vpcs list --no-header --format ID,Name |
    grep "vpc-${galaxy}$" | awk '{print $1}')
  if [[ -n "${vpc_id}" ]]; then
    echo "  vpc ${vpc_id}"
    terraform import "digitalocean_vpc.this[\"${galaxy}\"]" "${vpc_id}" || true
  else
    echo "  warn: no VPC matching 'vpc-${galaxy}'"
  fi

  # Firewall
  fw_id=$(doctl compute firewall list --no-header --format ID,Name |
    grep "fw-${galaxy}$" | awk '{print $1}')
  if [[ -n "${fw_id}" ]]; then
    echo "  firewall ${fw_id}"
    terraform import "digitalocean_firewall.this[\"${galaxy}\"]" "${fw_id}" || true
  else
    echo "  warn: no firewall matching 'fw-${galaxy}'"
  fi

  # Droplets — iterate over numbered nodes matching <galaxy>-NN
  while read -r id name; do
    [[ -z "${id}" ]] && continue
    echo "  droplet ${id} ${name}"
    terraform import "digitalocean_droplet.this[\"${name}\"]" "${id}" || true
  done < <(doctl compute droplet list --tag-name "${tag}" --no-header --format ID,Name)
done

echo
echo "Done. Run: terraform plan"
echo "Expect: zero diff for resources whose attributes match the .tf"
echo "files; non-zero indicates drift to reconcile (likely size /"
echo "image changes the operator did via dashboard)."
