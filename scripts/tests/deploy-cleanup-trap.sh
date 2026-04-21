#!/usr/bin/env bash
# Test: deploy recipe cleanup trap removes decrypted files after kubectl apply.
# Regression guard for the pre-2026-04-22 bug where $CLEANUP stored relative
# paths and the recipe's `cd k3s/<cluster>` broke the path by trap-trigger time,
# leaving tls.crt/tls.key/.secrets.env/.backup-secrets.env on disk.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
JUSTFILE="$REPO_ROOT/justfile"

fail=0

# The trap must reference absolute-anchored cleanup entries. Easiest signal:
# CLEANUP items prefixed with "$APP_SECRETS_ABS/" (absolute) rather than
# "$APP_SECRETS/" (relative).
if grep -q 'APP_SECRETS_ABS' "$JUSTFILE"; then
  :
else
  echo "FAIL: deploy recipe lacks APP_SECRETS_ABS — trap cleanup still uses relative path"
  fail=1
fi

# Sanity: absolute variable must be derived from realpath/$(pwd)/absolute
# prefix, not bare alias of relative.
if grep -E 'APP_SECRETS_ABS="\$\(realpath|APP_SECRETS_ABS="\$\(pwd\)|APP_SECRETS_ABS="/' "$JUSTFILE" >/dev/null; then
  :
else
  echo "FAIL: APP_SECRETS_ABS not derived from an absolute-path form"
  fail=1
fi

if [ "$fail" = 0 ]; then
  echo "OK: deploy cleanup trap uses absolute-anchored CLEANUP"
fi
exit "$fail"
