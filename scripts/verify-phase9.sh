#!/usr/bin/env bash
# Read-only check of Phase 9 (EKS). It changes nothing.
# Usage: ./scripts/verify-phase9.sh            cluster is up and the app works
#        ./scripts/verify-phase9.sh --test      also runs the end-to-end test
#        ./scripts/verify-phase9.sh --down      nothing paid is left after the teardown
REGION=ap-southeast-2
CLUSTER=visionhive-dev
NS=visionhive
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
MODE=up
[ "${1:-}" = "--down" ] && MODE=down
TEST=0
[ "${1:-}" = "--test" ] && TEST=1

P=0; W=0; F=0
ok() { echo "  [PASS] $*"; P=$((P + 1)); }
warn() { echo "  [WARN] $*"; W=$((W + 1)); }
bad() { echo "  [FAIL] $*"; F=$((F + 1)); }
info() { echo "  [INFO] $*"; }
sec() { echo; echo "== $*"; }

summary() {
  echo; echo "=============================================="
  echo "  PASS: $P    WARN: $W    FAIL: $F"
  if [ "$F" -gt 0 ]; then echo "  RESULT: NOT DONE. Fix the [FAIL] lines above."
  elif [ "$W" -gt 0 ]; then echo "  RESULT: DONE, read the [WARN] lines."
  else echo "  RESULT: ALL GOOD."; fi
  echo "=============================================="
  exit 0
}

acct=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
[ -n "$acct" ] || { bad "AWS CLI is not logged in"; summary; }

if [ "$MODE" = "down" ]; then
  sec "Is anything paid left after the teardown?"
  st=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --query cluster.status --output text 2>/dev/null)
  [ -z "$st" ] && ok "cluster $CLUSTER does not exist" || bad "cluster $CLUSTER still exists (status $st)"
  lbs=$(aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$CLUSTER" --resource-type-filters elasticloadbalancing --query 'length(ResourceTagMappingList)' --output text 2>/dev/null)
  [ "${lbs:-0}" = "0" ] && ok "no load balancers or target groups left" || bad "$lbs load balancer resources are left"
  inst=$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:eks:cluster-name,Values=$CLUSTER" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'length(Reservations[].Instances[])' --output text 2>/dev/null)
  [ "${inst:-0}" = "0" ] && ok "no cluster nodes left" || bad "$inst cluster node(s) are left"
  kn=$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag-key,Values=karpenter.sh/nodepool" "Name=instance-state-name,Values=pending,running" --query 'length(Reservations[].Instances[])' --output text 2>/dev/null)
  [ "${kn:-0}" = "0" ] && ok "no Karpenter nodes left" || bad "$kn Karpenter node(s) are left"
  vols=$(aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'length(Volumes)' --output text 2>/dev/null)
  [ "${vols:-0}" = "0" ] && ok "no unattached disks" || warn "$vols unattached disk(s) (maybe left by the EBS driver), still billed"
  nat=$(aws ec2 describe-nat-gateways --region "$REGION" --filter Name=state,Values=available,pending --query 'length(NatGateways)' --output text 2>/dev/null)
  [ "${nat:-0}" = "0" ] && ok "no NAT gateways" || warn "$nat NAT gateway(s) exist (expensive, turn off enable_nat_gateway)"
  info "also run ./scripts/verify-phase5.sh --all-regions for a full account check"
  summary
fi

sec "1. Cluster"
st=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --query cluster.status --output text 2>/dev/null)
if [ "$st" = "ACTIVE" ]; then
  ok "cluster $CLUSTER is ACTIVE"
  ver=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --query cluster.version --output text)
  sup=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" --query cluster.upgradePolicy.supportType --output text 2>/dev/null)
  info "Kubernetes $ver, support type ${sup:-unknown}"
  [ "$sup" = "STANDARD" ] && ok "cluster is set to standard support (avoids extended-support charges)" || warn "support type is ${sup:-unknown}"
  ng=$(aws eks describe-nodegroup --region "$REGION" --cluster-name "$CLUSTER" --nodegroup-name system --query nodegroup.status --output text 2>/dev/null)
  [ "$ng" = "ACTIVE" ] && ok "node group system is ACTIVE" || bad "node group status: ${ng:-missing}"
  for a in $(aws eks list-addons --region "$REGION" --cluster-name "$CLUSTER" --query 'addons[]' --output text 2>/dev/null); do
    s=$(aws eks describe-addon --region "$REGION" --cluster-name "$CLUSTER" --addon-name "$a" --query addon.status --output text 2>/dev/null)
    [ "$s" = "ACTIVE" ] && ok "add-on $a is ACTIVE" || bad "add-on $a is $s"
  done
