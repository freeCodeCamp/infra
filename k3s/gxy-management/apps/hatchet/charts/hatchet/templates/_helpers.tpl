{{/*
Labels. selectorLabels deliberately includes the component so every
selector consumer (Service, netpol endpointSelector) is scoped per
component from day one — the artemis chart's bare name+instance
selectors matched sibling pods (artemis dossier B12).
*/}}

{{- define "hatchet.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hatchet.labels" -}}
helm.sh/chart: {{ include "hatchet.chart" . }}
app.kubernetes.io/name: hatchet-engine
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: universe-static-apps
{{- end -}}

{{- define "hatchet.engineSelectorLabels" -}}
app.kubernetes.io/name: hatchet-engine
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: engine
{{- end -}}
