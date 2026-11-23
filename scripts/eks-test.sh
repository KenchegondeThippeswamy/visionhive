#!/usr/bin/env bash
# End-to-end test through the load balancer: real S3 upload, real SQS, real RDS.
# Usage: ./scripts/eks-test.sh [filename]
set -euo pipefail
cd "$(dirname "$0")/.."
NS=visionhive
host=$(kubectl -n "$NS" get ingress api-gateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
[ -n "$host" ] || { echo "No load balancer address. Run ./scripts/eks-deploy.sh"; exit 1; }
echo "waiting for http://$host/health (a new ALB needs a few minutes)"
ok=0
for _ in $(seq 1 40); do
  if [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$host/health")" = "200" ]; then ok=1; break; fi
  sleep 10
done
[ "$ok" -eq 1 ] || { echo "The load balancer never became healthy. Check the target group health in the console."; exit 1; }
API="http://$host" ./scripts/smoke-test.sh "${1:-sample.mp4}"
