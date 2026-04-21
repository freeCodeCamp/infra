#!/usr/bin/env bash
# Smoke test for RFC secrets-layout Phase 3 zone fallback.
# Asserts: `just deploy` recipe probes `k3s/<cluster>/cluster.tls.zone`
# marker and falls back to `global/tls/<zone>.{crt,key}.enc` in infra-secrets.
# Also asserts markers exist for clusters that carry TLS apps today.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
JUSTFILE="$REPO_ROOT/justfile"

fail=0

grep -q 'cluster\.tls\.zone' "$JUSTFILE" || { echo "FAIL: justfile deploy recipe lacks cluster.tls.zone probe"; fail=1; }
grep -q 'global/tls/' "$JUSTFILE" || { echo "FAIL: justfile deploy recipe lacks global/tls/ fallback path"; fail=1; }

for cluster in gxy-management gxy-launchbase; do
  marker="$REPO_ROOT/k3s/$cluster/cluster.tls.zone"
  [ -f "$marker" ] || { echo "FAIL: $marker missing"; fail=1; continue; }
  zone=$(tr -d '[:space:]' < "$marker")
  case "$zone" in
    freecodecamp-net|freecode-camp) ;;
    *) echo "FAIL: $marker has invalid zone '$zone'"; fail=1 ;;
  esac
done

if [ "$fail" = 0 ]; then
  echo "OK: zone-fallback wiring + markers in place"
fi
exit "$fail"
