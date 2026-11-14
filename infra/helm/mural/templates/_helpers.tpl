{{/* Chart name, overridable. */}}
{{- define "mural.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Base name of every resource: the release name, unless overridden. */}}
{{- define "mural.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 50 | trimSuffix "-" -}}
{{- else if contains (include "mural.name" .) .Release.Name -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "mural.name" .) | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels shared by every resource. */}}
{{- define "mural.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ include "mural.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels of one component.
Usage: include "mural.selectorLabels" (dict "ctx" . "component" "api")
*/}}
{{- define "mural.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mural.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "mural.api.fullname" -}}{{ include "mural.fullname" . }}-api{{- end -}}
{{- define "mural.web.fullname" -}}{{ include "mural.fullname" . }}-web{{- end -}}
{{- define "mural.postgres.fullname" -}}{{ include "mural.fullname" . }}-postgres{{- end -}}
{{- define "mural.config.fullname" -}}{{ include "mural.fullname" . }}-config{{- end -}}
{{- define "mural.secret.fullname" -}}{{ include "mural.fullname" . }}-db{{- end -}}
{{- define "mural.migrations.fullname" -}}{{ include "mural.fullname" . }}-migrations{{- end -}}

{{/* Database password; rendering fails when it is not supplied. */}}
{{- define "mural.postgres.password" -}}
{{- required "postgres.password is required (use --set postgres.password=... or the Terraform variable db_password)" .Values.postgres.password -}}
{{- end -}}

{{/*
Connection string consumed by the API. The password is percent-encoded so that
reserved characters do not break the URL.
*/}}
{{- define "mural.databaseUrl" -}}
{{- $password := include "mural.postgres.password" . | urlquery | replace "+" "%20" -}}
{{- printf "postgres://%s:%s@%s:%v/%s?sslmode=disable" .Values.postgres.user $password (include "mural.postgres.fullname" .) .Values.postgres.port .Values.postgres.database -}}
{{- end -}}
