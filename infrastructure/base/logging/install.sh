#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing Loki..."

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update grafana

helm upgrade --install loki grafana/loki \
  --namespace logging \
  --create-namespace \
  -f "${SCRIPT_DIR}/loki-values.yaml" \
  --wait \
  --timeout 5m

echo "==> Loki installed successfully."

echo "==> Installing Promtail..."

helm upgrade --install promtail grafana/promtail \
  --namespace logging \
  --create-namespace \
  -f "${SCRIPT_DIR}/promtail-values.yaml" \
  --wait \
  --timeout 5m

echo "==> Promtail installed successfully."
