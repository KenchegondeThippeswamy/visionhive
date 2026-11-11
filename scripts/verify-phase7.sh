#!/usr/bin/env bash
# Read-only check of Phase 7 (Kubernetes on Minikube). It changes nothing unless you pass --test.
# Usage: ./scripts/verify-phase7.sh [--test]     (--test also runs the end-to-end test)
NS=visionhive
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
TEST=0
[ "${1:-}" = "--test" ] && TEST=1

P=0
W=0
F=0
ok() { echo "  [PASS] $*"; P=$((P + 1)); }
warn() { echo "  [WARN] $*"; W=$((W + 1)); }
bad() { echo "  [FAIL] $*"; F=$((F + 1)); }
info() { echo "  [INFO] $*"; }
sec() { echo; echo "== $*"; }

sec "1. Files in Git"
git fetch -q origin 2>/dev/null
for f in k8s/kustomization.yaml k8s/api-gateway.yaml k8s/postgres.yaml k8s/hpa.yaml k8s/ingress.yaml scripts/k8s-up.sh docs/phase7-guide.md; do
  if git cat-file -e "origin/dev:$f" 2>/dev/null; then :; else bad "not on GitHub dev: $f"; fi
done
git ls-tree -r --name-only origin/dev 2>/dev/null | grep -q "^k8s/kustomization.yaml$" && ok "Kubernetes manifests are on GitHub dev"
if git ls-tree -r --name-only origin/dev 2>/dev/null | grep -qiE "k8s/.*secret"; then bad "a secret file is in k8s/ (secrets must not be in Git)"; else ok "no secret manifests in Git"; fi

sec "2. Cluster"
for tool in kubectl minikube; do command -v "$tool" >/dev/null 2>&1 || bad "$tool is not installed"; done
if minikube status >/dev/null 2>&1; then ok "minikube is running"; else bad "minikube is not running (./scripts/k8s-up.sh)"; fi
if kubectl get namespace "$NS" >/dev/null 2>&1; then
  ok "namespace $NS exists"

  notready=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if ($3!="Running" || a[1]!=a[2]) print $1" ("$3" "$2")"}')
  total=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | wc -l)
  if [ "$total" -gt 0 ] && [ -z "$notready" ]; then ok "all $total pods are Running and Ready"; else bad "pods not ready: ${notready:-no pods found}"; fi

  for d in api-gateway upload-svc ingest-worker localstack; do
    ready=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    want=$(kubectl -n "$NS" get deployment "$d" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ -n "$ready" ] && [ "$ready" = "$want" ]; then ok "deployment $d: $ready/$want ready"; else warn "deployment $d: ${ready:-0}/${want:-?} ready"; fi
  done
  ready=$(kubectl -n "$NS" get statefulset postgres -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "$ready" = "1" ] && ok "statefulset postgres is ready" || bad "statefulset postgres is not ready"

  phase=$(kubectl -n "$NS" get pvc -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  [ "$phase" = "Bound" ] && ok "database volume (PVC) is Bound" || bad "PVC is not Bound (${phase:-missing})"

  for s in api-gateway upload-svc postgres localstack; do
    addr=$(kubectl -n "$NS" get endpoints "$s" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    [ -n "$addr" ] && ok "service $s has endpoints" || bad "service $s has NO endpoints (selector or readiness problem)"
  done

  kubectl -n "$NS" get ingress api-gateway >/dev/null 2>&1 && ok "ingress api-gateway exists" || bad "ingress missing"
  target=$(kubectl -n "$NS" get hpa api-gateway -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  if [ -n "$target" ]; then ok "autoscaler is reading CPU metrics (${target}%)"; else warn "autoscaler shows no CPU metric yet (wait a minute, or enable metrics-server)"; fi
  kubectl -n "$NS" get pdb api-gateway >/dev/null 2>&1 && ok "PodDisruptionBudget exists" || warn "PodDisruptionBudget missing"
else
  bad "namespace $NS not found (./scripts/k8s-up.sh)"
fi

if [ "$TEST" -eq 1 ]; then
  sec "3. End-to-end test"
  out=$(./scripts/k8s-test.sh 2>&1)
  echo "$out" | tail -12 | sed 's/^/    /'
  echo "$out" | grep -q '"status": "done"' && ok "video processed: status done" || bad "end-to-end test did not reach status done"
fi

echo
echo "=============================================="
echo "  PASS: $P    WARN: $W    FAIL: $F"
if [ "$F" -gt 0 ]; then echo "  RESULT: NOT DONE. Fix the [FAIL] lines above."
elif [ "$W" -gt 0 ]; then echo "  RESULT: DONE, read the [WARN] lines."
else echo "  RESULT: ALL GOOD."; fi
echo "=============================================="
