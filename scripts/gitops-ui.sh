#!/usr/bin/env bash
# Opens the Argo CD UI at http://localhost:8081 (user: admin) and prints the initial password.
set -euo pipefail
pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "User: admin"
echo "Password: $pw"
echo "Open http://localhost:8081  (Ctrl+C stops the connection)"
kubectl -n argocd port-forward svc/argocd-server 8081:80
