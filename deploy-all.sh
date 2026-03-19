#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# deploy-all.sh - Script principal de deploiement KubeQuest
#
# Ce script orchestre le deploiement complet de la plateforme:
#   1. Creation des namespaces
#   2. Deploiement de l'infrastructure (monitoring, ingress, etc.)
#   3. Deploiement de l'application via Helm
#   4. Configuration des backups
#   5. Verification de l'etat des deploiements
#   6. Affichage des URLs d'acces
#
# Usage:
#   ./deploy-all.sh             # Deploiement complet
#   ./deploy-all.sh --dry-run   # Simulation sans appliquer les changements
###############################################################################

# Repertoire racine du projet
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# Couleurs pour la sortie console
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Pas de couleur

###############################################################################
# Fonctions utilitaires
###############################################################################

# Affiche un message d'information
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

# Affiche un message de succes
log_ok() {
  echo -e "${GREEN}[OK]${NC} $1"
}

# Affiche un avertissement
log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

# Affiche une erreur et quitte
log_error() {
  echo -e "${RED}[ERREUR]${NC} $1"
  exit 1
}

# Affiche un titre d'etape
print_step() {
  local step_num=$1
  local step_desc=$2
  echo ""
  echo "============================================"
  echo "  Etape ${step_num}: ${step_desc}"
  echo "============================================"
  echo ""
}

# Execute une commande kubectl (ou affiche en mode dry-run)
run_kubectl() {
  if [[ "${DRY_RUN}" == true ]]; then
    log_warn "[DRY-RUN] kubectl $*"
  else
    kubectl "$@"
  fi
}

# Execute une commande helm (ou affiche en mode dry-run)
run_helm() {
  if [[ "${DRY_RUN}" == true ]]; then
    log_warn "[DRY-RUN] helm $*"
  else
    helm "$@"
  fi
}

###############################################################################
# Traitement des arguments
###############################################################################

for arg in "$@"; do
  case ${arg} in
    --dry-run)
      DRY_RUN=true
      log_warn "Mode DRY-RUN active - aucune modification ne sera appliquee."
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dry-run    Simulation sans appliquer les changements"
      echo "  --help, -h   Afficher cette aide"
      exit 0
      ;;
    *)
      log_error "Option inconnue: ${arg}. Utilisez --help pour l'aide."
      ;;
  esac
done

###############################################################################
# Verifications prealables
###############################################################################

echo ""
echo "####################################################"
echo "#                                                  #"
echo "#           KubeQuest - Deploiement complet        #"
echo "#                                                  #"
echo "####################################################"
echo ""

log_info "Verification des prerequis..."

# Verifier que kubectl est disponible
if ! command -v kubectl &>/dev/null; then
  log_error "kubectl n'est pas installe. Veuillez l'installer avant de continuer."
fi

# Verifier que helm est disponible
if ! command -v helm &>/dev/null; then
  log_error "helm n'est pas installe. Veuillez l'installer avant de continuer."
fi

# Verifier la connexion au cluster
if ! kubectl cluster-info &>/dev/null; then
  log_error "Impossible de se connecter au cluster Kubernetes. Verifiez votre kubeconfig."
fi

log_ok "Prerequis verifies: kubectl, helm, connexion au cluster."

###############################################################################
# Etape 1: Creation des namespaces
###############################################################################

print_step 1 "Creation des namespaces"

# Appliquer tous les fichiers de namespace trouves dans le projet
if [[ -d "${SCRIPT_DIR}/gitops/base" ]]; then
  log_info "Application des namespaces depuis gitops/base..."
  run_kubectl apply -f "${SCRIPT_DIR}/gitops/base/namespace.yaml"
fi

# Creer les namespaces d'infrastructure si necessaire
for NS in monitoring ingress-nginx; do
  log_info "Creation du namespace '${NS}' (si inexistant)..."
  if [[ "${DRY_RUN}" == false ]]; then
    kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -
  else
    log_warn "[DRY-RUN] kubectl create namespace ${NS}"
  fi
done

log_ok "Namespaces crees."

###############################################################################
# Etape 2: Deploiement de l'infrastructure
###############################################################################

print_step 2 "Deploiement de l'infrastructure"

INFRA_SCRIPT="${SCRIPT_DIR}/infrastructure/deploy-infra.sh"
if [[ -f "${INFRA_SCRIPT}" ]]; then
  log_info "Execution de infrastructure/deploy-infra.sh..."
  if [[ "${DRY_RUN}" == false ]]; then
    bash "${INFRA_SCRIPT}"
  else
    log_warn "[DRY-RUN] bash ${INFRA_SCRIPT}"
  fi
  log_ok "Infrastructure deployee."
else
  log_warn "Script ${INFRA_SCRIPT} introuvable. Etape ignoree."
fi

