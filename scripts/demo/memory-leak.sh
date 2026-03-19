#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# memory-leak.sh - Simule une fuite memoire pour demontrer les OOM kills
#
# Cree un pod avec une limite memoire basse et un script Python qui
# alloue progressivement de la memoire jusqu'au OOMKill.
###############################################################################

NAMESPACE="sample-app"
POD_NAME="memory-leak-test"
MEMORY_LIMIT="${1:-128Mi}"

echo "============================================"
echo "  Demo: Fuite memoire + OOM Kill"
echo "  Namespace    : ${NAMESPACE}"
echo "  Limite RAM   : ${MEMORY_LIMIT}"
echo "============================================"
echo ""

# Nettoyage prealable
echo "[INFO] Nettoyage de tout pod de test existant..."
kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found=true
sleep 2

# Creer le pod avec un script qui consomme la memoire progressivement
echo "[INFO] Creation du pod avec fuite memoire simulee..."
cat <<PODEOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    purpose: memory-leak-test
spec:
  restartPolicy: Always
  containers:
    - name: memory-leak
      image: python:3.11-slim
      resources:
        requests:
          memory: "64Mi"
          cpu: "50m"
        limits:
          memory: "${MEMORY_LIMIT}"
          cpu: "200m"
      command:
        - python3
        - -c
        - |
          import time
          import sys

          print("[LEAK] Demarrage de la fuite memoire simulee...", flush=True)
          print(f"[LEAK] Limite memoire: ${MEMORY_LIMIT}", flush=True)

          data = []
          chunk_size = 10 * 1024 * 1024  # 10 Mo par iteration
          total = 0

          while True:
              chunk = bytearray(chunk_size)
              data.append(chunk)
              total += chunk_size
              total_mb = total / (1024 * 1024)
              print(f"[LEAK] Memoire allouee: {total_mb:.0f} Mo", flush=True)
              time.sleep(2)
PODEOF

echo "[INFO] Pod cree. Observation des OOM kills..."
echo ""

# Surveiller le pod
echo "[INFO] Suivi du pod (Ctrl+C pour arreter la surveillance)..."
WATCH_DURATION=120
ELAPSED=0
INTERVAL=5
OOM_COUNT=0

while [[ ${ELAPSED} -lt ${WATCH_DURATION} ]]; do
  sleep ${INTERVAL}
  ELAPSED=$((ELAPSED + INTERVAL))

  # Status du pod
  POD_STATUS=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Inconnu")
  RESTART_COUNT=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
  LAST_STATE=$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || echo "")

  echo "[T+${ELAPSED}s] Status: ${POD_STATUS} | Redemarrages: ${RESTART_COUNT} | Dernier arret: ${LAST_STATE:-N/A}"

  if [[ "${LAST_STATE}" == "OOMKilled" ]]; then
    OOM_COUNT=$((OOM_COUNT + 1))
    if [[ ${OOM_COUNT} -ge 2 ]]; then
      echo ""
      echo "[INFO] OOMKill detecte ${OOM_COUNT} fois. Demo concluante."
      break
    fi
  fi
done

echo ""
echo "[INFO] Logs du pod:"
kubectl logs "${POD_NAME}" -n "${NAMESPACE}" --tail=20 2>/dev/null || echo "  (logs non disponibles)"

echo ""
echo "[INFO] Description du pod (evenements):"
kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}" 2>/dev/null | grep -A5 "Events:" || true

# Nettoyage
echo ""
echo "[INFO] Nettoyage du pod de test..."
kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found=true

echo ""
echo "[OK] Demo de fuite memoire terminee."
echo "  Le pod a ete OOMKilled ${OOM_COUNT} fois, demontrant la gestion"
echo "  des limites memoire par Kubernetes."
