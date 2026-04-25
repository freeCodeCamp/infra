#!/usr/bin/env bash
# scripts/phase4-test-site-smoke.sh — Phase 4 exit validation per RFC
# rfc-gxy-cassiopeia.md §6.6.
#
# Uploads a test deploy to universe-static-apps-01, writes
# production + preview aliases, verifies end-to-end serving via
# Caddy + r2_alias on gxy-cassiopeia, then cleans up R2 on success
# AND on failure (trap).
#
# Decisions enforced:
#   - D35: preview hostname is `<site>.preview.freecode.camp` (dot-scheme)
#   - Q6 / D38: rollback SLO ≤ 2 min — alias polled 30s × 2 green hits
#
# Required env (loaded by direnv from k3s/gxy-cassiopeia/.envrc):
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY  (R2 rw key for the bucket)
#   R2_ENDPOINT                               (https://<account>.r2.cloudflarestorage.com)
#   R2_BUCKET=universe-static-apps-01
#   GXY_CASSIOPEIA_NODE_IP                    (any cassiopeia node public IP for Host-header smoke)
#   CF_API_TOKEN, CF_ZONE_ID                  (held for future temp DNS automation; runbook handles DNS manually)
#
# Exit codes:
#   0  smoke passed
#   2  prerequisite missing (env / tooling)
#   3  upload / alias write failed
#   4  serve verification failed
#   5  cleanup verification failed

set -euo pipefail

: "${R2_BUCKET:?R2_BUCKET not set}"
: "${GXY_CASSIOPEIA_NODE_IP:?GXY_CASSIOPEIA_NODE_IP not set}"
: "${CF_API_TOKEN:?CF_API_TOKEN not set}"
: "${CF_ZONE_ID:?CF_ZONE_ID not set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID not set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY not set}"
: "${R2_ENDPOINT:?R2_ENDPOINT not set}"

if ! command -v rclone >/dev/null 2>&1; then
  printf 'FAIL: rclone not on PATH\n' >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  printf 'FAIL: curl not on PATH\n' >&2
  exit 2
fi

TEST_SITE="test.freecode.camp"
PREVIEW_SITE="test.preview.freecode.camp"   # D35 dot-scheme
DEPLOY_ID="phase4-$(date -u +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"

# Cleanup runs on success AND failure. Acceptance §2544.
cleanup() {
  local rc=$?
  printf '[cleanup] purge r2:%s/%s/ + remove tmpdir\n' "$R2_BUCKET" "$TEST_SITE"
  if [[ -n "${RCLONE_CONFIG:-}" && -f "$RCLONE_CONFIG" ]]; then
    rclone purge "r2:${R2_BUCKET}/${TEST_SITE}/" >/dev/null 2>&1 || \
      printf '[cleanup] WARN: rclone purge failed (prefix may not exist yet)\n' >&2
  fi
  rm -rf "$TMP_DIR"
  exit "$rc"
}
trap cleanup EXIT

# Configure rclone in memory (does not pollute ~/.config/rclone).
export RCLONE_CONFIG="$TMP_DIR/rclone.conf"
rclone config create r2 s3 \
  provider=Cloudflare \
  endpoint="$R2_ENDPOINT" \
  access_key_id="$AWS_ACCESS_KEY_ID" \
  secret_access_key="$AWS_SECRET_ACCESS_KEY" >/dev/null

printf '[1/8] Create test deploy payload (id=%s)\n' "$DEPLOY_ID"
mkdir -p "$TMP_DIR/dist"
printf '<!doctype html><html><body><h1>phase4-smoke %s</h1></body></html>\n' \
  "$DEPLOY_ID" > "$TMP_DIR/dist/index.html"

printf '[2/8] Upload deploy prefix to r2:%s/%s/deploys/%s/\n' \
  "$R2_BUCKET" "$TEST_SITE" "$DEPLOY_ID"
if ! rclone copy "$TMP_DIR/dist/" "r2:${R2_BUCKET}/${TEST_SITE}/deploys/${DEPLOY_ID}/"; then
  printf 'FAIL: rclone copy failed\n' >&2
  exit 3
fi

printf '[3/8] Write production alias\n'
printf '%s' "$DEPLOY_ID" | rclone rcat "r2:${R2_BUCKET}/${TEST_SITE}/production" || {
  printf 'FAIL: production alias write failed\n' >&2
  exit 3
}

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
printf '%s' "$DEPLOY_ID" | rclone rcat "r2:${R2_BUCKET}/${TEST_SITE}/preview" || {
  printf 'FAIL: preview alias write failed\n' >&2
  exit 3
}
sleep 20  # alias cache TTL beat
preview_body="$(curl -fsS -H "Host: ${PREVIEW_SITE}" \
  "http://${GXY_CASSIOPEIA_NODE_IP}/" 2>/dev/null || true)"
if [[ "$preview_body" != *"$DEPLOY_ID"* ]]; then
  printf 'FAIL: preview did not serve %s after alias write\n' "$DEPLOY_ID" >&2
  exit 4
fi

printf '[7/8] Cleanup R2 (trap will redo defensively)\n'
rclone purge "r2:${R2_BUCKET}/${TEST_SITE}/" || {
  printf 'FAIL: rclone purge returned non-zero\n' >&2
  exit 5
}

printf '[8/8] Verify prefix gone\n'
remaining="$(rclone lsf "r2:${R2_BUCKET}/${TEST_SITE}/" 2>/dev/null || true)"
if [[ -n "$remaining" ]]; then
  printf 'FAIL: prefix still has objects after purge:\n%s\n' "$remaining" >&2
  exit 5
fi

printf 'OK: phase 4 smoke passed — %s\n' "$DEPLOY_ID"
