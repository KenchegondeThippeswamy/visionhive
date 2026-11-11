#!/usr/bin/env bash
# Read-only check of everything from Phase 5. It changes nothing in Git or AWS.
# Usage: ./scripts/verify-phase5.sh [--plan] [--all-regions]
#   --plan         also run "terraform plan" for dev and show its summary line
#   --all-regions  look for paid resources in every AWS region, not only ap-southeast-2
REGION=${REGION:-ap-southeast-2}
STATE_BUCKET=${STATE_BUCKET:-visionhive-tfstate-282380327737}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

PLAN=0
ALL=0
for a in "$@"; do
  case "$a" in
    --plan) PLAN=1 ;;
    --all-regions) ALL=1 ;;
  esac
done

P=0
W=0
F=0
ok() { echo "  [PASS] $*"; P=$((P + 1)); }
warn() { echo "  [WARN] $*"; W=$((W + 1)); }
bad() { echo "  [FAIL] $*"; F=$((F + 1)); }
info() { echo "  [INFO] $*"; }
sec() { echo; echo "== $*"; }

# ---------------------------------------------------------------- 1. Git and GitHub
sec "1. Git and GitHub"
info "current branch: $(git branch --show-current)"
git fetch -q origin 2>/dev/null || warn "could not reach GitHub (git fetch failed), results below may be old"

if [ -z "$(git status --porcelain)" ]; then ok "working tree is clean"; else warn "uncommitted changes (see: git status --short)"; fi

if git rev-parse origin/dev >/dev/null 2>&1; then
  missing=0
  for f in terraform/phase5.tf terraform/phase5_variables.tf terraform/phase5_outputs.tf \
    terraform/modules/rds/main.tf terraform/modules/efs/main.tf terraform/modules/security/main.tf \
    terraform/modules/iam-policies/main.tf terraform/modules/bastion/main.tf \
    scripts/phase5-add-tfvars.sh docs/phase5-guide.md; do
    if ! git cat-file -e "origin/dev:$f" 2>/dev/null; then
      bad "missing on GitHub dev branch: $f"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] && ok "all Phase 5 files are on the GitHub dev branch"

  if git grep -q "count *= *var.db_secret_arn" "origin/dev" -- terraform 2>/dev/null; then
    bad "dev still has the old count bug (apply phase5-fix files)"
  else
    ok "count bug fix is on dev"
  fi

  if git grep -qE "trivy-action@[0-9]" "origin/dev" -- .github 2>/dev/null; then
    bad "workflows use a removed trivy-action tag (use v0.35.0)"
  else
    ok "workflows do not use the removed trivy-action tags"
  fi

  bad_files=$(git ls-tree -r --name-only origin/dev | grep -E '\.tfstate|(^|/)\.terraform/|\.plan$|\.pem$|(^|/)\.env$')
  if [ -n "$bad_files" ]; then bad "files that must not be in Git: $bad_files"; else ok "no state, plugin, plan, key or .env files in Git"; fi

  if [ "$(git branch --show-current)" = "dev" ]; then
    if [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/dev)" ]; then ok "local dev matches GitHub dev"; else warn "local dev differs from GitHub dev (git pull or git push)"; fi
  fi
else
  bad "origin/dev not found"
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh pr list --state merged --base dev --json title --jq '.[].title' 2>/dev/null | grep -qi "data plane"; then
    ok "the data plane pull request is merged into dev"
  else
    warn "no merged pull request titled 'data plane' found"
  fi
  open_prs=$(gh pr list --state open --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null)
  if [ -n "$open_prs" ]; then warn "open pull requests: $open_prs"; else ok "no open pull requests"; fi
  last=$(gh run list --branch dev --limit 3 --json conclusion,name --jq '.[] | "\(.name): \(.conclusion)"' 2>/dev/null)
  if [ -n "$last" ]; then
    info "latest runs on dev:"
    echo "$last" | sed 's/^/           /'
    echo "$last" | grep -qE "failure|cancelled" && warn "a recent run on dev did not succeed"
  fi
else
  info "gh not logged in, skipping pull request and workflow checks (gh auth login)"
fi

