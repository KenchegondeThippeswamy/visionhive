#!/usr/bin/env bash
# Starts Minikube, builds the three images inside it, creates the secrets and deploys VisionHive.
# Safe to run again. Needs: docker, kubectl, minikube (see docs/phase7-guide.md, part 1).
# Stop the Docker Compose stack first (make down), because both use ports 8080 and 4566.
set -euo pipefail
cd "$(dirname "$0")/.."
NS=visionhive

for tool in docker kubectl minikube openssl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool (see docs/phase7-guide.md, part 1)"; exit 1; }
done

if ! minikube status >/dev/null 2>&1; then
  echo "== starting minikube"
  minikube start --driver=docker --cpus="${MK_CPUS:-4}" --memory="${MK_MEMORY:-6144}"
fi

echo "== enabling addons (ingress controller, metrics for the autoscaler)"
minikube addons enable ingress >/dev/null
minikube addons enable metrics-server >/dev/null
kubectl -n ingress-nginx wait --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=240s

echo "== building images inside minikube (no registry needed)"
for s in api-gateway upload-svc ingest-worker; do
  minikube image build -t "visionhive/$s:local" "services/$s"
done

echo "== creating namespace and secrets (never stored in Git)"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if ! kubectl -n "$NS" get secret db-credentials >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic db-credentials --from-literal=password="$(openssl rand -hex 16)"
fi
if ! kubectl -n "$NS" get secret aws-local-credentials >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic aws-local-credentials \
    --from-literal=AWS_ACCESS_KEY_ID=test --from-literal=AWS_SECRET_ACCESS_KEY=test
fi

echo "== applying manifests"
ok=0
for _ in 1 2 3; do
  if kubectl apply -k k8s; then ok=1; break; fi
  echo "apply failed (the ingress webhook may still be starting), retrying in 10 seconds"
  sleep 10
done
[ "$ok" -eq 1 ] || { echo "kubectl apply failed"; exit 1; }

# The image tag is always "local", so restart the pods to pick up freshly built images.
kubectl -n "$NS" rollout restart deployment/api-gateway deployment/upload-svc deployment/ingest-worker >/dev/null

echo "== waiting for everything to be ready"
kubectl -n "$NS" rollout status statefulset/postgres --timeout=300s
kubectl -n "$NS" rollout status deployment/localstack --timeout=300s
for d in api-gateway upload-svc ingest-worker; do
  kubectl -n "$NS" rollout status "deployment/$d" --timeout=300s
done
kubectl -n "$NS" get pods
echo
echo "Next: ./scripts/k8s-test.sh"
