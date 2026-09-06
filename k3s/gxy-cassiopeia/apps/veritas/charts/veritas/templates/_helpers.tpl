{{/*
Standard name + labels for the veritas chart. Mirrors the layout used
by the artemis + caddy + valkey charts so `helm list` / `kubectl get`
queries return the same shape across pillars.
*/}}

{{- define "veritas.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "veritas.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "veritas.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "veritas.labels" -}}
helm.sh/chart: {{ include "veritas.chart" . }}
{{ include "veritas.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: auth-idp
app.kubernetes.io/part-of: universe-platform
{{- end -}}

{{- define "veritas.selectorLabels" -}}
app.kubernetes.io/name: {{ include "veritas.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
CNPG cluster name — distinct from the app Deployment name so the two
resources don't collide on .Release.Name. Pattern matches CNPG examples.
*/}}
{{- define "veritas.cnpg.name" -}}
{{- printf "%s-pg" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
CNPG-generated app-user secret name. CNPG creates this Secret
automatically from `bootstrap.initdb.owner` — convention is `<cluster>-app`.
Holds keys: dbname, host, password, port, uri, user.
*/}}
{{- define "veritas.cnpg.appSecret" -}}
{{- printf "%s-app" (include "veritas.cnpg.name" .) -}}
{{- end -}}
