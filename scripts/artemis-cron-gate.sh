#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${KUBECONFIG:=$HERE/../k3s/gxy-management/.kubeconfig.yaml}"
export KUBECONFIG
PSQL=(kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d artemis -tAc)
TODAY="${ARTEMIS_GATE_DAY:-$(date -u +%F)}"
FAILED=0
PENDING=0
PURGE_TERMINAL=0

Q() {
  local out
  out="$("${PSQL[@]}" "$1" 2>&1 | tr -d '[:space:]')"
  if [[ ! "$out" =~ ^[0-9]+$ ]]; then
    printf 'QUERY_FAILED:%s' "$out"
    return 1
  fi
  printf '%s' "$out"
}

printf 'artemis cron gate — %s (UTC day %s)\n\n' "$(date -u +%FT%TZ)" "$TODAY"

printf '[0] pod state — the log checks below are only as good as the container lifetime\n'
PODS="$(kubectl -n artemis get pods -l app.kubernetes.io/component=deploy-proxy \
  -o 'custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp' \
  --no-headers 2>&1)"
printf '%s\n' "$PODS" | sed 's/^/  /'
if grep -qE '[[:space:]]false[[:space:]]' <<<"$PODS"; then
  printf '  FAIL — a pod is not ready\n' >&2
  FAILED=1
fi

printf '\n[1] runbook 09 C.6 double-fire gate + terminal status\n'
ROWS="$(kubectl -n artemis exec artemis-postgresql-0 -- psql -U postgres -d hatchet -tAc \
  "SELECT date_trunc('hour', r.inserted_at), w.name, count(*),
          string_agg(r.readable_status::text, '/' ORDER BY r.inserted_at)
   FROM v1_runs_olap r JOIN \"Workflow\" w ON w.id = r.workflow_id
   WHERE r.inserted_at > now() - interval '2 days'
     AND w.name IN ('tombstone-purge', 'drift-detect')
   GROUP BY 1, 2 ORDER BY 1" 2>&1)"
SHAPE_OK=1
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}\|[a-z-]+\|[0-9]+\|[A-Z/]+$ ]] || SHAPE_OK=0
done <<<"$ROWS"
if [[ -z "$ROWS" || "$SHAPE_OK" != "1" ]]; then
  printf '  FAIL — the run-history query did not return rows in the expected shape.\n' >&2
  printf '  This is NOT a double-fire verdict; it is a query or cluster problem:\n' >&2
  printf '%s\n' "${ROWS:-<empty>}" | head -5 | sed 's/^/    /' >&2
  FAILED=1
else
  printf '%s\n' "$ROWS" | sed 's/^/  /'
  TONIGHT="$(awk -F'|' -v d="$TODAY " 'index($1, d) == 1 {print}' <<<"$ROWS")"
  DUPES="$(awk -F'|' '$3 != 1 {print}' <<<"$TONIGHT")"
  PURGE_ROW="$(awk -F'|' -v d="$TODAY 03:00:00+00" '$1 == d && $2 == "tombstone-purge" {print $4}' <<<"$ROWS")"
  DRIFT_ROW="$(awk -F'|' -v d="$TODAY 04:00:00+00" '$1 == d && $2 == "drift-detect" {print $4}' <<<"$ROWS")"
  if [[ -n "$DUPES" ]]; then
    printf '  FAIL — a cron double-fired tonight. hatchet-engine runs 2 replicas today, so\n' >&2
    printf '  this is the live risk runbook 09 C.6 names. Roll the engine to one replica\n' >&2
    printf '  (runbook 09 E) and check the audit rows for duplicate deletes FIRST:\n' >&2
    printf '%s\n' "$DUPES" | sed 's/^/    /' >&2
    FAILED=1
  elif [[ -z "$PURGE_ROW" || -z "$DRIFT_ROW" ]]; then
    printf '  PENDING — one of tonight'"'"'s buckets is missing (purge=%s drift=%s).\n' \
      "${PURGE_ROW:-absent}" "${DRIFT_ROW:-absent}"
    printf '  Old rows all reading 1 is NOT a pass for tonight.\n'
    PENDING=1
  elif [[ "$PURGE_ROW" =~ (QUEUED|RUNNING) || "$DRIFT_ROW" =~ (QUEUED|RUNNING) ]]; then
    printf '  PENDING — a run is still in flight (purge=%s drift=%s). Both budgets are 30m\n' \
      "$PURGE_ROW" "$DRIFT_ROW"
    printf '  (gcworkflows.go:75-77), so a verdict now can precede the work.\n'
    PENDING=1
  else
    printf '  one fire per cron tonight: purge=%s drift=%s\n' "$PURGE_ROW" "$DRIFT_ROW"
    PURGE_TERMINAL=1
    if [[ "$PURGE_ROW" != "COMPLETED" ]]; then
      printf '  ATTENTION — the 03:00 purge did not COMPLETE. Same as 2026-09-07 and\n' >&2
      printf '  2026-09-08. This is the N4 signature at run level, not a cron fault.\n' >&2
      FAILED=1
    fi
    if [[ "$DRIFT_ROW" != "COMPLETED" ]]; then
      printf '  FAIL — the 04:00 drift-detect did not COMPLETE (%s).\n' "$DRIFT_ROW" >&2
      FAILED=1
    fi
    [[ "$PURGE_ROW$DRIFT_ROW" == "COMPLETEDCOMPLETED" ]] && printf '  PASS\n'
  fi
fi

