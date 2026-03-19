#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/base"

echo "============================================"
echo "  KubeQuest Infrastructure Deployment"
echo "============================================"
echo ""

# -----------------------------------------------
# Step 1: Create Namespaces
# -----------------------------------------------
echo ">>> Step 1/6: Creating Namespaces..."
kubectl apply -f "${BASE_DIR}/namespaces/namespaces.yaml"
echo ""

# -----------------------------------------------
# Step 2: Install Ingress-Nginx
# -----------------------------------------------
echo ">>> Step 2/6: Installing Ingress-Nginx..."
bash "${BASE_DIR}/ingress-nginx/install.sh"
echo ""

# -----------------------------------------------
# Step 3: Install Monitoring (kube-prometheus-stack)
# -----------------------------------------------
echo ">>> Step 3/6: Installing Monitoring Stack..."
bash "${BASE_DIR}/monitoring/install.sh"
echo ""

# -----------------------------------------------
# Step 4: Install Logging (Loki + Promtail)
# -----------------------------------------------
echo ">>> Step 4/6: Installing Logging Stack..."
bash "${BASE_DIR}/logging/install.sh"
echo ""

# -----------------------------------------------
# Step 5: Install Kubernetes Dashboard
# -----------------------------------------------
echo ">>> Step 5/6: Installing Kubernetes Dashboard..."
bash "${BASE_DIR}/dashboard/install.sh"
echo ""

# -----------------------------------------------
# Step 6: Install Security Components
# -----------------------------------------------
echo ">>> Step 6/6: Installing Security Components..."

echo "  --> OPA Gatekeeper..."
bash "${BASE_DIR}/security/opa/install.sh"
echo ""

echo "  --> Dex + OAuth2 Proxy..."
bash "${BASE_DIR}/security/dex/install.sh"
echo ""

echo "============================================"
echo "  KubeQuest Infrastructure Deployed!"
echo "============================================"
echo ""
echo "Endpoints:"
echo "  - Grafana:    https://grafana.kubequest.local"
echo "  - Dashboard:  https://dashboard.kubequest.local"
echo "  - Dex:        https://dex.kubequest.local"
echo "  - OAuth2:     https://oauth2.kubequest.local"
echo ""
echo "To get a dashboard admin token:"
echo "  kubectl -n kubernetes-dashboard create token admin-user"
echo ""
