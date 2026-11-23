#!/usr/bin/env bash
# Installs the controllers the application needs, creates the database secret and the tables.
# Safe to run again.
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=ap-southeast-2
CLUSTER=visionhive-dev
NS=visionhive
LBC_CHART_VERSION=3.6.2   # AWS Load Balancer Controller (matches terraform/eks/policies/alb_iam_policy.json)
ESO_CHART_VERSION=2.15.0  # External Secrets Operator

ctx=$(kubectl config current-context)
case "$ctx" in
  *"$CLUSTER"*) ;;
  *) echo "kubectl points at '$ctx', not at $CLUSTER. Run: aws eks update-kubeconfig --region $REGION --name $CLUSTER"; exit 1 ;;
esac

VPC_ID=$(terraform -chdir=terraform/eks output -raw vpc_id)

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update >/dev/null

echo "== 1. AWS Load Balancer Controller $LBC_CHART_VERSION (turns an Ingress into an ALB)"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version "$LBC_CHART_VERSION" \
  -f helm-values/aws-load-balancer-controller.yaml \
  --set clusterName="$CLUSTER" --set region="$REGION" --set vpcId="$VPC_ID" \
  --wait --timeout 5m

echo "== 2. External Secrets Operator $ESO_CHART_VERSION (copies Secrets Manager secrets into Kubernetes)"
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --version "$ESO_CHART_VERSION" \
  -f helm-values/external-secrets.yaml \
  --wait --timeout 5m
if ! kubectl get crd clustersecretstores.external-secrets.io >/dev/null 2>&1; then
  echo "The chart did not install the CRDs, applying the official bundle for v$ESO_CHART_VERSION"
  kubectl apply --server-side -f "https://raw.githubusercontent.com/external-secrets/external-secrets/v${ESO_CHART_VERSION}/deploy/crds/bundle.yaml"
fi
kubectl wait --for=condition=established --timeout=120s \
  crd/clustersecretstores.external-secrets.io crd/externalsecrets.external-secrets.io

echo "== 3. secret store and the database password"
kubectl apply -f k8s-eks/clustersecretstore.yaml
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
SECRET_ARN=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$CLUSTER-postgres" \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text 2>/dev/null || true)
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
  echo "The database or its managed secret was not found. Apply the dev environment with enable_rds=true first."; exit 1
fi
sed "s|REPLACE_RDS_SECRET_ARN|$SECRET_ARN|" k8s-eks/externalsecret-db.yaml | kubectl apply -f -
kubectl -n "$NS" wait --for=condition=Ready externalsecret/db-credentials --timeout=180s
kubectl -n "$NS" get secret db-credentials >/dev/null && echo "Secret db-credentials was created from Secrets Manager"

echo "== 4. database tables"
DB_HOST=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$CLUSTER-postgres" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
kubectl -n "$NS" create configmap db-init-sql --from-file=init.sql=helm/visionhive/files/postgres-init.sql \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" delete job db-init --ignore-not-found >/dev/null
sed "s|REPLACE_DB_HOST|$DB_HOST|" k8s-eks/db-init-job.yaml | kubectl apply -f -
kubectl -n "$NS" wait --for=condition=complete --timeout=180s job/db-init
kubectl -n "$NS" logs job/db-init
echo
echo "Next: ./scripts/eks-deploy.sh"
