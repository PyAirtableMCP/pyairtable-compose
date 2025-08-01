{{/*
Expand the name of the chart.
*/}}
{{- define "pyairtable-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pyairtable-stack.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pyairtable-stack.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pyairtable-stack.labels" -}}
helm.sh/chart: {{ include "pyairtable-stack.chart" . }}
{{ include "pyairtable-stack.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pyairtable-stack.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pyairtable-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create service selector labels for a specific service
Usage: {{ include "pyairtable-stack.serviceSelectorLabels" (dict "root" . "component" "service-name") }}
*/}}
{{- define "pyairtable-stack.serviceSelectorLabels" -}}
app.kubernetes.io/name: {{ include "pyairtable-stack.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pyairtable-stack.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pyairtable-stack.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common environment variables from secrets
*/}}
{{- define "pyairtable-stack.commonSecretEnvVars" -}}
- name: API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-secrets
      key: API_KEY
- name: POSTGRES_DB
  valueFrom:
    secretKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-secrets
      key: POSTGRES_DB
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-secrets
      key: POSTGRES_USER
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-secrets
      key: POSTGRES_PASSWORD
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-secrets
      key: REDIS_PASSWORD
{{- end }}

{{/*
Common environment variables from configmap
*/}}
{{- define "pyairtable-stack.commonConfigEnvVars" -}}
- name: ENVIRONMENT
  valueFrom:
    configMapKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-config
      key: ENVIRONMENT
- name: LOG_LEVEL
  valueFrom:
    configMapKeyRef:
      name: {{ include "pyairtable-stack.fullname" . }}-config
      key: LOG_LEVEL
{{- end }}

{{/*
Construct Docker image name with optional registry
*/}}
{{- define "pyairtable-stack.image" -}}
{{- if .registry -}}
{{- printf "%s/%s:%s" .registry .repository .tag -}}
{{- else -}}
{{- printf "%s:%s" .repository .tag -}}
{{- end -}}
{{- end }}