# ---------------------------------------------------------------- 2. Terraform code
sec "2. Terraform code"
if command -v terraform >/dev/null 2>&1; then
  if (cd terraform && terraform fmt -check -recursive >/dev/null 2>&1); then ok "terraform fmt is clean"; else bad "format problems (run: cd terraform && terraform fmt -recursive)"; fi
  if (cd terraform && terraform validate >/dev/null 2>&1); then
    ok "terraform validate passes"
  else
    bad "validate failed (run: cd terraform && terraform init -reconfigure -backend-config=env/dev.backend.hcl && terraform validate)"
  fi
  key=$(grep -o '"key": *"[^"]*"' terraform/.terraform/terraform.tfstate 2>/dev/null | head -1 | sed 's/.*: *//; s/"//g')
  info "backend currently set to state file: ${key:-not initialised}"
  for e in dev qa prod; do
    grep -q "^enable_rds" "terraform/env/$e.tfvars" 2>/dev/null && ok "$e.tfvars has the Phase 5 settings" || bad "$e.tfvars is missing the Phase 5 settings (run scripts/phase5-add-tfvars.sh)"
  done
  if [ "$PLAN" -eq 1 ]; then
    if [ "$key" = "visionhive/dev/terraform.tfstate" ]; then
      info "running terraform plan for dev (read-only)..."
      line=$(cd terraform && terraform plan -var-file=env/dev.tfvars -input=-1 -no-color 2>&1 | grep -E "^(Plan:|No changes)" | head -1)
      info "plan result: ${line:-could not read the plan}"
      info "differences are expected if you removed RDS or the bastion with -var enable_rds=false"
    else
      warn "plan skipped: backend is not set to dev (run: cd terraform && terraform init -reconfigure -backend-config=env/dev.backend.hcl)"
    fi
  fi
else
  warn "terraform is not installed on this machine"
fi

# ---------------------------------------------------------------- 3. AWS
sec "3. AWS account and costs"
acct=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$acct" ]; then
  bad "AWS CLI is not logged in (check: aws sts get-caller-identity, and unset AWS_PROFILE if it points to a missing profile)"
else
  ok "AWS login works (account $acct)"
  if aws s3 ls "s3://$STATE_BUCKET" >/dev/null 2>&1; then ok "Terraform state bucket exists ($STATE_BUCKET)"; else bad "state bucket not reachable ($STATE_BUCKET)"; fi

  if [ "$ALL" -eq 1 ]; then
    regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null)
    info "checking all regions (this takes about a minute)"
  else
    regions=$REGION
    info "checking region $REGION (add --all-regions to check every region)"
  fi

  W_BEFORE=$W
  for r in $regions; do
    rds=$(aws rds describe-db-instances --region "$r" --query 'DBInstances[].DBInstanceIdentifier' --output text 2>/dev/null)
    [ -n "$rds" ] && warn "[$r] RDS database running, billed per hour: $rds"

    ec2=$(aws ec2 describe-instances --region "$r" --filters Name=instance-state-name,Values=running,pending \
      --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`Name`]|[0].Value]' --output text 2>/dev/null | tr '\t' ' ')
    if [ -n "$ec2" ]; then
      while read -r line; do warn "[$r] EC2 instance running: $line"; done <<< "$ec2"
    fi

    nat=$(aws ec2 describe-nat-gateways --region "$r" --filter Name=state,Values=available,pending \
      --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
    [ -n "$nat" ] && warn "[$r] NAT gateway running, expensive: $nat"

    lb=$(aws elbv2 describe-load-balancers --region "$r" --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null)
    [ -n "$lb" ] && warn "[$r] load balancer running: $lb"

    vol=$(aws ec2 describe-volumes --region "$r" --filters Name=status,Values=available \
      --query 'Volumes[].[VolumeId,Size]' --output text 2>/dev/null | tr '\t' ' ')
    if [ -n "$vol" ]; then
      while read -r line; do warn "[$r] unattached EBS volume (still billed): $line"; done <<< "$vol"
    fi

    eip=$(aws ec2 describe-addresses --region "$r" --query 'Addresses[?AssociationId==`null`].PublicIp' --output text 2>/dev/null)
    [ -n "$eip" ] && warn "[$r] unused Elastic IP: $eip"

    snap=$(aws rds describe-db-snapshots --region "$r" --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text 2>/dev/null)
    [ -n "$snap" ] && warn "[$r] manual database snapshot (billed): $snap"

    efs=$(aws efs describe-file-systems --region "$r" --query 'FileSystems[].FileSystemId' --output text 2>/dev/null)
    [ -n "$efs" ] && info "[$r] EFS file system exists (pennies per GB): $efs"
  done
  [ "$W" -eq "$W_BEFORE" ] && ok "no running paid resources found"
fi

# ---------------------------------------------------------------- summary
echo
echo "=============================================="
echo "  PASS: $P    WARN: $W    FAIL: $F"
if [ "$F" -gt 0 ]; then
  echo "  RESULT: NOT DONE. Fix the [FAIL] lines above."
elif [ "$W" -gt 0 ]; then
  echo "  RESULT: DONE. Read the [WARN] lines: they may be costing money."
else
  echo "  RESULT: ALL GOOD."
fi
echo "=============================================="
