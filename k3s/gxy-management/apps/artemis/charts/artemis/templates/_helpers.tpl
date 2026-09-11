{{/*
Standard name + labels for the artemis chart. Mirrors the layout used
by the caddy + valkey charts so `helm list` / `kubectl get` queries
return the same shape across pillars.
*/}}

{{- define "artemis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "artemis.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "artemis.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "artemis.labels" -}}
helm.sh/chart: {{ include "artemis.chart" . }}
{{ include "artemis.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: universe-static-apps
{{- end -}}

{{- define "artemis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "artemis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "artemis.sentryCheckin" -}}
# docs.sentry.io/product/crons/getting-started/http/
sentry_checkin() {
  local status="$1" dsn key host proj url
  dsn="${SENTRY_DSN:-}"; dsn="${dsn//[[:space:]]/}"
  [ -n "${dsn}" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0
  key="${dsn#*//}"; key="${key%%@*}"
  host="${dsn#*@}"; host="${host%%/*}"
  proj="${dsn##*/}"
  url="https://${host}/api/${proj}/cron/${MONITOR_SLUG:-unknown}/${key}/?environment=${ENVIRONMENT:-production}"
  if [ "${status}" = "in_progress" ]; then
    curl -fsS -m 10 -o /dev/null -X POST "${url}" \
      -H 'Content-Type: application/json' \
      --data-raw "{\"status\":\"in_progress\",\"monitor_config\":{\"schedule\":{\"type\":\"crontab\",\"value\":\"${MONITOR_SCHEDULE:-}\"},\"checkin_margin\":${MONITOR_CHECKIN_MARGIN:-10},\"max_runtime\":${MONITOR_MAX_RUNTIME:-25},\"failure_issue_threshold\":${MONITOR_FAILURE_THRESHOLD:-2},\"timezone\":\"${MONITOR_TIMEZONE:-UTC}\"}}" \
      || echo "sentry check-in ${status} failed" >&2
  else
    curl -fsS -m 10 -o /dev/null "${url}&status=${status}" \
      || echo "sentry check-in ${status} failed" >&2
  fi
  return 0
}
{{- end -}}
