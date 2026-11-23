#!/usr/bin/env bash
# Creates the Secrets the chart expects in the visionhive namespace. They are never stored in Git.
#   ./scripts/local-secrets.sh                     mode A: random database password, fake LocalStack keys
#   ./scripts/local-secrets.sh --aws [--profile P] mode B: the real database password from Secrets Manager,
#                                                  an ECR pull secret (valid 12 hours, run again to refresh),
#                                                  AWS keys from a CLI profile (use a least-privilege IAM user)
set -euo pipefail
NS=visionhive
REGION=ap-southeast-2
MODE=local
PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --aws) MODE=aws ;;
    --profile) PROFILE="${2:?give a profile name}"; shift ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
  shift
done

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
apply_secret() { kubectl -n "$NS" create secret "$@" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

if [ "$MODE" = "local" ]; then
  kubectl -n "$NS" get secret db-credentials >/dev/null 2>&1 || \
    apply_secret generic db-credentials --from-env-file=<(printf 'password=%s\n' "$(openssl rand -hex 16)")
  kubectl -n "$NS" get secret aws-local-credentials >/dev/null 2>&1 || \
    apply_secret generic aws-local-credentials --from-literal=AWS_ACCESS_KEY_ID=test --from-literal=AWS_SECRET_ACCESS_KEY=test
  echo "Created db-credentials and aws-local-credentials (self-contained mode)."
  exit 0
fi

AWS=(aws)
[ -n "$PROFILE" ] && AWS=(aws --profile "$PROFILE")

echo "== database password from Secrets Manager"
SECRET_ARN=$("${AWS[@]}" rds describe-db-instances --region "$REGION" --db-instance-identifier visionhive-dev-postgres \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text 2>/dev/null || true)
if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
  echo "The database visionhive-dev-postgres or its managed secret was not found. Is the Phase 5 database running?"; exit 1
fi
PW=$("${AWS[@]}" secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ARN" --query SecretString --output text \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')
apply_secret generic db-credentials --from-env-file=<(printf 'password=%s\n' "$PW")
echo "created db-credentials"

echo "== ECR pull secret (valid 12 hours)"
ACCOUNT=$("${AWS[@]}" sts get-caller-identity --query Account --output text)
TOKEN=$("${AWS[@]}" ecr get-login-password --region "$REGION")
# The token goes in through a file (not as an argument), so it is not visible in the process list.
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
DOCKERCFG=$(REGISTRY="$REGISTRY" TOKEN="$TOKEN" python3 -c 'import os,json,base64;r=os.environ["REGISTRY"];t=os.environ["TOKEN"];print(json.dumps({"auths":{r:{"username":"AWS","password":t,"auth":base64.b64encode(("AWS:"+t).encode()).decode()}}}))')
apply_secret generic ecr-pull --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=<(printf '%s' "$DOCKERCFG")
echo "created ecr-pull"

echo "== AWS keys for the pods (S3 and SQS)"
KEY=$("${AWS[@]}" configure get aws_access_key_id 2>/dev/null || true)
SEC=$("${AWS[@]}" configure get aws_secret_access_key 2>/dev/null || true)
if [ -z "$KEY" ] || [ -z "$SEC" ]; then
  echo "This profile has no static keys (it uses SSO or a role)."
  echo "Create a dedicated IAM user with only the Phase 5 upload-svc and ingest-worker policies and pass it: --profile NAME"
  exit 1
fi
echo "These keys will be stored in a Kubernetes Secret on your laptop cluster."
echo "Use a least-privilege IAM user, not an administrator."
read -r -p "Type yes to continue: " answer
[ "$answer" = "yes" ] || { echo "Skipped aws-credentials."; exit 0; }
apply_secret generic aws-credentials --from-env-file=<(printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "$KEY" "$SEC")
echo "created aws-credentials"
