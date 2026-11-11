#!/usr/bin/env bash
# Runs the same end-to-end test as "make test", against the app running in Minikube.
# Usage: ./scripts/k8s-test.sh [filename]      (use corrupt.mp4 to trigger the dead-letter queue)
set -euo pipefail
cd "$(dirname "$0")/.."
NS=visionhive

for p in 8081 4566; do
  if ss -ltn "( sport = :$p )" | grep -q LISTEN; then
    echo "Port $p is already in use. If the Docker Compose stack is running, stop it first: make down"
    exit 1
  fi
done

PIDS=()
cleanup() {
  for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
}
trap cleanup EXIT

kubectl -n "$NS" port-forward svc/api-gateway 8081:8080 >/tmp/pf-gateway.log 2>&1 &
PIDS+=($!)
kubectl -n "$NS" port-forward svc/localstack 4566:4566 >/tmp/pf-localstack.log 2>&1 &
PIDS+=($!)
sleep 4

API=http://localhost:8081 ./scripts/smoke-test.sh "${1:-sample.mp4}"
