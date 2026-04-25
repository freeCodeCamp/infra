#!/usr/bin/env bash
# Test: phase4-test-site-smoke.sh upholds RFC §6.6 contract +
# repo-wide shell rules + Q5/D35 preview hostname scheme +
# admin-Bearer / on-demand-sops design (D-amend 2026-04-25).
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

# 2. Required input env vars guarded with `: "${VAR:?...}"`.
#    Operator must set R2_BUCKET + GXY_CASSIOPEIA_NODE_IP; admin
#    creds (CF_ACCOUNT_ID + R2_OPS_*) are sops-decrypted on demand
#    BUT must still be guarded after the decrypt block.
for var in R2_BUCKET GXY_CASSIOPEIA_NODE_IP CF_ACCOUNT_ID \
           R2_OPS_ACCESS_KEY_ID R2_OPS_SECRET_ACCESS_KEY; do
  if ! grep -qE ": \"\\\$\\{${var}:\\?" "$SCRIPT"; then
    printf 'FAIL: env guard missing for %s\n' "$var"
    fail=1
  fi
done

# 3. Legacy env vars MUST NOT be guarded — design moved off them.
#    rclone-style + per-cluster cred surface explicitly dropped
#    (D-amend 2026-04-25 / option 2).
for legacy in CF_API_TOKEN CF_ZONE_ID AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY R2_ENDPOINT; do
  if grep -qE ": \"\\\$\\{${legacy}:\\?" "$SCRIPT"; then
    printf 'FAIL: legacy env guard %s present (should be dropped per D-amend 2026-04-25)\n' "$legacy"
    fail=1
  fi
done

# 4. Admin source: sops-on-demand from infra-secrets/windmill/.env.enc.
#    D33 ×2 puts admin cred there. Script must reference that path
#    (allowing override via ADMIN_ENV_FILE).
if ! grep -qE 'windmill/\.env\.enc' "$SCRIPT"; then
  printf 'FAIL: script does not reference `windmill/.env.enc` admin source (D33 ×2 home)\n'
  fail=1
fi
if ! grep -qE 'sops -d' "$SCRIPT"; then
  printf 'FAIL: script does not invoke `sops -d` for on-demand admin decrypt\n'
  fail=1
fi
if ! grep -qE 'ADMIN_ENV_FILE' "$SCRIPT"; then
  printf 'FAIL: script does not expose ADMIN_ENV_FILE override (CI / non-interactive)\n'
  fail=1
fi

# 5. D35 preview hostname is dot-scheme (`<site>.preview.freecode.camp`),
#    NOT dash-scheme (`<site>--preview.freecode.camp`).
if grep -qE 'test--preview\.freecode\.camp' "$SCRIPT"; then
  printf 'FAIL: dash-scheme preview hostname present (D35 says dot-scheme)\n'
  fail=1
fi
if ! grep -qE 'test\.preview\.freecode\.camp' "$SCRIPT"; then
  printf 'FAIL: dot-scheme preview hostname `test.preview.freecode.camp` absent\n'
  fail=1
fi

# 6. Trap installed AND cleanup uses `aws s3 rm --recursive`
#    (acceptance: cleanup on success AND failure; rclone retired).
if ! grep -qE '^trap [^[:space:]]+ EXIT' "$SCRIPT"; then
  printf 'FAIL: no `trap ... EXIT` registered\n'
  fail=1
fi
if ! grep -qE 'aws_s3 rm.*--recursive|aws s3 .*rm.*--recursive' "$SCRIPT"; then
  printf 'FAIL: cleanup does not call `aws s3 rm --recursive` (R2 state would leak on failure)\n'
  fail=1
fi
# Trap target must reference an R2 cleanup, not just tmpdir rm.
if grep -qE "^trap 'rm -rf \"\\\$TMP_DIR\"' EXIT" "$SCRIPT"; then
  printf 'FAIL: trap only cleans tmpdir, not R2 (acceptance §2544 violated)\n'
  fail=1
fi

# 7. rclone surface MUST be absent in executable code — design moved
#    to aws-cli + sops-on-demand (option 2 / D-amend 2026-04-25).
#    Comment refs (e.g. "no rclone") are allowed.
if grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -qE '\brclone\b'; then
  printf 'FAIL: executable `rclone` reference present (script must use `aws s3` per D-amend)\n'
  fail=1
fi
if grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -qE 'RCLONE_CONFIG'; then
  printf 'FAIL: executable `RCLONE_CONFIG` reference present\n'
  fail=1
fi

# 8. Single-bucket invariant — script must reference exactly the
#    canonical bucket name. Per-site = prefix scope, NOT per-bucket.
if grep -qE 'R2_BUCKET=[a-z0-9-]+' "$SCRIPT"; then
  printf 'WARN: hardcoded `R2_BUCKET=...` literal in script body (use env)\n'
fi
# The bucket var must be USED (s3://${R2_BUCKET}/...) consistently.
if ! grep -qE 's3://\$\{R2_BUCKET\}/' "$SCRIPT"; then
  printf 'FAIL: script does not use `s3://${R2_BUCKET}/...` for object refs\n'
  fail=1
fi
# Smoke must scope to a SUBPATH of the bucket. Per-site = prefix.
if ! grep -qE 's3://\$\{R2_BUCKET\}/\$\{TEST_SITE\}/' "$SCRIPT"; then
  printf 'FAIL: script does not scope ops to `${R2_BUCKET}/${TEST_SITE}/` prefix\n'
  fail=1
fi

# 9. printf over echo for stdout I/O carrying values.
if grep -qE 'echo -n ' "$SCRIPT"; then
  printf 'FAIL: `echo -n` present (use `printf` per rules/shell.md)\n'
  fail=1
fi

# 10. `[[ ]]` over `[ ]` for conditionals.
if grep -qE '^\[ [^[]' "$SCRIPT"; then
  printf 'FAIL: POSIX `[ ]` conditional present (use `[[ ]]`)\n'
  fail=1
fi

# 11. shellcheck clean (definitive lint gate).
if command -v shellcheck >/dev/null 2>&1; then
  if ! shellcheck "$SCRIPT" >/dev/null; then
    printf 'FAIL: shellcheck reports issues\n'
    shellcheck "$SCRIPT" || true
    fail=1
  fi
else
  printf 'WARN: shellcheck not installed — skipping lint gate\n'
fi

# 12. bash parse check.
if ! bash -n "$SCRIPT"; then
  printf 'FAIL: `bash -n` parse error\n'
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  printf 'OK: phase4-test-site-smoke.sh contract satisfied\n'
fi
exit "$fail"
