#!/usr/bin/env bash
# Safe teardown of the EKS session. The ORDER matters:
#   1. things that create AWS resources from inside Kubernetes (load balancers)
#   2. nodes that Karpenter created (Phase 11)
#   3. the cluster stack
# Skipping step 1 leaves load balancers that keep billing and block the VPC from being deleted.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REGION=ap-southeast-2
CLUSTER=visionhive-dev

echo "== 1. remove what creates AWS resources from inside the cluster"
if kubectl cluster-info >/dev/null 2>&1; then
  helm -n visionhive uninstall visionhive 2>/dev/null || true
  kubectl -n visionhive delete ingress --all --ignore-not-found --wait=true --timeout=300s || true
  # any Service of type LoadBalancer in any namespace
  kubectl get svc -A -o json 2>/dev/null | python3 -c "
import sys, json
for s in json.load(sys.stdin)['items']:
    if s['spec'].get('type') == 'LoadBalancer':
        print(s['metadata']['namespace'], s['metadata']['name'])" | while read -r ns name; do
    echo "deleting LoadBalancer service $ns/$name"; kubectl -n "$ns" delete svc "$name" --wait=true --timeout=300s || true
  done
else
  echo "kubectl cannot reach the cluster, skipping"
fi

echo "== 2. wait until the load balancers and target groups of this cluster are gone"
for _ in $(seq 1 36); do
  n=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" \
      --resource-type-filters elasticloadbalancing --query 'length(ResourceTagMappingList)' --output text 2>/dev/null || echo 0)
  [ "$n" = "0" ] && break
  echo "  $n load balancer resources still exist, waiting 10 seconds"; sleep 10
done
[ "${n:-0}" = "0" ] || echo "WARNING: load balancer resources remain. Delete them in the console before the destroy, or it will hang."

echo "== 3. nodes created by Karpenter (they are not in Terraform)"
k=$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag-key,Values=karpenter.sh/nodepool" "Name=instance-state-name,Values=pending,running" \
    --query 'length(Reservations[].Instances[])' --output text 2>/dev/null || echo 0)
if [ "${k:-0}" != "0" ]; then
  echo "WARNING: $k Karpenter node(s) are running. Scale the workloads to zero and delete the NodePools first, then run this again."
  read -r -p "Continue anyway? (yes/no) " go
  [ "$go" = "yes" ] || exit 1
fi

echo "== 4. controllers"
helm -n kube-system uninstall aws-load-balancer-controller 2>/dev/null || true
helm -n external-secrets uninstall external-secrets 2>/dev/null || true

echo "== 5. destroy the cluster stack (Terraform asks you to confirm)"
( cd terraform/eks && terraform destroy -input=false )

echo "== 6. final check"
./scripts/verify-phase9.sh --down
