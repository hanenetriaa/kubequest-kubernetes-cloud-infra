#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# load-test.sh - Test de charge sur l'endpoint compteur de l'application
#
# Envoie 1000 requetes avec 10 workers concurrents.
# Affiche les valeurs du compteur avant et apres le test.
###############################################################################

APP_URL="${APP_URL:-http://localhost:30080}"
COUNTER_ENDPOINT="${APP_URL}/counter"
TOTAL_REQUESTS=1000
CONCURRENCY=10

echo "============================================"
echo "  Test de charge - KubeQuest"
echo "  URL      : ${COUNTER_ENDPOINT}"
echo "  Requetes : ${TOTAL_REQUESTS}"
echo "  Workers  : ${CONCURRENCY}"
echo "============================================"
echo ""

# Valeur du compteur avant le test
echo "[INFO] Valeur du compteur AVANT le test:"
BEFORE=$(curl -s "${COUNTER_ENDPOINT}" 2>/dev/null || echo "N/A")
echo "  -> ${BEFORE}"
echo ""

# Verifier si 'hey' est installe
if command -v hey &>/dev/null; then
  echo "[INFO] Utilisation de 'hey' pour le test de charge..."
  hey -n "${TOTAL_REQUESTS}" -c "${CONCURRENCY}" "${COUNTER_ENDPOINT}"
else
  echo "[INFO] 'hey' non installe. Utilisation de curl en boucle."
  echo "[CONSEIL] Pour de meilleurs resultats, installez 'hey':"
  echo "  go install github.com/rakyll/hey@latest"
  echo ""

  SUCCESS=0
  FAIL=0
  START_TIME=$(date +%s)

  # Fonction worker
  worker() {
    local id=$1
    local count=$2
    local ok=0
    local ko=0
    for ((i = 0; i < count; i++)); do
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${COUNTER_ENDPOINT}" 2>/dev/null || echo "000")
      if [[ "${HTTP_CODE}" == "200" ]]; then
        ((ok++))
      else
        ((ko++))
      fi
    done
    echo "${ok} ${ko}"
  }

  REQUESTS_PER_WORKER=$((TOTAL_REQUESTS / CONCURRENCY))
  TMPDIR_RESULTS=$(mktemp -d)

  echo "[INFO] Lancement de ${CONCURRENCY} workers (${REQUESTS_PER_WORKER} requetes chacun)..."

  for ((w = 0; w < CONCURRENCY; w++)); do
    worker "${w}" "${REQUESTS_PER_WORKER}" > "${TMPDIR_RESULTS}/worker_${w}.txt" &
  done

  # Attendre tous les workers
  wait

  # Agreger les resultats
  for ((w = 0; w < CONCURRENCY; w++)); do
    RESULT=$(cat "${TMPDIR_RESULTS}/worker_${w}.txt")
    OK=$(echo "${RESULT}" | awk '{print $1}')
    KO=$(echo "${RESULT}" | awk '{print $2}')
    SUCCESS=$((SUCCESS + OK))
    FAIL=$((FAIL + KO))
  done

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  rm -rf "${TMPDIR_RESULTS}"

  echo ""
  echo "--------------------------------------------"
  echo "  Resultats du test de charge (curl)"
  echo "--------------------------------------------"
  echo "  Requetes reussies : ${SUCCESS}"
  echo "  Requetes echouees : ${FAIL}"
  echo "  Duree             : ${DURATION}s"
  if [[ ${DURATION} -gt 0 ]]; then
    RPS=$((TOTAL_REQUESTS / DURATION))
    echo "  Debit approx.     : ${RPS} req/s"
  fi
  echo "--------------------------------------------"
fi

echo ""

# Valeur du compteur apres le test
echo "[INFO] Valeur du compteur APRES le test:"
AFTER=$(curl -s "${COUNTER_ENDPOINT}" 2>/dev/null || echo "N/A")
echo "  -> ${AFTER}"

echo ""
echo "[INFO] Test de charge termine."
