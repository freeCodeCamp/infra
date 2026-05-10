{{/*
Standard name + labels for the valkey chart. Mirrors the layout used
by the artemis chart so `helm list` / `kubectl get` queries return
the same shape across pillars.
*/}}

{{- define "valkey.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "valkey.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "valkey.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "valkey.labels" -}}
helm.sh/chart: {{ include "valkey.chart" . }}
{{ include "valkey.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: registry-kv
app.kubernetes.io/part-of: universe-static-apps
{{- end -}}

{{- define "valkey.selectorLabels" -}}
app.kubernetes.io/name: {{ include "valkey.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