else
  bad "cluster $CLUSTER not found or not active (./scripts/eks-up.sh)"; summary
fi

sec "2. Kubernetes"
if kubectl get nodes >/dev/null 2>&1; then
  notready=$(kubectl get nodes --no-headers | awk '$2!="Ready"{print $1}')
  [ -z "$notready" ] && ok "all nodes are Ready ($(kubectl get nodes --no-headers | wc -l))" || bad "nodes not ready: $notready"
  for d in "kube-system aws-load-balancer-controller" "external-secrets external-secrets"; do
    set -- $d
    r=$(kubectl -n "$1" get deployment "$2" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    [ -n "$r" ] && [ "$r" != "0" ] && ok "$2 is running" || bad "$2 is not running (./scripts/eks-bootstrap.sh)"
  done
  kubectl -n "$NS" get secret db-credentials >/dev/null 2>&1 && ok "secret db-credentials exists (made by External Secrets)" || bad "secret db-credentials is missing"
  notready=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if ($3!="Running" && $3!="Completed" || (a[1]!=a[2] && $3!="Completed")) print $1}')
  total=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | wc -l)
  [ "$total" -gt 0 ] && [ -z "$notready" ] && ok "all $total application pods are ready" || bad "application pods not ready: ${notready:-none found}"
  host=$(kubectl -n "$NS" get ingress api-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$host" ] && ok "load balancer address: $host" || bad "ingress has no load balancer address"
else
  bad "kubectl cannot reach the cluster (aws eks update-kubeconfig --region $REGION --name $CLUSTER)"
fi

sec "3. Identity (IRSA)"
arn=$(kubectl -n "$NS" exec deploy/upload-svc -- python -c "import boto3;print(boto3.client('sts',region_name='$REGION').get_caller_identity()['Arn'])" 2>/dev/null)
case "$arn" in *"visionhive-dev-irsa-upload-svc"*) ok "upload-svc runs as its own role: $arn" ;; *) bad "upload-svc identity is '${arn:-unknown}', expected the visionhive-dev-irsa-upload-svc role" ;; esac
ann=$(kubectl -n "$NS" get sa api-gateway -o jsonpath='{.metadata.annotations}' 2>/dev/null)
[ -z "$ann" ] && ok "api-gateway has no IAM role (it needs no AWS access)" || warn "api-gateway has annotations: $ann"

sec "4. Security group path to the database"
rds=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=$CLUSTER-rds" --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`].UserIdGroupPairs[].GroupId' --output text 2>/dev/null)
n=$(echo "$rds" | wc -w)
[ "$n" -ge 2 ] && ok "database accepts the app group and the EKS cluster group" || warn "database security group trusts $n group(s), expected 2"

if [ "$TEST" -eq 1 ]; then
  sec "5. End-to-end test"
  out=$(./scripts/eks-test.sh 2>&1)
  echo "$out" | tail -12 | sed 's/^/    /'
  echo "$out" | grep -q '"status": "done"' && ok "video processed on EKS: status done" || bad "end-to-end test did not reach status done"
fi
warn "the cluster is running and billing. Run ./scripts/eks-teardown.sh when you finish"
summary
