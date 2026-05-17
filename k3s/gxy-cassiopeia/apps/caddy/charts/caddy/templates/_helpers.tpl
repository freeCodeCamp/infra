{{/*
Standard name + labels for the caddy chart. Mirrors the layout used
by the artemis + valkey charts so `helm list` / `kubectl get` queries
return the same shape across pillars.
*/}}

{{- define "caddy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "caddy.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "caddy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "caddy.labels" -}}
helm.sh/chart: {{ include "caddy.chart" . }}
{{ include "caddy.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: static-serve
app.kubernetes.io/part-of: universe-static-apps
{{- end -}}

{{- define "caddy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "caddy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
