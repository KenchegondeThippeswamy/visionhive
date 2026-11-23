#!/usr/bin/env bash
# Builds the three images INSIDE Minikube, tagged with the current commit, and writes that tag into
# gitops/local/values.yaml. You then commit and push that file: Argo CD does the rest.
# Usage: ./scripts/local-build-images.sh [tag]
set -euo pipefail
cd "$(dirname "$0")/.."
minikube status >/dev/null 2>&1 || { echo "Minikube is not running (./scripts/gitops-local-up.sh)"; exit 1; }
TAG="${1:-$(git rev-parse --short=7 HEAD)}"
if ! git diff --quiet HEAD -- services; then
  echo "WARNING: services/ has uncommitted changes, so the tag $TAG will not match exactly what you build."
fi
eval "$(minikube -p minikube docker-env)"
for s in api-gateway upload-svc ingest-worker; do
  echo "== building visionhive/$s:$TAG"
  docker build -q -t "visionhive/$s:$TAG" "services/$s"
done
sed -i -E "s/^(  tag: ).*/\1\"${TAG}\"/" gitops/local/values.yaml
grep -n '^  tag:' gitops/local/values.yaml
echo
echo "Now release it with Git:"
echo "  git add gitops/local/values.yaml && git commit -m \"deploy $TAG\" && git push origin dev"
