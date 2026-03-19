#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# broken-deploy.sh - Demonstration d'un deploiement echoue et rollback
#
# Ce script:
#   1. Met a jour le deploiement avec une image inexistante
#   2. Observe l'echec du rollout
#   3. Execute un rollback automatique
###############################################################################

NAMESPACE="sample-app"
DEPLOYMENT="sample-app"
BROKEN_IMAGE="sample-app:broken-v999"

echo "============================================"
echo "  Demo: Deploiement casse + Rollback"
echo "  Namespace  : ${NAMESPACE}"
echo "  Deployment : ${DEPLOYMENT}"
echo "============================================"
echo ""

# Etat actuel
echo "[INFO] Etat actuel du deploiement:"
kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o wide
echo ""

# Sauvegarder l'image actuelle
CURRENT_IMAGE=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "[INFO] Image actuelle: ${CURRENT_IMAGE}"
echo ""

# Deployer une image cassee
echo "[WARN] Mise a jour avec une image inexistante: ${BROKEN_IMAGE}"
kubectl set image deployment/"${DEPLOYMENT}" \
  "${DEPLOYMENT}=${BROKEN_IMAGE}" \
  -n "${NAMESPACE}"

echo "[INFO] Observation du rollout (timeout 60s)..."
echo ""

# Attendre le rollout (va echouer)
if kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=60s 2>&1; then
  echo "[WARN] Le rollout a reussi de maniere inattendue."
else
  echo ""
  echo "[INFO] Le rollout a echoue comme prevu."
fi

echo ""
echo "[INFO] Etat des pods apres le deploiement casse:"
kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=${DEPLOYMENT}"
echo ""

# Description des evenements pour voir l'erreur ImagePullBackOff
echo "[INFO] Evenements recents:"
kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -10
echo ""

# Rollback
echo "============================================"
echo "  Rollback en cours..."
echo "============================================"
kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"

echo "[INFO] Attente du rollback..."
kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=120s

echo ""
echo "[INFO] Etat apres rollback:"
kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o wide
echo ""

RESTORED_IMAGE=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "[INFO] Image restauree: ${RESTORED_IMAGE}"
echo ""
echo "[OK] Demo terminee. Le deploiement a ete restaure avec succes."
