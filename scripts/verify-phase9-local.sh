#!/usr/bin/env bash
set -euo pipefail

echo "========== MINIKUBE STATUS =========="
minikube status

echo
echo "========== KUBERNETES NODES =========="
kubectl get nodes

echo
echo "========== HELM RELEASE =========="
helm -n visionhive list

echo
echo "========== VISIONHIVE PODS =========="
kubectl get pods -n visionhive

echo
echo "========== MONITORING PODS =========="
kubectl get pods -n monitoring

echo
echo "========== SERVICES =========="
kubectl get svc -n visionhive
kubectl get svc -n monitoring

echo
echo "========== PROMETHEUS TARGETS =========="
if curl -fsS http://127.0.0.1:19090/api/v1/targets >/tmp/visionhive-targets.json; then
    python3 -c '
import json
with open("/tmp/visionhive-targets.json") as f:
    data = json.load(f)
for target in data["data"]["activeTargets"]:
    print(f"{target['job']:20} {target['health']:10} {target['scrapeUrl']}")
'
else
    echo "Prometheus port-forward is not available on port 19090."
    echo "Start it using the command documented in the project notes."
fi

echo
echo "========== PHASE 9 LOCAL VERIFICATION COMPLETE =========="
