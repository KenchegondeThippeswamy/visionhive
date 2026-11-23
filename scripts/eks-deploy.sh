#!/usr/bin/env bash
# Deploys VisionHive to EKS with the Helm chart and prints the load balancer address.
# Usage: ./scripts/eks-deploy.sh [image-tag]     (default: the newest tag pushed to ECR)
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=ap-southeast-2
NS=visionhive
TAG="${1:-}"

if [ -z "$TAG" ]; then
  TAG=$(aws ecr describe-images --region "$REGION" --repository-name visionhive-dev/api-gateway \
    --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text 2>/dev/null || true)
fi
if [ -z "$TAG" ] || [ "$TAG" = "None" ]; then
  echo "No image found in ECR. Merge to dev so CI pushes images (Phase 6), or pass a tag."; exit 1
fi
for s in api-gateway upload-svc ingest-worker; do
  aws ecr describe-images --region "$REGION" --repository-name "visionhive-dev/$s" --image-ids imageTag="$TAG" >/dev/null 2>&1 \
    || { echo "Image tag $TAG is missing in visionhive-dev/$s"; exit 1; }
done

DB_HOST=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier visionhive-dev-postgres \
  --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || true)
if [ -z "$DB_HOST" ] || [ "$DB_HOST" = "None" ]; then echo "The database visionhive-dev-postgres was not found."; exit 1; fi

MYIP=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
echo "image tag: $TAG"
echo "the load balancer will accept traffic only from $MYIP/32 (your address)"

helm upgrade --install visionhive helm/visionhive -n "$NS" --create-namespace \
  -f helm/visionhive/values-dev.yaml \
  --set image.tag="$TAG" \
  --set database.host="$DB_HOST" \
  --set-string "ingress.annotations.alb\.ingress\.kubernetes\.io/inbound-cidrs=${MYIP}/32" \
  --wait --timeout 8m
kubectl -n "$NS" get pods

echo "== waiting for the load balancer address (2 to 4 minutes)"
host=""
for _ in $(seq 1 40); do
  host=$(kubectl -n "$NS" get ingress api-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$host" ] && break
  sleep 10
done
[ -n "$host" ] || { echo "No address yet. Check: kubectl -n $NS describe ingress api-gateway"; exit 1; }
echo "ALB address: http://$host"
echo
echo "Next: ./scripts/eks-test.sh"
