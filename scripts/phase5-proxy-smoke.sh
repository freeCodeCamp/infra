#!/usr/bin/env bash
# scripts/phase5-proxy-smoke.sh — Phase 5 exit validation per
# RFC gxy-cassiopeia §G2 (phase 4 → phase 5 ratification) + dispatch
# T34-caddy-dns-smoke §"Smoke retarget" (sprint-2026-04-26).
#
# Exercises the artemis deploy proxy E2E:
#
#   1. resolve identity via `gh auth token`
#   2. POST /api/deploy/init  → capture deploy-session JWT
#   3. PUT  /api/deploy/{id}/upload (multipart) — index.html
#   4. POST /api/deploy/{id}/finalize {mode: preview} → {url}
#   5. curl https://<site>.preview.freecode.camp/   (assert 200 + content match)
#   6. POST /api/site/{site}/promote                (re-auth via GH bearer)
#   7. curl https://<site>.freecode.camp/           (assert 200 + content match)
#   8. cleanup: rollback to previous deploy (best-effort via API)
#
# Architecture invariants honoured:
#
#   - No admin S3 keys in operator shell — all R2 mutations route
#     through artemis. Smoke only ever holds:
#       (a) GH user token (from `gh auth token`)
#       (b) deploy-session JWT (15min, scoped (login, site, deployId))
#   - `test` site authorization in artemis sites.yaml (PR-merged in
#     freeCodeCamp/artemis at config/sites.yaml — staff-only).
#   - D35 dot-scheme preview hostname (<site>.preview.<root>).
#
# Required input env (set by operator or `just phase5-smoke` recipe):
#   ARTEMIS_HOST   default: uploads.freecode.camp
#   TEST_SITE      default: test
#   ROOT_DOMAIN    default: freecode.camp
#   GH_TOKEN       default: `gh auth token`
#
# Tooling required: bash 4+, curl, jq, gh.
#
# Exit codes:
#   0  smoke passed
#   2  prerequisite missing (env / tooling)
#   3  init / upload / finalize failed
#   4  serve verification failed
#   5  promote / prod verification failed
set -euo pipefail

# ------------------------------------------------------------------------
# Inputs + tooling guards
# ------------------------------------------------------------------------
ARTEMIS_HOST="${ARTEMIS_HOST:-uploads.freecode.camp}"
TEST_SITE="${TEST_SITE:-test}"
ROOT_DOMAIN="${ROOT_DOMAIN:-freecode.camp}"
GH_TOKEN="${GH_TOKEN:-}"

PREVIEW_HOST="${TEST_SITE}.preview.${ROOT_DOMAIN}"
PROD_HOST="${TEST_SITE}.${ROOT_DOMAIN}"
ARTEMIS_BASE="https://${ARTEMIS_HOST}"

for tool in curl jq gh; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "[FAIL] missing tool: $tool"
    exit 2
  }
done

if [ -z "$GH_TOKEN" ]; then
  GH_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
[ -n "$GH_TOKEN" ] || {
  echo "[FAIL] no GitHub token (run 'gh auth login' or set GH_TOKEN)"
  exit 2
}

TMP_DIR="$(mktemp -d -t phase5-smoke.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ------------------------------------------------------------------------
# Generate test artifact (one HTML page, random marker for content match)
# ------------------------------------------------------------------------
MARKER="phase5-$(date -u +%Y%m%d-%H%M%S)-$RANDOM"
TEST_HTML="$TMP_DIR/index.html"
cat >"$TEST_HTML" <<HTML
<!doctype html>
<html><head><meta charset="utf-8"><title>${MARKER}</title></head>
<body><h1>${MARKER}</h1></body></html>
HTML

DEPLOY_SHA="$(printf '%s' "$MARKER" | sha256sum | cut -c1-12)"

# ------------------------------------------------------------------------
# 1. Pre-flight — capture current alias (used as rollback target on cleanup)
# ------------------------------------------------------------------------
echo "[1/8] preflight: capture current production deploy id"
PRE_DEPLOYS_JSON="$(curl -fsS \
  -H "Authorization: Bearer $GH_TOKEN" \
  "${ARTEMIS_BASE}/api/site/${TEST_SITE}/deploys" 2>"$TMP_DIR/preflight.err" || true)"
PRE_PROD_ID="$(echo "$PRE_DEPLOYS_JSON" | jq -r '.[0].deployId // empty' 2>/dev/null || true)"
if [ -n "$PRE_PROD_ID" ]; then
  echo "      pre-existing prod deploy: $PRE_PROD_ID (will rollback to this on cleanup)"
else
  echo "      no pre-existing prod deploy (first run for site=${TEST_SITE})"
fi

# ------------------------------------------------------------------------
# 2. POST /api/deploy/init  (auth: GitHub Bearer)
# ------------------------------------------------------------------------
echo "[2/8] POST /api/deploy/init site=${TEST_SITE} sha=${DEPLOY_SHA}"
INIT_PAYLOAD=$(jq -n \
  --arg site "$TEST_SITE" \
  --arg sha "$DEPLOY_SHA" \
  --arg f "index.html" \
  '{site: $site, sha: $sha, files: [$f]}')

