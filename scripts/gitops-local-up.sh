#!/usr/bin/env bash
# Starts Minikube, installs Argo CD and gives it the repository (project and app of apps).
# The gitops/ folder and the chart must already be merged into the dev branch on GitHub: Argo CD reads them from there.
set -euo pipefail
cd "$(dirname "$0")/.."
NS=visionhive
ARGOCD_CHART_VERSION=10.18.0

for tool in kubectl minikube helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool"; exit 1; }
done

if ! minikube status >/dev/null 2>&1; then
  echo "== starting minikube"
  minikube start --driver=docker --cpus="${MK_CPUS:-4}" --memory="${MK_MEMORY:-6144}"
fi
kubectl config use-context minikube >/dev/null
minikube addons enable ingress >/dev/null
minikube addons enable metrics-server >/dev/null
kubectl -n ingress-nginx wait --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=240s

# Argo CD must be the only owner of the application.
if helm -n "$NS" status visionhive >/dev/null 2>&1; then
  echo "A Helm release 'visionhive' already exists. Remove it first: ./scripts/helm-down.sh"; exit 1
fi
if kubectl -n "$NS" get deployment api-gateway >/dev/null 2>&1 && \
   ! kubectl -n argocd get application visionhive-local >/dev/null 2>&1; then
  echo "The application is already deployed by hand (Phase 7 or 8). Remove it first: ./scripts/k8s-down.sh"; exit 1
fi

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null
echo "== installing Argo CD (chart $ARGOCD_CHART_VERSION)"
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" -f gitops/argocd/values.yaml --wait --timeout 8m

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "== project and app of apps"
kubectl apply -f gitops/bootstrap/project.yaml
kubectl apply -f gitops/bootstrap/root-app.yaml

echo
echo "Next:"
echo "  ./scripts/local-secrets.sh          (the Secrets the app needs)"
echo "  ./scripts/local-build-images.sh     (images inside Minikube, then commit the tag)"
echo "  kubectl -n argocd get applications -w"
echo "  ./scripts/gitops-ui.sh"
