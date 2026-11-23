#!/usr/bin/env bash
# Creates the EKS cluster (Terraform stack terraform/eks) and points kubectl at it.
# THE CLUSTER BILLS EVERY HOUR. Tear it down the same day with ./scripts/eks-teardown.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=ap-southeast-2
CLUSTER=visionhive-dev

for tool in aws terraform kubectl helm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing tool: $tool"; exit 1; }
done

echo "== checking the dev environment (it must exist first)"
aws sts get-caller-identity --query Account --output text >/dev/null
repos=$(aws ecr describe-repositories --region "$REGION" --query "length(repositories[?starts_with(repositoryName,'visionhive-dev/')])" --output text)
[ "$repos" -ge 3 ] || { echo "The three ECR repositories are missing. Apply the dev environment first (guide, part 2)."; exit 1; }
db=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$CLUSTER-postgres" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || true)
[ "$db" = "available" ] || echo "WARNING: database $CLUSTER-postgres is '${db:-missing}'. The app needs it (apply dev with enable_rds=true)."
imgs=$(aws ecr list-images --region "$REGION" --repository-name visionhive-dev/api-gateway --query 'length(imageIds)' --output text 2>/dev/null || echo 0)
[ "$imgs" -ge 1 ] || echo "WARNING: no images in ECR yet. Merge to dev so CI pushes them (Phase 6) before deploying."

cd terraform/eks
terraform init -input=false
terraform plan -input=false -out=eks.plan
echo
echo "Read the plan above. The cluster costs money until you run ./scripts/eks-teardown.sh"
read -r -p "Type yes to apply: " answer
[ "$answer" = "yes" ] || { echo "Not applied."; exit 0; }
terraform apply -input=false eks.plan

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"
kubectl get nodes
echo
echo "Next: ./scripts/eks-bootstrap.sh"
