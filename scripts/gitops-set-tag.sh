#!/usr/bin/env bash
# Writes an image tag into gitops/local/values.yaml by hand.
# Usage: ./scripts/gitops-set-tag.sh abc1234        a tag you choose
#        ./scripts/gitops-set-tag.sh --ecr          the newest tag pushed to ECR (mode B)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-}"
if [ "$TAG" = "--ecr" ]; then
  TAG=$(aws ecr describe-images --region ap-southeast-2 --repository-name visionhive-dev/api-gateway \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text 2>/dev/null || true)
fi
if [ -z "$TAG" ] || [ "$TAG" = "None" ]; then echo "Give a tag, or --ecr to use the newest one in ECR."; exit 1; fi
sed -i -E "s/^(  tag: ).*/\1\"${TAG}\"/" gitops/local/values.yaml
grep -n '^  tag:' gitops/local/values.yaml
echo "Commit and push this file to dev, Argo CD will deploy it."
