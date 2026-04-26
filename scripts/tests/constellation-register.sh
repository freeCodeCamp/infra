#!/usr/bin/env bash
# Test: justfile `constellation-register` recipe contract
# (T11 sprint 2026-04-21 — Wave A.3 windmill).
#
# Static assertion suite. Does NOT execute the recipe (which would
# call the live Windmill flow). Asserts the recipe is wired correctly:
#   - declared with [group('constellations')]
#   - SITE arg required (no-arg → exit 2 + usage)
#   - resolves WINDMILL_REPO via env override
#   - dispatches to the right script path
#
# Run via `just constellation-register-test` or directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
JUSTFILE="$REPO_ROOT/justfile"

fail=0

if [[ ! -f "$JUSTFILE" ]]; then
    echo "FAIL: justfile not found at $JUSTFILE"
    exit 1
fi

# 1. recipe exists
if ! grep -qE '^constellation-register' "$JUSTFILE"; then
    echo "FAIL: recipe 'constellation-register' not declared"
    fail=1
fi

# 2. recipe is in [group('constellations')]
if ! awk "/\[group\('constellations'\)\]/{flag=1; next} /^\[group/{flag=0} flag && /^constellation-register/{found=1} END{exit !found}" "$JUSTFILE"; then
    echo "FAIL: recipe not under [group('constellations')]"
    fail=1
fi

# 3. usage check: empty arg → nonzero
if ! grep -q 'Usage: just constellation-register <site>' "$JUSTFILE"; then
    echo "FAIL: missing usage hint for empty arg"
    fail=1
fi

# 4. WINDMILL_REPO env override
if ! grep -q 'WINDMILL_REPO:-\.\./fCC-U/windmill' "$JUSTFILE"; then
    echo "FAIL: WINDMILL_REPO env override absent or wrong default"
    fail=1
fi

# 5. dispatches to correct flow path
if ! grep -q 'f/static/provision_site_r2_credentials' "$JUSTFILE"; then
    echo "FAIL: dispatch path 'f/static/provision_site_r2_credentials' missing"
    fail=1
fi

# 6. JSON envelope with `site` key (typed-bridge contract — name not position)
if ! grep -qE 'site["\\:].*\{\{ SITE \}\}' "$JUSTFILE"; then
    echo "FAIL: JSON envelope must pass {site: SITE} by name"
    fail=1
fi

# 7. fail-fast: set -euo pipefail
if ! awk '/^constellation-register/{flag=1} flag && /set -euo pipefail/{found=1; exit} END{exit !found}' "$JUSTFILE"; then
    echo "FAIL: recipe missing 'set -euo pipefail'"
    fail=1
fi

if [[ $fail -eq 0 ]]; then
    echo "OK: constellation-register recipe contract checks pass"
fi
exit "$fail"
