#!/usr/bin/env bash
# Removes VisionHive from Minikube.
# Usage: ./scripts/k8s-down.sh [--stop | --delete]
#   (no option)  delete the app and its data, keep the cluster running
#   --stop       also stop Minikube (frees memory, keeps the cluster)
#   --delete     also delete the whole Minikube cluster
set -uo pipefail
kubectl delete namespace visionhive --ignore-not-found --wait=true
case "${1:-}" in
  --stop) minikube stop ;;
  --delete) minikube delete ;;
esac
echo "done"
