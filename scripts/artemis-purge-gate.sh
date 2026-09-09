#!/usr/bin/env bash
# shellcheck disable=SC2154
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${KUBECONFIG:=$HERE/../k3s/gxy-management/.kubeconfig.yaml}"
export KUBECONFIG
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/artemis"
BASE="${ARTEMIS_PURGE_BASELINE:-$STATE/purge-gate-baseline.env}"
TERMINAL='CANCELLED|FAILED|COMPLETED|EVICTED'
FAILED=0

Q_ART() { kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }
EV_CAP() { sentry issue view "$1" 2>/dev/null | awk -F'│' '/Events/{gsub(/[^0-9]/,"",$3); print $3; exit}'; }

capture_baseline() {
  local head total elig present
  total="$(Q_ART "select count(*) from tombstones;")"
  elig="$(Q_ART "select count(*) from tombstones where trashed_at < now() - interval '7 days';")"
  head="$(Q_ART "select site || '/' || id from tombstones where id <> '' order by trashed_at limit 1;")"
  present=0
  [[ -n "$head" ]] && present=1
  mkdir -p "$(dirname "$BASE")"
  {
    printf 'captured_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'tombstones_total=%s\n' "$total"
    printf 'tombstones_eligible=%s\n' "$elig"
    printf 'head_deploy=%s\n' "$head"
    printf 'head_present=%s\n' "$present"
    printf 'sentry_ARTEMIS_J_events=%s\n' "$(EV_CAP ARTEMIS-J)"
    printf 'sentry_ARTEMIS_K_events=%s\n' "$(EV_CAP ARTEMIS-K)"
  } >"$BASE"
  printf 'baseline written to %s\n' "$BASE"
  cat "$BASE"
}

if [[ "${1-}" == "--capture" ]]; then
  capture_baseline
  exit 0
fi

if [[ ! -r "$BASE" ]]; then
  printf 'FAIL: no baseline at %s. Run "%s --capture" before the 03:00 UTC purge.\n' \
    "$BASE" "${BASH_SOURCE[0]}" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$BASE"

for k in captured_utc tombstones_total tombstones_eligible head_deploy head_present \
  sentry_ARTEMIS_J_events sentry_ARTEMIS_K_events; do
  if [[ -z "${!k-}" ]]; then
    printf 'FAIL: baseline %s is missing key %s — regenerate it\n' "$BASE" "$k" >&2
    exit 2
  fi
done

