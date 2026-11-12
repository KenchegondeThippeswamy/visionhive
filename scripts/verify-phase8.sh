#!/usr/bin/env bash
# Read-only check of Phase 8 (Helm). It changes nothing.
NS=visionhive
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
P=0; W=0; F=0
ok() { echo "  [PASS] $*"; P=$((P + 1)); }
warn() { echo "  [WARN] $*"; W=$((W + 1)); }
bad() { echo "  [FAIL] $*"; F=$((F + 1)); }
info() { echo "  [INFO] $*"; }
sec() { echo; echo "== $*"; }

sec "1. Files on GitHub dev"
git fetch -q origin 2>/dev/null
for f in helm/visionhive/Chart.yaml helm/visionhive/values.yaml helm/visionhive/values-minikube.yaml helm/visionhive/values-dev.yaml \
         helm/visionhive/values-qa.yaml helm/visionhive/values-prod.yaml helm/visionhive/templates/deployments.yaml \
         helm/visionhive/values.schema.json scripts/helm-check.sh scripts/helm-up.sh .github/workflows/helm-ci.yml docs/phase8-guide.md; do
  git cat-file -e "origin/dev:$f" 2>/dev/null || bad "not on GitHub dev: $f"
done
git cat-file -e "origin/dev:helm/visionhive/Chart.yaml" 2>/dev/null && ok "chart files are on GitHub dev"

sec "2. Chart checks (offline)"
if command -v helm >/dev/null 2>&1; then
  ok "helm is installed ($(helm version --short 2>/dev/null))"
  if ./scripts/helm-check.sh >/tmp/helm-check.log 2>&1; then ok "lint, render and schema checks pass for minikube, dev, qa, prod"; else bad "helm-check.sh failed (see /tmp/helm-check.log)"; tail -5 /tmp/helm-check.log | sed 's/^/        /'; fi
  if helm template v helm/visionhive -f helm/visionhive/values-dev.yaml >/dev/null 2>&1; then bad "an empty image.tag was accepted for dev (the 'required' guard is missing)"; else ok "dev refuses to render without image.tag (guard works)"; fi
else
  bad "helm is not installed"
fi

sec "3. Release on the cluster"
if command -v helm >/dev/null 2>&1 && helm -n "$NS" status visionhive >/dev/null 2>&1; then
  st=$(helm -n "$NS" status visionhive -o json 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["info"]["status"])' 2>/dev/null)
  [ "$st" = "deployed" ] && ok "release visionhive is deployed" || bad "release status: ${st:-unknown}"
  rev=$(helm -n "$NS" history visionhive -o json 2>/dev/null | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null)
  info "revisions: ${rev:-0} (the rollback lab creates more than one)"
  notready=$(kubectl -n "$NS" get pods --no-headers 2>/dev/null | awk '{split($2,a,"/"); if ($3!="Running" || a[1]!=a[2]) print $1}')
  [ -z "$notready" ] && ok "all pods Running and Ready" || bad "pods not ready: $notready"
else
  warn "no Helm release in namespace $NS (./scripts/helm-up.sh), skipping cluster checks"
fi

echo; echo "=============================================="
echo "  PASS: $P    WARN: $W    FAIL: $F"
if [ "$F" -gt 0 ]; then echo "  RESULT: NOT DONE. Fix the [FAIL] lines above."
elif [ "$W" -gt 0 ]; then echo "  RESULT: DONE, read the [WARN] lines."
else echo "  RESULT: ALL GOOD."; fi
echo "=============================================="
