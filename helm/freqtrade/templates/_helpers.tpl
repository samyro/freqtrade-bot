{{- define "freqtrade.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "freqtrade.fullname" -}}
{{- include "freqtrade.name" . -}}
{{- end -}}

{{- define "freqtrade.labels" -}}
app.kubernetes.io/name: {{ include "freqtrade.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "freqtrade.selectorLabels" -}}
app.kubernetes.io/name: {{ include "freqtrade.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