printf '\n[2] the 03:00 tombstone-purge left an audit row\n'
printf '  the cron audits gc.purge (gcwire.go:80 via gcwire.go:331). gc.tombstone is\n'
printf '  SiteGC (gcwire.go:304) and appears only when the pending sweep has a site.\n'
if [[ "$PURGE_TERMINAL" != "1" ]]; then
  printf '  PENDING — tonight'"'"'s purge has not reached a terminal status, so a zero count\n'
  printf '  here means "not yet", not "deleted nothing".\n'
  PENDING=1
elif PURGED="$(Q "select count(*) from audit_log where action='gc.purge' and occurred_at > timestamptz '$TODAY 02:00:00+00';")"; then
  printf '  gc.purge audit rows since %s 02:00Z: %s\n' "$TODAY" "$PURGED"
  if [[ "$PURGED" == "0" ]]; then
    printf '  ATTENTION — the purge deleted nothing. That is the N4 signature: r2.go:284\n' >&2
    printf '  DeletePrefix returns on the first batch error, so a 429 aborts the prefix.\n' >&2
    FAILED=1
  else
    printf '  PASS\n'
  fi
else
  printf '  FAIL — %s\n' "$PURGED" >&2
  FAILED=1
fi

printf '\n[3] drift threshold 25 -> 1 (driftalert.go:24)\n'
printf '  D1 ruling: let it alert. Expect op=drift.reclaimable.\n'
LOGS="$(kubectl -n artemis logs -l app.kubernetes.io/component=deploy-proxy --since=180m --tail=-1 2>/dev/null)"
DRIFT_LINE="$(grep -o '"msg":"drift.detected"[^}]*' <<<"$LOGS" | tail -1)"
DRIFT_RAN=0
if [[ -n "$DRIFT_LINE" ]]; then
  DRIFT_RAN=1
  printf '  %s\n' "$(cut -c1-190 <<<"$DRIFT_LINE")"
  if grep -q '"op":"drift.reclaimable"' <<<"$DRIFT_LINE"; then
    printf '  PASS — op=drift.reclaimable, exactly what the new threshold predicts\n'
  else
    printf '  ATTENTION — drift.detected fired on a HIGHER-PRIORITY op, which MASKS the\n' >&2
    printf '  reclaimable signal. classifyDrift is a first-match chain: selfcheck, then\n' >&2
    printf '  aliased_missing, then orphan_aliases, then unreadable, and only then\n' >&2
    printf '  reclaimable. Read the op above and treat it on its own merits.\n' >&2
    FAILED=1
  fi
elif grep -q '"msg":"drift.clean"' <<<"$LOGS"; then
  DRIFT_RAN=1
  printf '  %s\n' "$(grep -o '"msg":"drift.clean"[^}]*' <<<"$LOGS" | tail -1 | cut -c1-190)"
  printf '  PASS (clean) — reclaimable reached 0, so nothing was left to alert on\n'
else
  printf '  PENDING — neither drift.detected nor drift.clean in the last 180m.\n'
  printf '  Check [0] for a restart before concluding the cron did not fire.\n'
  PENDING=1
fi

printf '\n[4] nightly reclaim-ledger audit (driftalert.go:170)\n'
if [[ "$DRIFT_RAN" != "1" ]]; then
  printf '  PENDING — drift-detect did not log in the window, so silence proves nothing\n'
  PENDING=1
elif grep -q '"msg":"drift.ledger"' <<<"$LOGS"; then
  printf '  ATTENTION — drift.ledger fired, so the ledger is inconsistent:\n' >&2
  printf '  %s\n' "$(grep -o '"msg":"drift.ledger"[^}]*' <<<"$LOGS" | tail -1 | cut -c1-190)" >&2
  FAILED=1
else
  printf '  PASS — the audit ran (alertOnLedger is deferred from alertOnDrift) and stayed silent\n'
fi

printf '\n[5] pending deploys — a count alone renders no verdict, so bound it by age\n'
if PEND="$(Q "select count(*) from deploys where state='pending';")"; then
  STALE="$(Q "select count(*) from deploys where state='pending' and created_at < now() - interval '24 hours';")" || STALE=""
  printf '  pending: %s (older than 24h: %s)\n' "$PEND" "${STALE:-unknown}"
  if [[ -n "$STALE" && "$STALE" != "0" ]]; then
    printf '  ATTENTION — %s pending deploy(s) older than 24h. Every site row is state=active\n' "$STALE"
    printf '  and none is reserved, so LedgerAudit (pg/ledgeraudit.go:29) cannot see these and\n'
    printf '  drift.ledger will stay silent. They are a separate leak, not a [4] failure.\n'
  fi
else
  printf '  FAIL — %s\n' "$PEND" >&2
  FAILED=1
fi

printf '\n[6] Sentry, unresolved\n'
if ! command -v sentry >/dev/null; then
  printf '  sentry CLI not on PATH\n'
else
  SENT="$(sentry issue list freecodecamp/artemis --query "is:unresolved" 2>&1 | grep -E 'ARTEMIS-' || true)"
  if [[ -z "$SENT" ]]; then
    printf '  no unresolved issues, or the CLI failed — verify by hand\n'
  else
    printf '%s\n' "$SENT" | cut -c1-120 | sed 's/^/  /'
  fi
fi

if [[ "$FAILED" == "0" && "$PENDING" == "1" ]]; then
  printf '\ncron gate exit=3 (PENDING — nothing failed, the night is not over)\n'
  exit 3
fi
printf '\ncron gate exit=%s\n' "$FAILED"
exit "$FAILED"
