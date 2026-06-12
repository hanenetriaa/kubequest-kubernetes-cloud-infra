#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# keynote-flow.sh - Orchestrates a live keynote demo for KubeQuest
#
# Flow:
#   1) Quick platform precheck
#   2) HPA demo (CPU stress)
#   3) Broken deployment + rollback demo
#   4) Zero-downtime rolling update demo
#   5) Manual DB backup trigger from CronJob
#
# Usage:
#   bash scripts/demo/keynote-flow.sh
#   bash scripts/demo/keynote-flow.sh --no-pause
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NO_PAUSE=false

for arg in "$@"; do
  case "${arg}" in
    --no-pause)
      NO_PAUSE=true
      ;;
    --help|-h)
      echo "Usage: $0 [--no-pause]"
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}"
      echo "Usage: $0 [--no-pause]"
      exit 1
      ;;
  esac
done

pause() {
  if [[ "${NO_PAUSE}" == false ]]; then
    read -r -p "Press Enter to continue..."
  fi
}

header() {
  echo ""
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
}

check_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: $1"
    exit 1
  fi
}

run_step() {
  local title="$1"
  shift
  header "${title}"
  echo "[INFO] Command: $*"
  "$@"
  echo ""
  echo "[OK] ${title}"
}

header "KubeQuest Keynote Demo Flow"
check_cmd kubectl
check_cmd bash

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] Cannot reach Kubernetes cluster. Check kubeconfig/context."
  exit 1
fi

APP_URL="${APP_URL:-http://localhost:30080}"
export APP_URL

echo "[INFO] APP_URL for HTTP checks: ${APP_URL}"
echo "[INFO] Demo scripts root: ${SCRIPT_DIR}"

header "Precheck: Cluster and Core Components"
kubectl get nodes -o wide
kubectl get pods -A | grep -E "ingress-nginx|monitoring|kubernetes-dashboard|gatekeeper|security|sample-app|metrics-server" || true
kubectl get hpa -n sample-app || true
pause

run_step "Demo 1/4 - HPA autoscaling under CPU load" \
  bash "${SCRIPT_DIR}/cpu-stress.sh" 2 90
pause

run_step "Demo 2/4 - Broken deployment and automatic rollback" \
  bash "${SCRIPT_DIR}/broken-deploy.sh"
pause

run_step "Demo 3/4 - Zero-downtime rolling update" \
  bash "${SCRIPT_DIR}/zero-downtime-test.sh"
pause

header "Demo 4/4 - Trigger an on-demand DB backup"
if kubectl get cronjob sample-app-mysql-backup -n sample-app >/dev/null 2>&1; then
  JOB_NAME="manual-backup-$(date +%H%M%S)"
  kubectl create job --from=cronjob/sample-app-mysql-backup "${JOB_NAME}" -n sample-app
  kubectl wait --for=condition=complete "job/${JOB_NAME}" -n sample-app --timeout=180s || true
  kubectl get jobs -n sample-app | grep "${JOB_NAME}" || true
  echo "[INFO] Backup job triggered: ${JOB_NAME}"
else
  echo "[WARN] CronJob sample-app-mysql-backup not found in namespace sample-app"
fi

header "Final Snapshot"
kubectl get pods -A --field-selector=status.phase!=Succeeded | grep -v Completed || true
kubectl get hpa -n sample-app || true
kubectl get cronjob -n sample-app || true

echo ""
echo "[OK] Keynote flow completed."
