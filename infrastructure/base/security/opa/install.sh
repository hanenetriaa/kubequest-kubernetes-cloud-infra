#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing OPA Gatekeeper..."

helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update gatekeeper

helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set replicas=1 \
  --set audit.replicas=1 \
  --set controllerManager.nodeSelector."node-type"=application \
  --set audit.nodeSelector."node-type"=application \
  --wait \
  --timeout 5m

echo "==> Gatekeeper installed. Waiting for webhook to be ready..."
kubectl wait --for=condition=Ready pod -l control-plane=controller-manager \
  -n gatekeeper-system --timeout=120s

echo "==> Applying constraint templates and constraints..."

# Apply constraint templates first, then constraints
for constraint_file in "${SCRIPT_DIR}"/constraints/*.yaml; do
  echo "    Applying $(basename "${constraint_file}")..."
  kubectl apply -f "${constraint_file}"
done

echo "==> OPA Gatekeeper constraints applied successfully."
