#!/usr/bin/env bash
# Test: phase4-test-site-smoke.sh upholds RFC §6.6 contract +
# repo-wide shell rules + Q5/D35 preview hostname scheme.
#
# Static assertion suite — does not invoke the smoke script. Run via
# `just phase4-smoke-test` or directly.

# shellcheck disable=SC2016
# Failure messages quote shell tokens in backticks (literal strings,
# not command substitution); single-quoting is intentional.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/phase4-test-site-smoke.sh"

fail=0

if [[ ! -f "$SCRIPT" ]]; then
  printf 'FAIL: %s does not exist\n' "$SCRIPT"
  exit 1
fi

# 1. Strict mode
if ! grep -qE '^set -euo pipefail$' "$SCRIPT"; then
  printf 'FAIL: missing `set -euo pipefail`\n'
  fail=1
fi

# 2. All seven required env vars guarded with `: "${VAR:?...}"`
for var in R2_BUCKET GXY_CASSIOPEIA_NODE_IP CF_API_TOKEN CF_ZONE_ID \
           AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY R2_ENDPOINT; do
  if ! grep -qE ": \"\\\$\\{${var}:\\?" "$SCRIPT"; then
    printf 'FAIL: env guard missing for %s\n' "$var"
    fail=1
  fi
done

# 3. D35 preview hostname is dot-scheme (`<site>.preview.freecode.camp`),
#    NOT dash-scheme (`<site>--preview.freecode.camp`).
if grep -qE 'test--preview\.freecode\.camp' "$SCRIPT"; then
  printf 'FAIL: dash-scheme preview hostname present (D35 says dot-scheme)\n'
  fail=1
fi
if ! grep -qE 'test\.preview\.freecode\.camp' "$SCRIPT"; then
  printf 'FAIL: dot-scheme preview hostname `test.preview.freecode.camp` absent\n'
  fail=1
fi

# 4. Trap installed AND cleanup function purges the R2 test prefix
#    (acceptance criterion: cleanup on success AND failure).
if ! grep -qE '^trap [^[:space:]]+ EXIT' "$SCRIPT"; then
  printf 'FAIL: no `trap ... EXIT` registered\n'
  fail=1
fi
if ! grep -qE 'rclone (purge|delete)' "$SCRIPT"; then
  printf 'FAIL: cleanup does not call `rclone purge` (R2 state would leak on failure)\n'
  fail=1
fi
# Trap target must reference an R2 cleanup, not just tmpdir rm.
if grep -qE "^trap 'rm -rf \"\\\$TMP_DIR\"' EXIT" "$SCRIPT"; then
  printf 'FAIL: trap only cleans tmpdir, not R2 (acceptance §2544 violated)\n'
  fail=1
fi

# 5. printf over echo for stdout I/O carrying values.
#    Allow `echo "[N/M] ..."` step banners; reject `echo -n`.
if grep -qE 'echo -n ' "$SCRIPT"; then
  printf 'FAIL: `echo -n` present (use `printf` per rules/shell.md)\n'
  fail=1
fi

# 6. `[[ ]]` over `[ ]` for conditionals.
if grep -qE '^\[ [^[]' "$SCRIPT"; then
  printf 'FAIL: POSIX `[ ]` conditional present (use `[[ ]]`)\n'
  fail=1
fi

# 7. shellcheck clean (definitive lint gate).
if command -v shellcheck >/dev/null 2>&1; then
  if ! shellcheck "$SCRIPT" >/dev/null; then
    printf 'FAIL: shellcheck reports issues\n'
    shellcheck "$SCRIPT" || true
    fail=1
  fi
else
  printf 'WARN: shellcheck not installed — skipping lint gate\n'
fi

# 8. bash parse check.
if ! bash -n "$SCRIPT"; then
  printf 'FAIL: `bash -n` parse error\n'
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  printf 'OK: phase4-test-site-smoke.sh contract satisfied\n'
fi
exit "$fail"
