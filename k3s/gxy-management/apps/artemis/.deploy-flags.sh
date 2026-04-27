# shellcheck shell=bash
# Sourced by `just deploy gxy-management artemis` inside the helm phase.
# May export EXTRA_HELM_ARGS appended to `helm upgrade --install`.
#
# Inject sites.yaml from the operator's local `freeCodeCamp/artemis`
# checkout. Override the default path via $ARTEMIS_REPO if cloned
# elsewhere. SOT lives in the artemis repo at config/sites.yaml
# (PR-reviewed by platform team per ADR-016 §sites.yaml lifecycle).

SITES_PATH="${ARTEMIS_REPO:-$HOME/DEV/fCC/artemis}/config/sites.yaml"
if [ ! -f "$SITES_PATH" ]; then
  echo "Error: $SITES_PATH not found." >&2
  echo "       Pull freeCodeCamp/artemis or set ARTEMIS_REPO=<path>." >&2
  exit 1
fi
EXTRA_HELM_ARGS="${EXTRA_HELM_ARGS:-} --set-file sites=$SITES_PATH"
echo "Helm: artemis sites.yaml from $SITES_PATH"
