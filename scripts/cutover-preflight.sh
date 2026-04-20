#!/usr/bin/env bash
# DNS cutover preflight: enumerate sites in gxy-static-1, run 8 checks per
# site against gxy-cassiopeia-1. Exits non-zero on ANY site failing ANY check
# — cutover must not proceed.
#
# Usage:
#   just cutover-preflight
#
# Environment (from direnv in infra-secrets):
#   STATIC_BUCKET           (default: gxy-static-1)
#   CASSIOPEIA_BUCKET       (default: gxy-cassiopeia-1)
#   CASSIOPEIA_NODE_IP      any gxy-cassiopeia node public IP (for Host-header test)
#   WOODPECKER_ADMIN_TOKEN  Woodpecker API token with repo-read scope
#   WOODPECKER_ENDPOINT     e.g. https://woodpecker.freecodecamp.net
#
# Read-only script. Never mutates R2, CF DNS, or Woodpecker state.

set -euo pipefail

: "${STATIC_BUCKET:=gxy-static-1}"
: "${CASSIOPEIA_BUCKET:=gxy-cassiopeia-1}"
: "${CASSIOPEIA_NODE_IP:?Set CASSIOPEIA_NODE_IP to any gxy-cassiopeia node public IP}"
: "${WOODPECKER_ADMIN_TOKEN:?Set WOODPECKER_ADMIN_TOKEN}"
: "${WOODPECKER_ENDPOINT:?Set WOODPECKER_ENDPOINT (e.g. https://woodpecker.freecodecamp.net)}"

# Ensure rclone is configured for both buckets (sourced from direnv).
rclone lsd "r2:${STATIC_BUCKET}" >/dev/null 2>&1 || { echo "ERROR: cannot list $STATIC_BUCKET — is rclone r2 remote configured?" >&2; exit 2; }
rclone lsd "r2:${CASSIOPEIA_BUCKET}" >/dev/null 2>&1 || { echo "ERROR: cannot list $CASSIOPEIA_BUCKET — is rclone r2 remote configured?" >&2; exit 2; }

# Enumerate sites (top-level prefixes) in gxy-static-1.
SITES=$(rclone lsf --dirs-only "r2:${STATIC_BUCKET}" | sed 's|/$||' | sort -u)
if [ -z "$SITES" ]; then
  echo "no sites in $STATIC_BUCKET — nothing to cutover"
  exit 0
fi

FAIL=0
printf "%-50s | %s\n" "SITE" "STATUS"
printf -- "--------------------------------------------------+---------------------------------------------\n"

for SITE in $SITES; do
  # 1. Site exists in cassiopeia with at least one deploy
  if ! rclone lsd "r2:${CASSIOPEIA_BUCKET}/${SITE}/deploys/" >/dev/null 2>&1; then
    printf "%-50s | %s\n" "$SITE" "fail:no-deploys-in-cassiopeia"
    FAIL=1
    continue
  fi

  # 2. Production alias file exists
  PROD=$(rclone cat "r2:${CASSIOPEIA_BUCKET}/${SITE}/production" 2>/dev/null | tr -d '[:space:]' || true)
  if [ -z "$PROD" ]; then
    printf "%-50s | %s\n" "$SITE" "fail:no-production-alias"
    FAIL=1
    continue
  fi

  # 3. Alias value format
  if ! echo "$PROD" | grep -qE '^[A-Za-z0-9._-]{1,64}$'; then
    printf "%-50s | %s\n" "$SITE" "fail:alias-invalid-format($PROD)"
    FAIL=1
    continue
  fi

  # 4. Alias target has index.html
  if ! rclone lsf "r2:${CASSIOPEIA_BUCKET}/${SITE}/deploys/${PROD}/index.html" >/dev/null 2>&1; then
    printf "%-50s | %s\n" "$SITE" "fail:alias-target-missing-index"
    FAIL=1
    continue
  fi

  # 5. HTTP 200 via cassiopeia origin (Host-header test)
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" -H "Host: ${SITE}" "http://${CASSIOPEIA_NODE_IP}/" || echo "000")
  if [ "$HTTP_CODE" != "200" ]; then
    printf "%-50s | %s\n" "$SITE" "fail:origin-returned-${HTTP_CODE}"
    FAIL=1
    continue
  fi

  # 6. Preview alias (optional; if present, must return 200 too)
  if rclone lsf "r2:${CASSIOPEIA_BUCKET}/${SITE}/preview" >/dev/null 2>&1; then
    SUBDOMAIN="${SITE%%.*}"
    PREVIEW_HOST="${SUBDOMAIN}--preview.freecode.camp"
    PREVIEW_CODE=$(curl -o /dev/null -s -w "%{http_code}" -H "Host: ${PREVIEW_HOST}" "http://${CASSIOPEIA_NODE_IP}/" || echo "000")
    if [ "$PREVIEW_CODE" != "200" ]; then
      printf "%-50s | %s\n" "$SITE" "fail:preview-returned-${PREVIEW_CODE}"
      FAIL=1
      continue
    fi
  fi

  # 7. Woodpecker repo registered (matches the site's subdomain)
  REPO_NAME="${SITE%%.*}"
  if ! curl -fsS -H "Authorization: Bearer ${WOODPECKER_ADMIN_TOKEN}" \
        "${WOODPECKER_ENDPOINT}/api/repos/lookup/freeCodeCamp-Universe/${REPO_NAME}" \
        >/dev/null 2>&1; then
    printf "%-50s | %s\n" "$SITE" "fail:woodpecker-repo-not-registered"
    FAIL=1
    continue
  fi

  # 8. Site-name validation (no --, RFC-1123 subdomain)
  if echo "$REPO_NAME" | grep -q -- '--'; then
    printf "%-50s | %s\n" "$SITE" "fail:site-name-contains-double-hyphen"
    FAIL=1
    continue
  fi

  printf "%-50s | %s\n" "$SITE" "ok"
done

echo ""
if [ "$FAIL" = "1" ]; then
  echo "PREFLIGHT FAILED — fix the failing sites before cutover."
  exit 3
fi
echo "PREFLIGHT OK — ready to proceed with cutover."
