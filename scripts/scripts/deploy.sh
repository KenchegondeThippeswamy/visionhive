#!/usr/bin/env bash
# Deploy the VisionHive stack on a server and roll back automatically if it is unhealthy.
# Usage: ./deploy.sh [git-branch]     (run inside the repo folder)
set -euo pipefail

BRANCH=${1:-main}
HEALTH_URL=${HEALTH_URL:-http://localhost:8080/health}
COMPOSE="docker compose -f docker/docker-compose.yml"

PREV=$(git rev-parse HEAD)
echo "Current version: $PREV"

git fetch origin
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"
NEW=$(git rev-parse HEAD)
echo "Deploying version: $NEW"

$COMPOSE up -d --build

echo "Waiting for health check: $HEALTH_URL"
for i in $(seq 1 20); do
  if curl -fs -m 3 "$HEALTH_URL" >/dev/null; then
    echo "Deploy OK ($NEW)"
    exit 0
  fi
  sleep 3
done

echo "Health check FAILED. Rolling back to $PREV"
git checkout "$PREV"
$COMPOSE up -d --build
exit 1
