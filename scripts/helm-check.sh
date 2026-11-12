#!/usr/bin/env bash
# Checks the chart offline: lint, render and schema-check it with every values file.
# Needs helm. Uses kubeconform if installed, otherwise its Docker image.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
CHART=helm/visionhive
command -v helm >/dev/null 2>&1 || { echo "helm is not installed (see docs/phase8-guide.md, part 2)"; exit 1; }

CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
if command -v kubeconform >/dev/null 2>&1; then
  KC=(kubeconform -strict -summary -schema-location default -schema-location "$CATALOG")
elif command -v docker >/dev/null 2>&1; then
  KC=(docker run --rm -i ghcr.io/yannh/kubeconform:v0.6.7 -strict -summary -schema-location default -schema-location "$CATALOG")
else
  echo "Install kubeconform or Docker to schema-check the rendered YAML"; exit 1
fi

fail=0
for env in minikube dev qa prod; do
  f="$CHART/values-$env.yaml"
  echo "== $env"
  helm lint --strict "$CHART" -f "$f" --set image.tag=ci1234567 || fail=1
  helm template visionhive "$CHART" -n visionhive -f "$f" --set image.tag=ci1234567 \
    --set monitoring.serviceMonitor.enabled=true | "${KC[@]}" || fail=1
done
if [ "$fail" -eq 0 ]; then echo "ALL GOOD"; else echo "PROBLEMS FOUND"; exit 1; fi
