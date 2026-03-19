#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Dex..."

helm repo add dex https://charts.dexidp.io
helm repo update dex

helm upgrade --install dex dex/dex \
  --namespace security \
  --create-namespace \
  -f "${SCRIPT_DIR}/values.yaml" \
  --wait \
  --timeout 5m

echo "==> Dex installed successfully."

echo "==> Installing OAuth2 Proxy..."

helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
helm repo update oauth2-proxy

helm upgrade --install oauth2-proxy oauth2-proxy/oauth2-proxy \
  --namespace security \
  --create-namespace \
  -f "${SCRIPT_DIR}/oauth2-proxy-values.yaml" \
  --wait \
  --timeout 5m

echo "==> OAuth2 Proxy installed successfully."
