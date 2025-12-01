{{/*
Expand the name of the chart.
*/}}
{{- define "app-template.name" -}}
{{- default .Chart.Name .Values.app.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "app-template.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Values.app.name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app-template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "app-template.labels" -}}
helm.sh/chart: {{ include "app-template.chart" . }}
{{ include "app-template.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: web-application
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app-template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app-template.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "app-template.fullname" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "app-template.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "app-template.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Istio sidecar annotations
*/}}
{{- define "app-template.istioAnnotations" -}}
{{- if .Values.istio.enabled }}
sidecar.istio.io/inject: {{ .Values.istio.sidecar.inject | quote }}
sidecar.istio.io/proxyCPU: {{ .Values.istio.sidecar.proxyCPU | quote }}
sidecar.istio.io/proxyCPULimit: {{ .Values.istio.sidecar.proxyCPULimit | quote }}
sidecar.istio.io/proxyMemory: {{ .Values.istio.sidecar.proxyMemory | quote }}
sidecar.istio.io/proxyMemoryLimit: {{ .Values.istio.sidecar.proxyMemoryLimit | quote }}
{{- end }}
{{- end }}

{{/*
Service port - use proxy port if oauth2-proxy is enabled
*/}}
{{- define "app-template.servicePort" -}}
{{- if .Values.oauth2Proxy.enabled }}
4180
{{- else }}
{{ .Values.app.containerPort }}
{{- end }}
{{- end }}
