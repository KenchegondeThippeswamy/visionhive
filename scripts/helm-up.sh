#!/usr/bin/env bash
# Deploys VisionHive to Minikube with Helm (instead of kubectl apply -k).
# Run ./scripts/k8s-down.sh first if the Phase 7 manifests are deployed: one copy at a time.
set -euo pipefail
cd "$(dirname "$0")/.."
NS=visionhive

for tool in docker kubectl minikube helm openssl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool"; exit 1; }
done

if kubectl get deployment api-gateway -n "$NS" >/dev/null 2>&1 && \
   [ -z "$(kubectl get deployment api-gateway -n "$NS" -o jsonpath='{.metadata.labels.helm\.sh/chart}' 2>/dev/null)" ]; then
  echo "The Phase 7 manifests are still deployed. Run ./scripts/k8s-down.sh first."; exit 1
fi

if ! minikube status >/dev/null 2>&1; then
  echo "== starting minikube"
  minikube start --driver=docker --cpus="${MK_CPUS:-4}" --memory="${MK_MEMORY:-6144}"
fi
minikube addons enable ingress >/dev/null
minikube addons enable metrics-server >/dev/null
kubectl -n ingress-nginx wait --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=240s

echo "== building images inside minikube"
for s in api-gateway upload-svc ingest-worker; do
  minikube image build -t "visionhive/$s:local" "services/$s"
done

echo "== namespace and secrets (never in Git)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" get secret db-credentials >/dev/null 2>&1 || \
  kubectl -n "$NS" create secret generic db-credentials --from-literal=password="$(openssl rand -hex 16)"
kubectl -n "$NS" get secret aws-local-credentials >/dev/null 2>&1 || \
  kubectl -n "$NS" create secret generic aws-local-credentials \
    --from-literal=AWS_ACCESS_KEY_ID=test --from-literal=AWS_SECRET_ACCESS_KEY=test

echo "== helm upgrade --install"
helm upgrade --install visionhive helm/visionhive -n "$NS" \
  -f helm/visionhive/values-minikube.yaml \
  --set-string global.restartToken="$(date +%s)" \
  --wait --timeout 8m
helm -n "$NS" list
kubectl -n "$NS" get pods
echo
echo "Next: ./scripts/k8s-test.sh"
