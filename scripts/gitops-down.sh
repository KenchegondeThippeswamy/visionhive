#!/usr/bin/env bash
# Removes the application and Argo CD from Minikube (database data included).
# Usage: ./scripts/gitops-down.sh [--stop]     (--stop also stops Minikube)
set -uo pipefail
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  # delete the applications first, otherwise Argo CD recreates what you remove
  kubectl -n argocd delete applications.argoproj.io --all --wait=true --timeout=300s || true
fi
helm -n argocd uninstall argocd 2>/dev/null || true
kubectl delete namespace argocd --ignore-not-found --wait=true
kubectl delete namespace visionhive --ignore-not-found --wait=true
[ "${1:-}" = "--stop" ] && minikube stop
echo "done"