INIT_RESP="$(curl -fsS -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$INIT_PAYLOAD" \
  "${ARTEMIS_BASE}/api/deploy/init")" || {
  echo "[FAIL] /api/deploy/init"
  exit 3
}

DEPLOY_ID="$(echo "$INIT_RESP" | jq -r '.deployId')"
DEPLOY_JWT="$(echo "$INIT_RESP" | jq -r '.jwt')"
[ -n "$DEPLOY_ID" ] && [ -n "$DEPLOY_JWT" ] || {
  echo "[FAIL] missing deployId/jwt in init response"
  exit 3
}
echo "      deployId=$DEPLOY_ID"

# Cleanup hook — rollback to pre-existing deploy on exit (success OR fail).
cleanup_rollback() {
  local rc=$?
  if [ -n "${PRE_PROD_ID:-}" ]; then
    echo "[cleanup] rollback to $PRE_PROD_ID"
    curl -fsS -X POST \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg to "$PRE_PROD_ID" '{to: $to}')" \
      "${ARTEMIS_BASE}/api/site/${TEST_SITE}/rollback" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
  exit $rc
}
trap cleanup_rollback EXIT

# ------------------------------------------------------------------------
# 3. PUT /api/deploy/{id}/upload  (auth: deploy-session JWT)
# ------------------------------------------------------------------------
echo "[3/8] PUT /api/deploy/${DEPLOY_ID}/upload?path=index.html"
curl -fsS -X PUT \
  -H "Authorization: Bearer $DEPLOY_JWT" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@${TEST_HTML};type=text/html" \
  "${ARTEMIS_BASE}/api/deploy/${DEPLOY_ID}/upload?path=index.html" >/dev/null ||
  {
    echo "[FAIL] upload"
    exit 3
  }

# ------------------------------------------------------------------------
# 4. POST /api/deploy/{id}/finalize  (mode: preview)
# ------------------------------------------------------------------------
echo "[4/8] POST /api/deploy/${DEPLOY_ID}/finalize mode=preview"
FIN_PAYLOAD=$(jq -n --arg f "index.html" '{mode: "preview", files: [$f]}')
FIN_RESP="$(curl -fsS -X POST \
  -H "Authorization: Bearer $DEPLOY_JWT" \
  -H "Content-Type: application/json" \
  -d "$FIN_PAYLOAD" \
  "${ARTEMIS_BASE}/api/deploy/${DEPLOY_ID}/finalize")" || {
  echo "[FAIL] finalize"
  exit 3
}
PREVIEW_URL="$(echo "$FIN_RESP" | jq -r '.url // empty')"
echo "      preview url: ${PREVIEW_URL:-<none>}"

# ------------------------------------------------------------------------
# 5. Curl preview URL — assert 200 + marker content match
# ------------------------------------------------------------------------
echo "[5/8] verify https://${PREVIEW_HOST}/ contains ${MARKER}"
PREVIEW_RETRIES=12
for _ in $(seq 1 "$PREVIEW_RETRIES"); do
  PREVIEW_BODY="$(curl -fsS "https://${PREVIEW_HOST}/" 2>/dev/null || true)"
  if echo "$PREVIEW_BODY" | grep -q "$MARKER"; then break; fi
  sleep 5
done
echo "$PREVIEW_BODY" | grep -q "$MARKER" ||
  {
    echo "[FAIL] preview content missing marker after $((PREVIEW_RETRIES * 5))s"
    exit 4
  }

# ------------------------------------------------------------------------
# 6. POST /api/site/{site}/promote  (auth: GitHub Bearer)
# ------------------------------------------------------------------------
echo "[6/8] POST /api/site/${TEST_SITE}/promote"
PROMOTE_RESP="$(curl -fsS -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Content-Type: application/json" \
  "${ARTEMIS_BASE}/api/site/${TEST_SITE}/promote")" ||
  {
    echo "[FAIL] promote"
    exit 5
  }
PROD_URL="$(echo "$PROMOTE_RESP" | jq -r '.url // empty')"
echo "      prod url: ${PROD_URL:-<none>}"

# ------------------------------------------------------------------------
# 7. Curl prod URL — assert 200 + marker content match (D38: ≤2min SLO)
# ------------------------------------------------------------------------
echo "[7/8] verify https://${PROD_HOST}/ contains ${MARKER}  (≤2min SLO per D38)"
PROD_RETRIES=24 # 24 * 5s = 120s
for _ in $(seq 1 "$PROD_RETRIES"); do
  PROD_BODY="$(curl -fsS "https://${PROD_HOST}/" 2>/dev/null || true)"
  if echo "$PROD_BODY" | grep -q "$MARKER"; then break; fi
  sleep 5
done
echo "$PROD_BODY" | grep -q "$MARKER" ||
  {
    echo "[FAIL] prod content missing marker after $((PROD_RETRIES * 5))s"
    exit 5
  }

# ------------------------------------------------------------------------
# 8. Done — trap rolls back the alias on exit
# ------------------------------------------------------------------------
echo "[8/8] PASS — phase5 proxy smoke green"
echo "      preview: $PREVIEW_URL"
echo "      prod:    $PROD_URL"
echo "      marker:  $MARKER"
