#!/usr/bin/env bash
# Removes the Helm release and the namespace (database data included).
# Usage: ./scripts/helm-down.sh [--stop]     (--stop also stops Minikube)
set -uo pipefail
helm uninstall visionhive -n visionhive 2>/dev/null || true
kubectl delete namespace visionhive --ignore-not-found --wait=true
[ "${1:-}" = "--stop" ] && minikube stop
echo "done"
