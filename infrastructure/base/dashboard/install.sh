#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing kubernetes-dashboard..."

helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update kubernetes-dashboard

helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard \
  --create-namespace \
  -f "${SCRIPT_DIR}/values.yaml" \
  --wait \
  --timeout 5m

echo "==> Applying admin-user resources..."
kubectl apply -f "${SCRIPT_DIR}/admin-user.yaml"

echo "==> kubernetes-dashboard installed successfully."
echo ""
echo "To get an admin token, run:"
echo "  kubectl -n kubernetes-dashboard create token admin-user"
