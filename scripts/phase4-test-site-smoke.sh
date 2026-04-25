#!/usr/bin/env bash
# scripts/phase4-test-site-smoke.sh — Phase 4 exit validation per RFC
# rfc-gxy-cassiopeia.md §6.6.
#
# Uploads a test deploy under prefix `test.freecode.camp/` in the
# single bucket `universe-static-apps-01`, writes production +
# preview alias blobs, verifies end-to-end serving via Caddy +
# r2_alias on gxy-cassiopeia, then cleans up R2 on success AND on
# failure (trap).
#
# Architecture invariants honoured:
#   - Single R2 bucket. Per-site isolation = prefix scoping
#     (<site>/*), NOT per-bucket. Bucket fixed.
#   - No persistent per-cluster R2 ops cred. Admin S3 keys live
#     ONLY in `infra-secrets/windmill/.env.enc` and are sops-decrypted
#     on demand by this script. Never persisted in operator shell.
#   - D33 ×2: admin cred home = `infra-secrets/windmill/.env.enc`
#     (NOT `global/`).
#
# Decisions enforced:
#   - D35: preview hostname `<site>.preview.freecode.camp` (dot-scheme)
#   - Q6 / D38: rollback SLO ≤ 2 min — alias polled 30s × 2 green hits
#
# Required input env (set by operator or `just phase4-smoke` recipe):
#   R2_BUCKET                   plain export from k3s/gxy-cassiopeia/.envrc
#   GXY_CASSIOPEIA_NODE_IP      operator export (any cassiopeia node IP)
#
# Admin source (sops-decrypted on demand from windmill/.env.enc):
#   CF_ACCOUNT_ID               32-char hex
#   R2_OPS_ACCESS_KEY_ID        admin S3 access key (full-bucket scope)
#   R2_OPS_SECRET_ACCESS_KEY    paired secret
#   ADMIN_ENV_FILE              path override (default: <SECRETS_DIR>/windmill/.env.enc)
#
# Tooling required: bash, curl, aws (aws-cli v2), sops.
#
# Exit codes:
#   0  smoke passed
#   2  prerequisite missing (env / tooling / admin file)
#   3  upload / alias write failed
#   4  serve verification failed
#   5  cleanup verification failed

set -euo pipefail

# Sops-decrypt admin creds from windmill/.env.enc on demand.
# Operator can pre-export any of the three vars to skip the decrypt
# (CI / non-interactive runs).
ADMIN_ENV_FILE="${ADMIN_ENV_FILE:-${SECRETS_DIR:-$HOME/DEV/fCC/infra-secrets}/windmill/.env.enc}"

if [[ -z "${R2_OPS_ACCESS_KEY_ID:-}" \
   || -z "${R2_OPS_SECRET_ACCESS_KEY:-}" \
   || -z "${CF_ACCOUNT_ID:-}" ]]; then
  if [[ ! -f "$ADMIN_ENV_FILE" ]]; then
    printf 'FAIL: admin env not pre-exported AND %s not found\n' "$ADMIN_ENV_FILE" >&2
    exit 2
  fi
  if ! command -v sops >/dev/null 2>&1; then
    printf 'FAIL: sops not on PATH (needed to decrypt %s)\n' "$ADMIN_ENV_FILE" >&2
    exit 2
  fi
  admin_env="$(sops -d --input-type dotenv --output-type dotenv "$ADMIN_ENV_FILE")"
  read_var() {
    local name="$1"
    printf '%s\n' "$admin_env" \
      | awk -F= -v n="$name" '$1==n {print substr($0, index($0,"=")+1); exit}'
  }
  R2_OPS_ACCESS_KEY_ID="${R2_OPS_ACCESS_KEY_ID:-$(read_var R2_OPS_ACCESS_KEY_ID)}"
  R2_OPS_SECRET_ACCESS_KEY="${R2_OPS_SECRET_ACCESS_KEY:-$(read_var R2_OPS_SECRET_ACCESS_KEY)}"
  CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-$(read_var CF_ACCOUNT_ID)}"
fi

: "${R2_BUCKET:?R2_BUCKET not set}"
: "${GXY_CASSIOPEIA_NODE_IP:?GXY_CASSIOPEIA_NODE_IP not set}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID not set (missing from admin env file?)}"
: "${R2_OPS_ACCESS_KEY_ID:?R2_OPS_ACCESS_KEY_ID not set (missing from admin env file?)}"
: "${R2_OPS_SECRET_ACCESS_KEY:?R2_OPS_SECRET_ACCESS_KEY not set (missing from admin env file?)}"

for tool in curl aws; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'FAIL: %s not on PATH\n' "$tool" >&2
    exit 2
  fi
done

# Pass S3 keys to aws-cli via env (no rclone, no config file write).
export AWS_ACCESS_KEY_ID="$R2_OPS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_OPS_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=auto

