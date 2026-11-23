#!/usr/bin/env bash
# Read-only check of Phase 10 (Argo CD and GitOps on Minikube). It changes nothing.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
P=0; W=0; F=0
ok() { echo "  [PASS] $*"; P=$((P + 1)); }
warn() { echo "  [WARN] $*"; W=$((W + 1)); }
bad() { echo "  [FAIL] $*"; F=$((F + 1)); }
info() { echo "  [INFO] $*"; }
sec() { echo; echo "== $*"; }

sec "1. Git (what Argo CD reads)"
git fetch -q origin 2>/dev/null
for f in gitops/apps/visionhive-local.yaml gitops/local/values.yaml gitops/bootstrap/root-app.yaml gitops/bootstrap/project.yaml \
         gitops/argocd/values.yaml helm/visionhive/Chart.yaml; do
  git cat-file -e "origin/dev:$f" 2>/dev/null || bad "not on GitHub dev: $f"
done
git cat-file -e "origin/dev:gitops/apps/visionhive-local.yaml" 2>/dev/null && ok "gitops files are on GitHub dev"
git show origin/dev:helm/visionhive/templates/deployments.yaml 2>/dev/null | grep -q imagePullSecrets && ok "chart supports imagePullSecrets (ECR)" || bad "chart on dev has no imagePullSecrets patch"
tag=$(git show origin/dev:gitops/local/values.yaml 2>/dev/null | sed -n 's/^  tag: "\(.*\)"/\1/p')
[ -n "$tag" ] && ok "image tag in Git: $tag" || bad "no image tag in gitops/local/values.yaml"
git ls-tree -r --name-only origin/dev 2>/dev/null | grep -qiE "secret.*\.ya?ml$" && bad "a secret manifest is in Git"

sec "2. Argo CD on Minikube"
if ! command -v kubectl >/dev/null 2>&1; then bad "kubectl is not installed"
elif ! minikube status >/dev/null 2>&1; then bad "Minikube is not running (./scripts/gitops-local-up.sh)"
elif ! kubectl -n argocd get deploy argocd-server >/dev/null 2>&1; then bad "Argo CD is not installed (./scripts/gitops-local-up.sh)"
else
  notready=$(kubectl -n argocd get pods --no-headers | awk '{split($2,a,"/"); if ($3!="Running" || a[1]!=a[2]) print $1}')
  [ -z "$notready" ] && ok "all Argo CD pods are ready" || bad "Argo CD pods not ready: $notready"
  for app in visionhive-root visionhive-local; do
    sync=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null)
    health=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null)
    if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then ok "application $app: Synced and Healthy"; else bad "application $app: sync=${sync:-missing} health=${health:-missing}"; fi
  done
  heal=$(kubectl -n argocd get application visionhive-local -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null)
  [ "$heal" = "true" ] && ok "self-heal is on" || warn "self-heal is not on"
  running=$(kubectl -n visionhive get deploy api-gateway -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  info "running image: ${running:-none}"
  if [ -n "$tag" ] && echo "$running" | grep -q ":$tag$"; then ok "the cluster runs the tag that Git says ($tag)"; else warn "cluster image does not match the tag in Git (still syncing?)"; fi
  helm -n visionhive status visionhive >/dev/null 2>&1 && warn "a Helm release 'visionhive' exists next to Argo CD (remove it: ./scripts/helm-down.sh)"
  kubectl -n visionhive get secret db-credentials >/dev/null 2>&1 && ok "secret db-credentials exists" || bad "secret db-credentials is missing (./scripts/local-secrets.sh)"
  kubectl -n visionhive get secret ecr-pull >/dev/null 2>&1 && info "mode B secrets present (ecr-pull)" || info "mode A (no ecr-pull secret)"
fi
info "Minikube uses laptop memory. Stop it when you finish: ./scripts/gitops-down.sh --stop"

echo; echo "=============================================="
echo "  PASS: $P    WARN: $W    FAIL: $F"
if [ "$F" -gt 0 ]; then echo "  RESULT: NOT DONE. Fix the [FAIL] lines above."
elif [ "$W" -gt 0 ]; then echo "  RESULT: DONE, read the [WARN] lines."
else echo "  RESULT: ALL GOOD."; fi
echo "=============================================="