###############################################################################
# Etape 3: Deploiement de l'application via Helm
###############################################################################

print_step 3 "Deploiement de l'application (Helm)"

CHART_DIR="${SCRIPT_DIR}/charts/sample-app"
VALUES_FILE="${CHART_DIR}/values.yaml"

if [[ -d "${CHART_DIR}" ]]; then
  log_info "Deploiement du chart Helm sample-app..."
  run_helm upgrade --install sample-app \
    "${CHART_DIR}" \
    -n sample-app \
    -f "${VALUES_FILE}" \
    --create-namespace \
    --wait \
    --timeout 5m
  log_ok "Application deployee via Helm."
else
  log_warn "Chart Helm ${CHART_DIR} introuvable. Etape ignoree."
fi

###############################################################################
# Etape 4: Configuration des backups
###############################################################################

print_step 4 "Configuration des sauvegardes automatiques"

BACKUP_MANIFEST="${SCRIPT_DIR}/scripts/backup/mysql-backup-cronjob.yaml"
if [[ -f "${BACKUP_MANIFEST}" ]]; then
  log_info "Application du CronJob de backup MySQL..."
  run_kubectl apply -f "${BACKUP_MANIFEST}"
  log_ok "CronJob de backup configure (tous les jours a 2h00)."
else
  log_warn "Manifest de backup ${BACKUP_MANIFEST} introuvable. Etape ignoree."
fi

###############################################################################
# Etape 5: Attente de la disponibilite des deploiements
###############################################################################

print_step 5 "Verification de la disponibilite des deploiements"

if [[ "${DRY_RUN}" == false ]]; then
  # Attendre que tous les deploiements soient prets dans chaque namespace
  for NS in sample-app monitoring ingress-nginx; do
    log_info "Verification des deploiements dans le namespace '${NS}'..."
    DEPLOYMENTS=$(kubectl get deployments -n "${NS}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "${DEPLOYMENTS}" ]]; then
      for DEP in ${DEPLOYMENTS}; do
        log_info "  Attente de ${DEP}..."
        if kubectl rollout status deployment/"${DEP}" -n "${NS}" --timeout=300s; then
          log_ok "  ${DEP} est pret."
        else
          log_warn "  ${DEP} n'est pas pret apres 5 minutes."
        fi
      done
    else
      log_info "  Aucun deploiement dans ${NS}."
    fi
  done
else
  log_warn "[DRY-RUN] Verification des deploiements ignoree."
fi

log_ok "Verification terminee."

###############################################################################
# Etape 6: Affichage du statut et des URLs d'acces
###############################################################################

print_step 6 "Statut final et URLs d'acces"

if [[ "${DRY_RUN}" == false ]]; then
  echo "--- Deploiements ---"
  kubectl get deployments -A --no-headers 2>/dev/null | column -t || true
  echo ""

  echo "--- Pods ---"
  kubectl get pods -A --no-headers 2>/dev/null | column -t || true
  echo ""

  echo "--- Services ---"
  kubectl get svc -A --no-headers 2>/dev/null | column -t || true
  echo ""

  echo "--- CronJobs ---"
  kubectl get cronjobs -A --no-headers 2>/dev/null | column -t || true
  echo ""

  # Recuperer les URLs d'acces
  echo ""
  echo "####################################################"
  echo "#               URLs d'acces                       #"
  echo "####################################################"
  echo ""

  # NodePort de l'application
  APP_NODEPORT=$(kubectl get svc -n sample-app -l "app.kubernetes.io/name=sample-app" \
    -o jsonpath='{.items[0].spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
  MASTER_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "<MASTER_IP>")

  echo "  Application     : http://${MASTER_IP}:${APP_NODEPORT}"

  # Grafana
  GRAFANA_PORT=$(kubectl get svc -n monitoring -l "app.kubernetes.io/name=grafana" \
    -o jsonpath='{.items[0].spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
  if [[ "${GRAFANA_PORT}" != "N/A" ]]; then
    echo "  Grafana          : http://${MASTER_IP}:${GRAFANA_PORT}"
  fi

  # Prometheus
  PROM_PORT=$(kubectl get svc -n monitoring -l "app=prometheus" \
    -o jsonpath='{.items[0].spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
  if [[ "${PROM_PORT}" != "N/A" ]]; then
    echo "  Prometheus       : http://${MASTER_IP}:${PROM_PORT}"
  fi

  echo ""
else
  log_warn "[DRY-RUN] Affichage du statut ignore."
fi

echo ""
echo "####################################################"
echo "#                                                  #"
echo "#     Deploiement KubeQuest termine avec succes    #"
echo "#                                                  #"
echo "####################################################"
echo ""
log_ok "Tout est pret! Utilisez les scripts dans scripts/demo/ pour les demonstrations."
