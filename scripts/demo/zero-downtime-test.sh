#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# zero-downtime-test.sh - Verifie le zero-downtime pendant un rolling update
#
# Envoie des requetes HTTP en continu pendant qu'un rolling update est
# declenche, puis compte les requetes reussies vs echouees.
###############################################################################

NAMESPACE="sample-app"
DEPLOYMENT="sample-app"
APP_URL="${APP_URL:-http://localhost:30080}"
HEALTH_ENDPOINT="${APP_URL}/health"
REQUEST_INTERVAL="0.1"  # secondes entre chaque requete

echo "============================================"
echo "  Demo: Test Zero-Downtime Deployment"
echo "  Namespace  : ${NAMESPACE}"
echo "  Deployment : ${DEPLOYMENT}"
echo "  URL        : ${HEALTH_ENDPOINT}"
echo "============================================"
echo ""

# Verifier que l'application repond
echo "[INFO] Verification de l'application..."
if ! curl -s -o /dev/null -w "%{http_code}" "${HEALTH_ENDPOINT}" | grep -q "200"; then
  echo "[ERREUR] L'application ne repond pas sur ${HEALTH_ENDPOINT}"
  echo "  Definissez APP_URL si l'URL est differente."
  exit 1
fi
echo "[INFO] Application OK."
echo ""

# Fichier temporaire pour les resultats
RESULTS_FILE=$(mktemp)
PID_FILE=$(mktemp)
trap 'rm -f "${RESULTS_FILE}" "${PID_FILE}"' EXIT

# Lancer les requetes en arriere-plan
echo "[INFO] Demarrage des requetes continues..."
(
  while true; do
    TIMESTAMP=$(date +%H:%M:%S.%N | cut -c1-12)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 "${HEALTH_ENDPOINT}" 2>/dev/null || echo "000")
    echo "${TIMESTAMP} ${HTTP_CODE}" >> "${RESULTS_FILE}"
    sleep "${REQUEST_INTERVAL}"
  done
) &
REQUESTER_PID=$!
echo "${REQUESTER_PID}" > "${PID_FILE}"

echo "[INFO] Requetes en cours (PID: ${REQUESTER_PID})..."
echo ""

# Attendre un peu pour avoir une baseline
sleep 5

# Declencher un rolling update (ajout d'une annotation pour forcer le redeploy)
echo "[INFO] Declenchement du rolling update..."
kubectl annotate deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
  "zero-downtime-test/timestamp=$(date +%s)" --overwrite

echo "[INFO] Attente du rollout..."
kubectl rollout status deployment/"${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s

echo "[INFO] Rolling update termine."
echo ""

# Attendre encore un peu apres le rollout
sleep 10

# Arreter les requetes
kill "${REQUESTER_PID}" 2>/dev/null || true
wait "${REQUESTER_PID}" 2>/dev/null || true
sleep 1

# Analyser les resultats
TOTAL=$(wc -l < "${RESULTS_FILE}")
SUCCESS=$(grep -c " 200$" "${RESULTS_FILE}" || true)
FAILED=$((TOTAL - SUCCESS))

echo "============================================"
echo "  Resultats du test Zero-Downtime"
echo "============================================"
echo ""
echo "  Total requetes     : ${TOTAL}"
echo "  Requetes reussies  : ${SUCCESS} (HTTP 200)"
echo "  Requetes echouees  : ${FAILED}"
echo ""

if [[ ${TOTAL} -gt 0 ]]; then
  SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", (${SUCCESS}/${TOTAL})*100}")
  echo "  Taux de succes     : ${SUCCESS_RATE}%"
  echo ""
fi

if [[ ${FAILED} -eq 0 ]]; then
  echo "  [OK] ZERO-DOWNTIME CONFIRME!"
  echo "  Aucune requete n'a echoue pendant le rolling update."
else
  echo "  [WARN] ${FAILED} requete(s) echouee(s) pendant le rolling update."
  echo ""
  echo "  Detail des echecs:"
  grep -v " 200$" "${RESULTS_FILE}" | head -20
  echo ""
  echo "  Verifiez la configuration des probes et du PodDisruptionBudget."
fi

echo ""
echo "[OK] Test zero-downtime termine."
