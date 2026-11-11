#!/usr/bin/env bash
# Read-only check of Phase 6 (GitHub Actions -> ECR with OIDC). It changes nothing.
# Usage: ./scripts/verify-phase6.sh
REGION=${REGION:-ap-southeast-2}
ROLE=${ROLE:-visionhive-github-actions-ecr}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1

P=0
W=0
F=0
ok() { echo "  [PASS] $*"; P=$((P + 1)); }
warn() { echo "  [WARN] $*"; W=$((W + 1)); }
bad() { echo "  [FAIL] $*"; F=$((F + 1)); }
info() { echo "  [INFO] $*"; }
sec() { echo; echo "== $*"; }

sec "1. AWS side"
acct=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$acct" ]; then
  bad "AWS CLI is not logged in"
else
  ok "AWS login works (account $acct)"
  if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text 2>/dev/null | grep -q "token.actions.githubusercontent.com"; then
    ok "GitHub OIDC provider exists"
  else
    bad "GitHub OIDC provider missing (cd terraform/github-oidc && terraform apply)"
  fi
  if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
    ok "role $ROLE exists"
    subs=$(aws iam get-role --role-name "$ROLE" --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals."token.actions.githubusercontent.com:sub"' --output text 2>/dev/null)
    info "role can be assumed only by: $subs"
    echo "$subs" | grep -q "pull_request" && bad "the role trusts pull requests, it should trust branches only"
    echo "$subs" | grep -q '\*' && bad "the role trust contains a wildcard"
  else
    bad "role $ROLE not found"
  fi
  for s in api-gateway upload-svc ingest-worker; do
    tags=$(aws ecr list-images --region "$REGION" --repository-name "visionhive-dev/$s" --query 'imageIds[].imageTag' --output text 2>/dev/null)
    if [ -n "$tags" ]; then ok "ECR visionhive-dev/$s has images: $tags"; else warn "ECR visionhive-dev/$s has no images (dev environment up? CI run on dev finished?)"; fi
  done
fi

sec "2. GitHub side"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if gh variable list 2>/dev/null | grep -q "^AWS_ROLE_ARN"; then ok "repository variable AWS_ROLE_ARN is set"; else bad "AWS_ROLE_ARN variable not set (gh variable set AWS_ROLE_ARN --body <role arn>)"; fi
  if gh secret list 2>/dev/null | grep -qiE "AWS_(ACCESS|SECRET)"; then bad "AWS keys are stored as GitHub secrets. Delete them: OIDC needs none"; else ok "no AWS keys stored in GitHub secrets"; fi
  last=$(gh run list --branch dev --workflow ci --limit 1 --json conclusion,headSha --jq '.[0] | "\(.conclusion) \(.headSha[0:7])"' 2>/dev/null)
  info "latest ci run on dev: ${last:-unknown}"
  case "$last" in success*) ok "latest ci run on dev succeeded" ;; *) warn "latest ci run on dev did not succeed" ;; esac
else
  info "gh is not logged in, skipping GitHub checks"
fi

sec "3. Workflow file on GitHub dev"
git fetch -q origin 2>/dev/null
if git cat-file -e origin/dev:.github/workflows/ci.yml 2>/dev/null; then
  wf=$(git show origin/dev:.github/workflows/ci.yml)
  echo "$wf" | grep -q "configure-aws-credentials" && ok "workflow uses OIDC (configure-aws-credentials)" || bad "workflow has no OIDC step"
  echo "$wf" | grep -q "id-token: write" && ok "workflow requests id-token: write" || bad "id-token: write missing"
  echo "$wf" | grep -qiE "aws-access-key-id|aws_secret_access_key" && bad "workflow references static AWS keys" || ok "workflow has no static AWS keys"
else
  bad "ci.yml not found on origin/dev"
fi

echo
echo "=============================================="
echo "  PASS: $P    WARN: $W    FAIL: $F"
if [ "$F" -gt 0 ]; then echo "  RESULT: NOT DONE. Fix the [FAIL] lines above."
elif [ "$W" -gt 0 ]; then echo "  RESULT: DONE, read the [WARN] lines."
else echo "  RESULT: ALL GOOD."; fi
echo "=============================================="
