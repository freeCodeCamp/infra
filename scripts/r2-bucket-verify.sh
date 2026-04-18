#!/usr/bin/env bash
# scripts/r2-bucket-verify.sh — T12 R2 bucket verification
#
# Verifies that the R2 bucket is provisioned correctly per
# docs/rfc/gxy-cassiopeia.md §4.4 and the rw/ro keys decrypt + work.
#
# Usage:
#   just r2-bucket-verify gxy-cassiopeia-1
#   # OR
#   scripts/r2-bucket-verify.sh gxy-cassiopeia-1
#
# Requires: rclone, sops, jq, infra-secrets checked out as sibling dir.
# Exit code: 0 on all checks pass, non-zero on any failure.

set -euo pipefail

BUCKET="${1:?usage: r2-bucket-verify.sh <bucket-name>}"
SECRETS_DIR="${SECRETS_DIR:-$(git rev-parse --show-toplevel)/../infra-secrets}"
FAIL=0

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RST=$'\033[0m'
ok()   { printf '%s[PASS]%s %s\n' "$GRN" "$RST" "$1"; }
fail() { printf '%s[FAIL]%s %s\n' "$RED" "$RST" "$1"; FAIL=$((FAIL+1)); }
warn() { printf '%s[WARN]%s %s\n' "$YLW" "$RST" "$1"; }

# 1. Dependencies
for cmd in rclone sops jq; do
  command -v "$cmd" >/dev/null 2>&1 || { fail "missing dependency: $cmd"; exit 1; }
done
ok "dependencies present: rclone, sops, jq"

# 2. Secret files exist and decrypt
RW_ENC="$SECRETS_DIR/gxy-cassiopeia/r2-rw.env.enc"
RO_ENC="$SECRETS_DIR/gxy-cassiopeia/r2-ro.env.enc"

[ -f "$RW_ENC" ] || { fail "rw key file missing: $RW_ENC"; exit 1; }
[ -f "$RO_ENC" ] || { fail "ro key file missing: $RO_ENC"; exit 1; }
ok "rw + ro .env.enc files present"

set +e
RW_DECRYPTED=$(sops -d --input-type dotenv --output-type dotenv "$RW_ENC" 2>/dev/null); RW_RC=$?
RO_DECRYPTED=$(sops -d --input-type dotenv --output-type dotenv "$RO_ENC" 2>/dev/null); RO_RC=$?
set -e

[ "$RW_RC" -eq 0 ] && ok "rw key decrypts" || fail "rw key sops decrypt failed (rc=$RW_RC)"
[ "$RO_RC" -eq 0 ] && ok "ro key decrypts" || fail "ro key sops decrypt failed (rc=$RO_RC)"

eval "$RW_DECRYPTED"
eval "$RO_DECRYPTED"

: "${R2_ENDPOINT:?R2_ENDPOINT missing from rw env}"
: "${R2_ACCESS_KEY_ID_RW:?R2_ACCESS_KEY_ID_RW missing}"
: "${R2_SECRET_ACCESS_KEY_RW:?R2_SECRET_ACCESS_KEY_RW missing}"
: "${R2_ACCESS_KEY_ID_RO:?R2_ACCESS_KEY_ID_RO missing}"
: "${R2_SECRET_ACCESS_KEY_RO:?R2_SECRET_ACCESS_KEY_RO missing}"
ok "all required env vars present"

# 3. rclone remote config (ephemeral, via env)
RCLONE_RW=(
  --s3-provider=Cloudflare
  --s3-endpoint="$R2_ENDPOINT"
  --s3-access-key-id="$R2_ACCESS_KEY_ID_RW"
  --s3-secret-access-key="$R2_SECRET_ACCESS_KEY_RW"
  --s3-region=auto
)
RCLONE_RO=(
  --s3-provider=Cloudflare
  --s3-endpoint="$R2_ENDPOINT"
  --s3-access-key-id="$R2_ACCESS_KEY_ID_RO"
  --s3-secret-access-key="$R2_SECRET_ACCESS_KEY_RO"
  --s3-region=auto
)

# 4. Bucket reachable by both keys
if rclone "${RCLONE_RW[@]}" lsd ":s3:$BUCKET" >/dev/null 2>&1; then
  ok "bucket '$BUCKET' reachable with rw key"
else
  fail "bucket '$BUCKET' not reachable with rw key"
fi
if rclone "${RCLONE_RO[@]}" lsd ":s3:$BUCKET" >/dev/null 2>&1; then
  ok "bucket '$BUCKET' reachable with ro key"
else
  fail "bucket '$BUCKET' not reachable with ro key"
fi

# 5. rw writes; ro cannot write
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
echo "verify-$(date +%s)" > "$TMP"
TESTKEY="_ops/r2-bucket-verify/$(date +%s)-$$.txt"

if rclone "${RCLONE_RW[@]}" copyto "$TMP" ":s3:$BUCKET/$TESTKEY" >/dev/null 2>&1; then
  ok "rw key can write (test object: $TESTKEY)"
else
  fail "rw key write failed"
fi

if rclone "${RCLONE_RO[@]}" copyto "$TMP" ":s3:$BUCKET/$TESTKEY.ro-violation" >/dev/null 2>&1; then
  fail "ro key WAS ABLE TO WRITE — permissions are too broad"
  rclone "${RCLONE_RW[@]}" deletefile ":s3:$BUCKET/$TESTKEY.ro-violation" >/dev/null 2>&1 || true
else
  ok "ro key correctly rejected for writes (AccessDenied expected)"
fi

rclone "${RCLONE_RW[@]}" deletefile ":s3:$BUCKET/$TESTKEY" >/dev/null 2>&1 || warn "could not delete test object $TESTKEY"

# 6. Versioning (manual — rclone cannot query R2 versioning state)
warn "versioning state cannot be queried via rclone — confirm in CF dashboard (Settings → Object versioning: Enabled)"

echo
if [ "$FAIL" -eq 0 ]; then
  printf '%s✓ all automated checks passed%s (1 manual check: versioning UI)\n' "$GRN" "$RST"
  exit 0
else
  printf '%s✗ %d check(s) failed%s\n' "$RED" "$FAIL" "$RST"
  exit 1
fi