R2_ENDPOINT="https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
TEST_SITE="test.freecode.camp"
PREVIEW_SITE="test.preview.freecode.camp"   # D35 dot-scheme
DEPLOY_ID="phase4-$(date -u +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"

aws_s3() {
  aws s3 --endpoint-url "$R2_ENDPOINT" "$@"
}

# Cleanup runs on success AND failure. Single bucket, prefix scope.
cleanup() {
  local rc=$?
  printf '[cleanup] purge s3://%s/%s/ + remove tmpdir\n' "$R2_BUCKET" "$TEST_SITE"
  aws_s3 rm "s3://${R2_BUCKET}/${TEST_SITE}/" --recursive >/dev/null 2>&1 \
    || printf '[cleanup] WARN: aws s3 rm returned non-zero (prefix may be empty)\n' >&2
  rm -rf "$TMP_DIR"
  exit "$rc"
}
trap cleanup EXIT

printf '[1/8] Create test deploy payload (id=%s)\n' "$DEPLOY_ID"
mkdir -p "$TMP_DIR/dist"
printf '<!doctype html><html><body><h1>phase4-smoke %s</h1></body></html>\n' \
  "$DEPLOY_ID" > "$TMP_DIR/dist/index.html"

printf '[2/8] Upload deploy prefix to s3://%s/%s/deploys/%s/\n' \
  "$R2_BUCKET" "$TEST_SITE" "$DEPLOY_ID"
if ! aws_s3 cp "$TMP_DIR/dist/" \
  "s3://${R2_BUCKET}/${TEST_SITE}/deploys/${DEPLOY_ID}/" --recursive >/dev/null; then
  printf 'FAIL: aws s3 cp failed\n' >&2
  exit 3
fi

printf '[3/8] Write production alias\n'
printf '%s' "$DEPLOY_ID" \
  | aws_s3 cp - "s3://${R2_BUCKET}/${TEST_SITE}/production" >/dev/null \
  || { printf 'FAIL: production alias write failed\n' >&2; exit 3; }

printf '[4/8] Verify origin serves test page via Host header (poll 30s × 2 green per Q6)\n'
green=0
for attempt in 1 2 3 4; do
  body="$(curl -fsS -H "Host: ${TEST_SITE}" "http://${GXY_CASSIOPEIA_NODE_IP}/" 2>/dev/null || true)"
  if [[ "$body" == *"$DEPLOY_ID"* ]]; then
    green=$((green + 1))
    printf '       attempt %d green (consecutive=%d)\n' "$attempt" "$green"
    if [[ "$green" -ge 2 ]]; then
      break
    fi
  else
    green=0
    printf '       attempt %d not-yet (cache settling)\n' "$attempt"
  fi
  sleep 30
done
if [[ "$green" -lt 2 ]]; then
  printf 'FAIL: production never returned %s on 2 consecutive polls\n' "$DEPLOY_ID" >&2
  exit 4
fi

printf '[5/8] Verify preview URL 404 before preview alias write\n'
preview_status="$(curl -o /dev/null -s -w "%{http_code}" \
  -H "Host: ${PREVIEW_SITE}" "http://${GXY_CASSIOPEIA_NODE_IP}/" || true)"
if [[ "$preview_status" != "404" ]]; then
  printf 'FAIL: preview returned %s, expected 404\n' "$preview_status" >&2
  exit 4
fi

printf '[6/8] Write preview alias, verify preview serves test page\n'
printf '%s' "$DEPLOY_ID" \
  | aws_s3 cp - "s3://${R2_BUCKET}/${TEST_SITE}/preview" >/dev/null \
  || { printf 'FAIL: preview alias write failed\n' >&2; exit 3; }
sleep 20  # alias cache TTL beat
preview_body="$(curl -fsS -H "Host: ${PREVIEW_SITE}" \
  "http://${GXY_CASSIOPEIA_NODE_IP}/" 2>/dev/null || true)"
if [[ "$preview_body" != *"$DEPLOY_ID"* ]]; then
  printf 'FAIL: preview did not serve %s after alias write\n' "$DEPLOY_ID" >&2
  exit 4
fi

printf '[7/8] Cleanup R2 (trap will redo defensively)\n'
aws_s3 rm "s3://${R2_BUCKET}/${TEST_SITE}/" --recursive >/dev/null \
  || { printf 'FAIL: aws s3 rm returned non-zero\n' >&2; exit 5; }

printf '[8/8] Verify prefix gone\n'
remaining="$(aws_s3 ls "s3://${R2_BUCKET}/${TEST_SITE}/" --recursive 2>/dev/null || true)"
if [[ -n "$remaining" ]]; then
  printf 'FAIL: prefix still has objects after rm:\n%s\n' "$remaining" >&2
  exit 5
fi

printf 'OK: phase 4 smoke passed — %s\n' "$DEPLOY_ID"