if [[ "$head_deploy" != */* || "$head_deploy" == *"'"* ]]; then
  printf 'FAIL: head_deploy is not <site>/<id> or contains a quote: %s\n' "$head_deploy" >&2
  exit 2
fi
HEAD_SITE="${head_deploy%%/*}"
HEAD_ID="${head_deploy#*/}"

Q() {
  local out
  out="$(kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -tAc "$1" 2>&1 | tr -d '[:space:]')"
  if [[ ! "$out" =~ ^[0-9]+$ ]]; then
    printf 'QUERY_FAILED'
    return 1
  fi
  printf '%s' "$out"
}
EV() { sentry issue view "$1" 2>/dev/null | awk -F'│' '/Events/{gsub(/[^0-9]/,"",$3); print $3; exit}'; }

printf 'artemis purge gate — %s\n' "$(date -u +%FT%TZ)"
printf 'baseline captured %s\n\n' "$captured_utc"

printf '[1] has tombstone-purge REACHED A TERMINAL STATUS since the baseline?\n'
ROWS="$(kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d hatchet -tAc \
  "SELECT r.readable_status FROM v1_runs_olap r JOIN \"Workflow\" w ON w.id = r.workflow_id
   WHERE w.name = 'tombstone-purge'
     AND r.inserted_at > timestamptz '$captured_utc'
   ORDER BY r.inserted_at" 2>&1)"
if [[ -z "$ROWS" ]]; then
  printf '  PENDING — no purge run since the baseline. Every comparison below would be\n'
  printf '  vacuous: it would measure the snapshot-to-now gap, not a purge.\n'
  exit 3
fi
while IFS= read -r st; do
  [[ -z "$st" ]] && continue
  if [[ ! "$st" =~ ^(QUEUED|RUNNING|$TERMINAL)$ ]]; then
    printf '  FAIL — the run-history query did not return statuses. Query problem, not a\n' >&2
    printf '  verdict:\n' >&2
    printf '%s\n' "$ROWS" | head -5 | sed 's/^/    /' >&2
    exit 2
  fi
done <<<"$ROWS"
N_RUNS="$(grep -c . <<<"$ROWS")"
printf '  runs since %s: %s [%s]\n' "$captured_utc" "$N_RUNS" "$(tr '\n' ' ' <<<"$ROWS")"
if grep -qE '^(QUEUED|RUNNING)$' <<<"$ROWS"; then
  printf '  PENDING — a run is still in flight. gcRunBudget is 30m (gcworkflows.go:77), and\n'
  printf '  on 2026-09-08 the purge wrote audit rows until 03:10:43Z. A verdict now would\n'
  printf '  read a half-drained backlog.\n'
  exit 3
fi
if [[ "$N_RUNS" != "1" ]]; then
  printf '  FAIL — %s fires, not 1. This is the runbook 09 C.6 double-fire condition on a\n' "$N_RUNS" >&2
  printf '  workflow that performs destructive R2 deletes. Treat as urgent.\n' >&2
  FAILED=1
fi
if ! grep -q '^COMPLETED$' <<<"$ROWS"; then
  printf '  ATTENTION — the run did not COMPLETE. That is the run-level N4 signature: the\n' >&2
  printf '  2026-09-07 and 2026-09-08 purges both ended FAILED.\n' >&2
  FAILED=1
fi

LOGS="$(kubectl -n artemis logs -l app.kubernetes.io/component=deploy-proxy --since=90m --tail=-1 2>/dev/null)"

printf '\n[1b] blast cap — BlastCap defaults to 10 (config.go:194) and no CLEANUP_BLAST_CAP\n'
printf '  overrides it, so 12 eligible tombstones are CAPPED. The remainder is by design.\n'
CAPLINE="$(grep -o '"msg":"gc\.tombstone-purge\.capped"[^}]*' <<<"$LOGS" | tail -1)"
ATTEMPTED=""
if [[ -n "$CAPLINE" ]]; then
  printf '  %s\n' "$(cut -c1-210 <<<"$CAPLINE")"
  ATTEMPTED="$(sed -n 's/.*"cap":\([0-9]*\).*/\1/p' <<<"$CAPLINE")"
  printf '  attempted %s of %s eligible — a leftover backlog is NOT a failure\n' \
    "$ATTEMPTED" "$(sed -n 's/.*"expired":\([0-9]*\).*/\1/p' <<<"$CAPLINE")"
else
  printf '  no capped warning in the 90m window. Either eligible <= cap, or the container\n'
  printf '  restarted and took the logs with it — check [0] equivalents in R6.\n'
fi

printf '\n[2] tombstone backlog vs baseline\n'
NOW_TOTAL="$(Q "select count(*) from tombstones;")" || {
  printf '  FAIL — query failed\n' >&2
  exit 2
}
NOW_ELIG="$(Q "select count(*) from tombstones where trashed_at < now() - interval '7 days';")" || {
  printf '  FAIL — query failed\n' >&2
  exit 2
}
NEW_T="$(Q "select count(*) from tombstones where trashed_at > timestamptz '$captured_utc';")" || NEW_T=""
printf '  total     %s -> %s\n' "$tombstones_total" "$NOW_TOTAL"
printf '  eligible  %s -> %s\n' "$tombstones_eligible" "$NOW_ELIG"
printf '  created since the baseline: %s\n' "${NEW_T:-unknown}"
printf '  read the ELIGIBLE line for the purge, not the total. The same cron runs\n'
printf '  runPendingSweep (gcworkflows.go:207), which CREATES tombstones through SiteGC\n'
printf '  while the purge removes them, so the total moves both ways in one run.\n'

printf '\n[3] the deploy that failed twice: %s\n' "$head_deploy"
HEAD_NOW="$(Q "select count(*) from tombstones where site='$HEAD_SITE' and id='$HEAD_ID';")" ||
  {
    printf '  FAIL — query failed\n' >&2
    exit 2
  }
if [[ "$head_present" == "1" && "$HEAD_NOW" == "0" ]]; then
  printf '  PURGED — the 429 did not recur on this prefix\n'
elif [[ "$HEAD_NOW" == "1" ]]; then
  printf '  STILL PRESENT — this prefix survived the purge run again\n'
  FAILED=1
else
  printf '  was already absent at baseline (head_present=%s)\n' "$head_present"
fi

printf '\n[4] gc.purge audit rows written by this run\n'
printf '  the cron audits gc.purge (gcwire.go:80 via gcwire.go:331), NOT gc.tombstone —\n'
printf '  gc.tombstone belongs to SiteGC (gcwire.go:304) and only appears when the pending\n'
printf '  sweep has a site to collect.\n'
AUD="$(Q "select count(*) from audit_log where action='gc.purge' and occurred_at > timestamptz '$captured_utc';")" || {
  printf '  FAIL — query failed\n' >&2
  exit 2
}
printf '  gc.purge rows since the baseline: %s (attempted %s)\n' "$AUD" "${ATTEMPTED:-unknown}"
if [[ "$AUD" == "0" ]]; then
  printf '  ATTENTION — the purge deleted nothing at all. Every selected prefix failed.\n' >&2
  FAILED=1
elif [[ -z "$ATTEMPTED" ]]; then
  printf '  purged %s, but the cap line is missing so there is no denominator to judge it\n' "$AUD"
elif [[ "$AUD" == "$ATTEMPTED" ]]; then
  printf '  PASS — every attempted prefix purged. ARTEMIS-J did not recur.\n'
elif [[ "$AUD" -lt "$ATTEMPTED" ]]; then
  printf '  ATTENTION — %s of %s purged, so %s prefix(es) failed. On 2026-09-08 the single\n' >&2 \
    "$AUD" "$ATTEMPTED" "$((ATTEMPTED - AUD))"
  printf '  failure was ARTEMIS-J: DeleteObjects 429 ServiceUnavailable "Reduce your\n' >&2
  printf '  concurrent request rate for the same object" on the head prefix. r2.go has no\n' >&2
  printf '  transient classification and no retry, so it aborts the prefix outright.\n' >&2
  FAILED=1
else
  printf '  ATTENTION — %s purged exceeds %s attempted. Suspect a double fire.\n' >&2 "$AUD" "$ATTEMPTED"
  FAILED=1
fi

printf '\n[5] Sentry event counts vs baseline\n'
for pair in "ARTEMIS-J:$sentry_ARTEMIS_J_events" "ARTEMIS-K:$sentry_ARTEMIS_K_events"; do
  id="${pair%%:*}"
  was="${pair##*:}"
  now="$(EV "$id")"
  if [[ -z "$now" ]]; then
    printf '  %s: could not read the event count (sentry CLI)\n' "$id"
    continue
  fi
  printf '  %s: %s -> %s' "$id" "$was" "$now"
  if [[ "$now" -gt "$was" ]]; then
    printf '  RECURRED\n'
    FAILED=1
  else
    printf '  quiet\n'
  fi
done

printf '\n[6] purge log signatures in the last 90m\n'
if [[ -z "$LOGS" ]]; then
  printf '  no logs in the window — check pod restarts before reading anything into this\n'
else
  HITS="$(grep -oE '"msg":"gc\.tombstone-purge[a-z._]*"' <<<"$LOGS" | sort | uniq -c)"
  if [[ -n "$HITS" ]]; then printf '%s\n' "$HITS" | sed 's/^/  /'; else printf '  none\n'; fi
  FAILLINE="$(grep -o '"msg":"gc\.tombstone-purge\.site_failed"[^}]*' <<<"$LOGS" | tail -1)"
  if [[ -n "$FAILLINE" ]]; then
    printf '  the error text, which is the whole point of this check:\n'
    printf '  %s\n' "$(cut -c1-300 <<<"$FAILLINE")"
  fi
fi

printf '\npurge gate exit=%s\n' "$FAILED"
exit "$FAILED"
