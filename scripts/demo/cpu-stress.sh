#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# cpu-stress.sh - Genere du stress CPU pour declencher le HPA
#
# Cree un pod temporaire qui consomme du CPU avec des boucles
# 'yes > /dev/null' pour demontrer l'autoscaling horizontal.
###############################################################################

NAMESPACE="sample-app"
POD_NAME="cpu-stress-test"
NUM_CORES="${1:-4}"
DURATION="${2:-120}"

echo "============================================"
echo "  Demo: Stress CPU pour HPA"
echo "  Namespace : ${NAMESPACE}"
echo "  Coeurs    : ${NUM_CORES}"
echo "  Duree     : ${DURATION}s"
echo "============================================"
echo ""

# Nettoyage prealable
echo "[INFO] Nettoyage de tout pod de stress existant..."
kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found=true

# Etat HPA avant le test
echo "[INFO] Etat du HPA avant le test:"
kubectl get hpa -n "${NAMESPACE}" 2>/dev/null || echo "  Aucun HPA trouve."
echo ""

echo "[INFO] Nombre de replicas avant le test:"
kubectl get deployment -n "${NAMESPACE}" -o wide
echo ""

# Generer la commande de stress CPU
# Chaque boucle 'yes > /dev/null' consomme ~1 coeur CPU
STRESS_CMD=""
for ((i = 0; i < NUM_CORES; i++)); do
  STRESS_CMD+="yes > /dev/null & "
done
STRESS_CMD+="sleep ${DURATION}; kill \$(jobs -p) 2>/dev/null || true"

# Creer le pod de stress
echo "[INFO] Creation du pod de stress CPU..."
kubectl run "${POD_NAME}" \
  -n "${NAMESPACE}" \
  --image=busybox:1.36 \
  --restart=Never \
  --labels="purpose=cpu-stress-test" \
  --requests="cpu=100m,memory=64Mi" \
  --limits="cpu=${NUM_CORES},memory=128Mi" \
  --command -- /bin/sh -c "${STRESS_CMD}"

echo "[INFO] Pod cree. Stress CPU en cours pendant ${DURATION}s..."
echo "[INFO] Surveillez le HPA dans un autre terminal:"
echo "  kubectl get hpa -n ${NAMESPACE} -w"
echo ""

# Surveiller le HPA pendant le test
echo "[INFO] Observation du HPA (mise a jour toutes les 15s)..."
ELAPSED=0
INTERVAL=15
while [[ ${ELAPSED} -lt ${DURATION} ]]; do
  sleep ${INTERVAL}
  ELAPSED=$((ELAPSED + INTERVAL))
  echo ""
  echo "--- T+${ELAPSED}s ---"
  kubectl get hpa -n "${NAMESPACE}" 2>/dev/null || true
  kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=sample-app" --no-headers 2>/dev/null | wc -l | xargs -I{} echo "  Replicas actifs: {}"
done

echo ""

# Nettoyage
echo "[INFO] Nettoyage du pod de stress..."
kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found=true

echo ""
echo "[INFO] Etat du HPA apres le test:"
kubectl get hpa -n "${NAMESPACE}" 2>/dev/null || echo "  Aucun HPA trouve."
echo ""
echo "[INFO] Le HPA mettra quelques minutes a reduire les replicas (cooldown)."
echo "[OK] Demo de stress CPU terminee."
