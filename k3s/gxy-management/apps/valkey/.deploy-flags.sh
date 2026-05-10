# shellcheck shell=bash
# Sourced by `just deploy gxy-management valkey` inside the helm phase.
# May export EXTRA_HELM_ARGS appended to `helm upgrade --install`.
#
# Decrypt the sops sealed overlay into a tempfile, append it to the
# helm value chain, and clean it up on shell exit. Layering target:
#
#   chart values.yaml
#     < apps/valkey/values.production.yaml
#       < $TMP/valkey.values.yaml         (decrypted from sops here)
#
# The sops envelope holds only `secretEnv.VALKEY_PASSWORD`.
# Nothing else lives in the encrypted layer.

set -euo pipefail

SECRETS_REPO="${SECRETS_DIR:-../../../../infra-secrets}"
ENC="${SECRETS_REPO}/k3s/gxy-management/valkey.values.yaml.enc"

if [[ ! -f "$ENC" ]]; then
  printf 'Error: %s not found.\n' "$ENC" >&2
  printf '       Mint via the recipe in docs/flight-manuals/gxy-management.md §C-valkey.\n' >&2
  exit 1
fi

TMP="$(mktemp -t valkey-values-XXXXXX.yaml)"
trap 'rm -f "$TMP"' EXIT

sops --input-type yaml --output-type yaml --decrypt "$ENC" >"$TMP"

EXTRA_HELM_ARGS="${EXTRA_HELM_ARGS:-} --values $TMP"
printf 'Helm: valkey sops overlay decrypted to %s\n' "$TMP"
