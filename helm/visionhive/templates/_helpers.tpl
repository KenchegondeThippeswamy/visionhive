{{/* Labels added to every object. */}}
{{- define "visionhive.labels" -}}
app.kubernetes.io/part-of: visionhive
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end }}

{{/* Full image reference: [registry/]repositoryPrefix/service:tag. The tag is mandatory. */}}
{{- define "visionhive.image" -}}
{{- $tag := required "image.tag must be set (the commit tag that CI pushed, or 'local' on Minikube)" (default .root.Values.image.tag .svc.tag) -}}
{{- $repo := printf "%s/%s" .root.Values.image.repositoryPrefix .name -}}
{{- if .root.Values.image.registry -}}
{{- printf "%s/%s:%s" .root.Values.image.registry $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}
