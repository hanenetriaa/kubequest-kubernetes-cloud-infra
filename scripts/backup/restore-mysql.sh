#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# restore-mysql.sh - Restaure une base MySQL depuis un fichier de backup
#
# Usage: ./restore-mysql.sh <fichier_backup.sql>
#
# Le script utilise kubectl exec pour injecter le fichier SQL dans MySQL.
###############################################################################

NAMESPACE="sample-app"
MYSQL_POD_LABEL="app.kubernetes.io/name=mysql"
DATABASE="app_database"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <fichier_backup.sql>"
  echo ""
  echo "Exemples:"
  echo "  $0 app_database-20260319-020000.sql        # depuis le PVC (copie locale)"
  echo "  $0 /chemin/local/app_database-backup.sql    # depuis un fichier local"
  exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f "${BACKUP_FILE}" ]]; then
  echo "[ERREUR] Fichier introuvable: ${BACKUP_FILE}"
  exit 1
fi

# Trouver le pod MySQL
echo "[INFO] Recherche du pod MySQL dans le namespace '${NAMESPACE}'..."
MYSQL_POD=$(kubectl get pods -n "${NAMESPACE}" -l "${MYSQL_POD_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "${MYSQL_POD}" ]]; then
  echo "[ERREUR] Aucun pod MySQL trouve avec le label '${MYSQL_POD_LABEL}' dans le namespace '${NAMESPACE}'"
  exit 1
fi

echo "[INFO] Pod MySQL trouve: ${MYSQL_POD}"
echo "[INFO] Fichier de backup: ${BACKUP_FILE} ($(du -h "${BACKUP_FILE}" | cut -f1))"

# Recuperer les identifiants depuis le secret
MYSQL_USER=$(kubectl get secret sample-app-mysql -n "${NAMESPACE}" -o jsonpath='{.data.username}' | base64 -d)
MYSQL_PASSWORD=$(kubectl get secret sample-app-mysql -n "${NAMESPACE}" -o jsonpath='{.data.password}' | base64 -d)

# Confirmation
echo ""
echo "============================================"
echo "  ATTENTION: Restauration de la base MySQL"
echo "  Base    : ${DATABASE}"
echo "  Pod     : ${MYSQL_POD}"
echo "  Fichier : ${BACKUP_FILE}"
echo "============================================"
echo ""
read -r -p "Confirmer la restauration ? (oui/non): " CONFIRM
if [[ "${CONFIRM}" != "oui" ]]; then
  echo "[INFO] Restauration annulee."
  exit 0
fi

# Restauration
echo "[INFO] Restauration en cours..."
kubectl exec -i -n "${NAMESPACE}" "${MYSQL_POD}" -- \
  mysql -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${DATABASE}" < "${BACKUP_FILE}"

echo "[INFO] Restauration terminee avec succes."
