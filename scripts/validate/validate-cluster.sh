#!/usr/bin/env bash
# ============================================================================
# validate-cluster.sh — Validation sur cluster du projet KubeQuest
# ============================================================================
# Ce script effectue des verifications sur un cluster Kubernetes actif
# pour s'assurer que tous les composants sont correctement deployes.
#
# Prerequis : kubectl doit etre configure et connecte a un cluster.
#
# Phases de verification :
#   1. Cluster (noeuds, labels, CoreDNS, Calico)
#   2. Namespaces (6 namespaces requis)
#   3. Ingress (nginx controller, IngressClass)
#   4. Monitoring (prometheus, grafana, alertmanager)
#   5. Logging (loki, promtail)
#   6. Dashboard (pods, ServiceAccount admin)
#   7. Application (deployment, mysql, service, ingress, HPA, PDB)
#   8. Bonnes pratiques (limites, secrets, labels, replicas)
#   9. Securite (gatekeeper, ConstraintTemplates, NetworkPolicies)
#  10. Backup (CronJob, PVC)
# ============================================================================
set -euo pipefail

# --- Couleurs pour la sortie formatee ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # Pas de couleur

# --- Compteurs globaux ---
PASS_COUNT=0
FAIL_COUNT=0

# --- Compteurs par phase ---
declare -A PHASE_PASS
declare -A PHASE_FAIL
declare -a PHASE_NAMES
CURRENT_PHASE=""

# =============================================================================
# Fonctions utilitaires
# =============================================================================

# Affiche un resultat PASS (reussite)
pass() {
    local msg="$1"
    echo -e "  ${GREEN}✓ PASS${NC} ${msg}"
    ((PASS_COUNT++))
    ((PHASE_PASS[${CURRENT_PHASE}]++))
}

# Affiche un resultat FAIL (echec) — n'arrete pas le script
fail() {
    local msg="$1"
    echo -e "  ${RED}✗ FAIL${NC} ${msg}"
    ((FAIL_COUNT++))
    ((PHASE_FAIL[${CURRENT_PHASE}]++))
}

# Demarre une nouvelle phase de verification
start_phase() {
    local phase_num="$1"
    local phase_name="$2"
    CURRENT_PHASE="${phase_num}"
    PHASE_NAMES+=("${phase_num}:${phase_name}")
    PHASE_PASS[${phase_num}]=0
    PHASE_FAIL[${phase_num}]=0
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  Phase ${phase_num} : ${phase_name}${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# Verification des prerequis
# =============================================================================
echo -e "${BOLD}Validation sur cluster — KubeQuest${NC}"
echo ""

# Verification que kubectl est disponible
if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}${BOLD}ERREUR : kubectl n'est pas installe ou pas dans le PATH.${NC}"
    echo -e "${RED}Ce script necessite un acces a un cluster Kubernetes.${NC}"
    exit 1
fi

# Verification de la connexion au cluster
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}${BOLD}ERREUR : Impossible de se connecter au cluster Kubernetes.${NC}"
    echo -e "${RED}Verifiez votre configuration kubectl (kubeconfig).${NC}"
    exit 1
fi

echo -e "${GREEN}Connexion au cluster etablie.${NC}"

# =============================================================================
# Phase 1 : Verification du cluster (noeuds, composants systeme)
# =============================================================================
start_phase "1" "Cluster"

# Verification du nombre de noeuds Ready (on attend 4 : 1 control-plane + 3 workers)
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || echo "0")
if [[ "${READY_NODES}" -ge 4 ]]; then
    pass "Nombre de noeuds Ready : ${READY_NODES} (>= 4 attendus)"
else
    fail "Nombre de noeuds Ready : ${READY_NODES} (4 attendus)"
fi

# Verification des labels node-type sur les noeuds
LABELED_NODES=$(kubectl get nodes -l node-type --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${LABELED_NODES}" -gt 0 ]]; then
    pass "Label node-type present sur ${LABELED_NODES} noeud(s)"
else
    fail "Label node-type absent des noeuds"
fi

# Verification que CoreDNS fonctionne
COREDNS_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${COREDNS_RUNNING}" -gt 0 ]]; then
    pass "CoreDNS en cours d'execution (${COREDNS_RUNNING} pod(s))"
else
    fail "CoreDNS ne fonctionne pas"
fi

# Verification que Calico (CNI) fonctionne
CALICO_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${CALICO_RUNNING}" -gt 0 ]]; then
    pass "Calico en cours d'execution (${CALICO_RUNNING} pod(s))"
else
    fail "Calico ne fonctionne pas"
fi

# =============================================================================
# Phase 2 : Verification des namespaces
# =============================================================================
start_phase "2" "Namespaces"

# Liste des 6 namespaces requis
REQUIRED_NAMESPACES=(
    "ingress-nginx"
    "monitoring"
    "logging"
    "kubernetes-dashboard"
    "sample-app"
    "security"
)

for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" &>/dev/null; then
        pass "Namespace existe : ${ns}"
    else
        fail "Namespace manquant : ${ns}"
    fi
done

# =============================================================================
# Phase 3 : Verification Ingress (nginx controller)
# =============================================================================
start_phase "3" "Ingress"

# Verification des pods nginx controller
NGINX_RUNNING=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${NGINX_RUNNING}" -gt 0 ]]; then
    pass "Pods nginx controller en execution (${NGINX_RUNNING})"
else
    fail "Aucun pod nginx controller en execution"
fi

# Verification de l'IngressClass
if kubectl get ingressclass nginx &>/dev/null 2>&1; then
    pass "IngressClass 'nginx' existe"
else
    fail "IngressClass 'nginx' manquant"
fi

# =============================================================================
# Phase 4 : Verification Monitoring (prometheus, grafana, alertmanager)
# =============================================================================
start_phase "4" "Monitoring"

# Verification de Prometheus
PROM_RUNNING=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${PROM_RUNNING}" -gt 0 ]]; then
    pass "Prometheus en execution (${PROM_RUNNING} pod(s))"
else
    # Essai avec un autre label courant
    PROM_RUNNING2=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -ci 'prometheus.*running' || echo "0")
    if [[ "${PROM_RUNNING2}" -gt 0 ]]; then
        pass "Prometheus en execution (${PROM_RUNNING2} pod(s))"
    else
        fail "Prometheus ne fonctionne pas dans le namespace monitoring"
    fi
fi

# Verification de Grafana
GRAFANA_RUNNING=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${GRAFANA_RUNNING}" -gt 0 ]]; then
    pass "Grafana en execution (${GRAFANA_RUNNING} pod(s))"
else
    GRAFANA_RUNNING2=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -ci 'grafana.*running' || echo "0")
    if [[ "${GRAFANA_RUNNING2}" -gt 0 ]]; then
        pass "Grafana en execution (${GRAFANA_RUNNING2} pod(s))"
    else
        fail "Grafana ne fonctionne pas dans le namespace monitoring"
    fi
fi

# Verification d'Alertmanager
ALERT_RUNNING=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${ALERT_RUNNING}" -gt 0 ]]; then
    pass "Alertmanager en execution (${ALERT_RUNNING} pod(s))"
else
    ALERT_RUNNING2=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -ci 'alertmanager.*running' || echo "0")
    if [[ "${ALERT_RUNNING2}" -gt 0 ]]; then
        pass "Alertmanager en execution (${ALERT_RUNNING2} pod(s))"
    else
        fail "Alertmanager ne fonctionne pas dans le namespace monitoring"
    fi
fi

# =============================================================================
# Phase 5 : Verification Logging (loki, promtail)
# =============================================================================
start_phase "5" "Logging"

# Verification de Loki
LOKI_RUNNING=$(kubectl get pods -n logging --no-headers 2>/dev/null | grep -ci 'loki.*running' || echo "0")
if [[ "${LOKI_RUNNING}" -gt 0 ]]; then
    pass "Loki en execution (${LOKI_RUNNING} pod(s)) dans logging"
else
    fail "Loki ne fonctionne pas dans le namespace logging"
fi

# Verification du DaemonSet Promtail
PROMTAIL_DS=$(kubectl get daemonset -n logging --no-headers 2>/dev/null | grep -ci 'promtail' || echo "0")
if [[ "${PROMTAIL_DS}" -gt 0 ]]; then
    pass "DaemonSet Promtail present dans logging"
    # Verification que les pods promtail sont en execution
    PROMTAIL_RUNNING=$(kubectl get pods -n logging --no-headers 2>/dev/null | grep -ci 'promtail.*running' || echo "0")
    if [[ "${PROMTAIL_RUNNING}" -gt 0 ]]; then
        pass "Promtail en execution (${PROMTAIL_RUNNING} pod(s))"
    else
        fail "Pods Promtail ne sont pas en execution"
    fi
else
    fail "DaemonSet Promtail absent du namespace logging"
fi

# =============================================================================
# Phase 6 : Verification Dashboard
# =============================================================================
start_phase "6" "Dashboard"

# Verification des pods du dashboard
DASH_RUNNING=$(kubectl get pods -n kubernetes-dashboard --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${DASH_RUNNING}" -gt 0 ]]; then
    pass "Pods dashboard en execution (${DASH_RUNNING})"
else
    fail "Aucun pod dashboard en execution"
fi

# Verification du ServiceAccount admin
if kubectl get serviceaccount admin-user -n kubernetes-dashboard &>/dev/null 2>&1; then
    pass "ServiceAccount admin-user existe dans kubernetes-dashboard"
else
    fail "ServiceAccount admin-user manquant dans kubernetes-dashboard"
fi

# =============================================================================
# Phase 7 : Verification Application (sample-app)
# =============================================================================
start_phase "7" "Application (sample-app)"

# Verification du deployment sample-app
DEPLOY_READY=$(kubectl get deployment -n sample-app --no-headers 2>/dev/null | grep -v 'mysql' | head -1)
if [[ -n "${DEPLOY_READY}" ]]; then
    # Extraction du status ready (ex: "2/2")
    READY_STATUS=$(echo "${DEPLOY_READY}" | awk '{print $2}')
    pass "Deployment sample-app present (${READY_STATUS} ready)"
else
    fail "Deployment sample-app introuvable dans le namespace sample-app"
fi

# Verification de MySQL
MYSQL_RUNNING=$(kubectl get pods -n sample-app --no-headers 2>/dev/null | grep -ci 'mysql.*running' || echo "0")
if [[ "${MYSQL_RUNNING}" -gt 0 ]]; then
    pass "MySQL en execution dans sample-app"
else
    fail "MySQL ne fonctionne pas dans sample-app"
fi

# Verification du PVC MySQL (doit etre Bound)
MYSQL_PVC_BOUND=$(kubectl get pvc -n sample-app --no-headers 2>/dev/null | grep -c 'Bound' || echo "0")
if [[ "${MYSQL_PVC_BOUND}" -gt 0 ]]; then
    pass "PVC MySQL en etat Bound"
else
    fail "PVC MySQL non Bound ou absent"
fi

# Verification du Service
if kubectl get service -n sample-app --no-headers 2>/dev/null | grep -qv 'mysql'; then
    pass "Service sample-app existe"
else
    fail "Service sample-app manquant"
fi

# Verification de l'Ingress
if kubectl get ingress -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "Ingress sample-app existe"
else
    fail "Ingress sample-app manquant"
fi

# Verification du HPA
if kubectl get hpa -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "HPA present dans sample-app"
else
    fail "HPA absent de sample-app"
fi

# Verification du PDB
if kubectl get pdb -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "PDB present dans sample-app"
else
    fail "PDB absent de sample-app"
fi

# =============================================================================
# Phase 8 : Verification des bonnes pratiques
# =============================================================================
start_phase "8" "Bonnes pratiques"

# Verification que les deployments ont des limites de ressources
echo -e "  ${CYAN}--- Limites de ressources ---${NC}"
DEPLOYS_JSON=$(kubectl get deploy -n sample-app -o json 2>/dev/null || echo '{"items":[]}')
DEPLOYS_WITH_LIMITS=$(echo "${DEPLOYS_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for item in data.get('items', []):
    for container in item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', []):
        resources = container.get('resources', {})
        if 'limits' in resources and 'requests' in resources:
            count += 1
print(count)
" 2>/dev/null || echo "0")

TOTAL_CONTAINERS=$(echo "${DEPLOYS_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for item in data.get('items', []):
    count += len(item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', []))
print(count)
" 2>/dev/null || echo "0")

if [[ "${TOTAL_CONTAINERS}" -gt 0 && "${DEPLOYS_WITH_LIMITS}" -eq "${TOTAL_CONTAINERS}" ]]; then
    pass "Tous les conteneurs (${TOTAL_CONTAINERS}) ont des limites de ressources"
elif [[ "${DEPLOYS_WITH_LIMITS}" -gt 0 ]]; then
    fail "Seulement ${DEPLOYS_WITH_LIMITS}/${TOTAL_CONTAINERS} conteneurs ont des limites de ressources"
else
    fail "Aucun conteneur n'a de limites de ressources"
fi

# Verification de l'existence de secrets
echo -e "  ${CYAN}--- Secrets ---${NC}"
SECRETS_COUNT=$(kubectl get secrets -n sample-app --no-headers 2>/dev/null | grep -cv 'default-token\|service-account' || echo "0")
if [[ "${SECRETS_COUNT}" -gt 0 ]]; then
    pass "Secrets presents dans sample-app (${SECRETS_COUNT})"
else
    fail "Aucun secret applicatif dans sample-app"
fi

# Verification des labels sur les pods
echo -e "  ${CYAN}--- Labels ---${NC}"
PODS_WITH_LABELS=$(kubectl get pods -n sample-app -l app.kubernetes.io/name --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${PODS_WITH_LABELS}" -gt 0 ]]; then
    pass "Pods avec label app.kubernetes.io/name (${PODS_WITH_LABELS})"
else
    # Essai avec un label alternatif
    PODS_WITH_APP=$(kubectl get pods -n sample-app -l app --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "${PODS_WITH_APP}" -gt 0 ]]; then
        pass "Pods avec label app (${PODS_WITH_APP})"
    else
        fail "Aucun pod avec des labels standards dans sample-app"
    fi
fi

# Verification du nombre de replicas (haute disponibilite)
echo -e "  ${CYAN}--- Replicas multiples ---${NC}"
APP_REPLICAS=$(kubectl get deploy -n sample-app --no-headers 2>/dev/null | grep -v 'mysql' | head -1 | awk '{print $2}' | cut -d'/' -f1 || echo "0")
if [[ "${APP_REPLICAS}" -ge 2 ]] 2>/dev/null; then
    pass "Application avec ${APP_REPLICAS} replicas (>= 2)"
else
    fail "Application avec ${APP_REPLICAS} replica(s) (>= 2 recommande)"
fi

# =============================================================================
# Phase 9 : Verification Securite (Gatekeeper, contraintes, NetworkPolicies)
# =============================================================================
start_phase "9" "Securite"

# Verification de Gatekeeper
GATEKEEPER_RUNNING=$(kubectl get pods -n gatekeeper-system --no-headers 2>/dev/null | grep -c 'Running' || echo "0")
if [[ "${GATEKEEPER_RUNNING}" -eq 0 ]]; then
    # Essai dans le namespace security
    GATEKEEPER_RUNNING=$(kubectl get pods -n security --no-headers 2>/dev/null | grep -ci 'gatekeeper.*running' || echo "0")
fi
if [[ "${GATEKEEPER_RUNNING}" -gt 0 ]]; then
    pass "Gatekeeper en execution (${GATEKEEPER_RUNNING} pod(s))"
else
    fail "Gatekeeper ne fonctionne pas"
fi

# Verification de 3 ConstraintTemplates
CT_COUNT=$(kubectl get constrainttemplates --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${CT_COUNT}" -ge 3 ]]; then
    pass "ConstraintTemplates presents : ${CT_COUNT} (>= 3 requis)"
else
    fail "ConstraintTemplates insuffisants : ${CT_COUNT} (3 requis)"
fi

# Verification des NetworkPolicies
NETPOL_COUNT=$(kubectl get networkpolicies --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${NETPOL_COUNT}" -gt 0 ]]; then
    pass "NetworkPolicies presentes (${NETPOL_COUNT} au total)"
else
    fail "Aucune NetworkPolicy deployee"
fi

# =============================================================================
# Phase 10 : Verification Backup (CronJob, PVC)
# =============================================================================
start_phase "10" "Backup"

# Verification du CronJob de backup
CJ_COUNT=$(kubectl get cronjob -n sample-app --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${CJ_COUNT}" -gt 0 ]]; then
    pass "CronJob de backup present dans sample-app"
else
    # Essai dans le namespace par defaut
    CJ_COUNT_DEFAULT=$(kubectl get cronjob --all-namespaces --no-headers 2>/dev/null | grep -ci 'backup' || echo "0")
    if [[ "${CJ_COUNT_DEFAULT}" -gt 0 ]]; then
        pass "CronJob de backup present"
    else
        fail "CronJob de backup absent"
    fi
fi

# Verification du PVC pour les backups
BACKUP_PVC=$(kubectl get pvc -n sample-app --no-headers 2>/dev/null | grep -ci 'backup' || echo "0")
if [[ "${BACKUP_PVC}" -gt 0 ]]; then
    pass "PVC de backup present dans sample-app"
else
    # Recherche dans tous les namespaces
    BACKUP_PVC_ALL=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -ci 'backup' || echo "0")
    if [[ "${BACKUP_PVC_ALL}" -gt 0 ]]; then
        pass "PVC de backup present"
    else
        fail "PVC de backup absent"
    fi
fi

# =============================================================================
# RESUME PAR PHASE
# =============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RESUME PAR PHASE${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

for entry in "${PHASE_NAMES[@]}"; do
    phase_num="${entry%%:*}"
    phase_name="${entry#*:}"
    p=${PHASE_PASS[${phase_num}]}
    f=${PHASE_FAIL[${phase_num}]}
    total=$((p + f))
    if [[ "${f}" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Phase ${phase_num} — ${phase_name} : ${GREEN}${p}/${total} passes${NC}"
    else
        echo -e "  ${RED}✗${NC} Phase ${phase_num} — ${phase_name} : ${RED}${p}/${total} passes (${f} echec(s))${NC}"
    fi
done

# =============================================================================
# RESUME GLOBAL
# =============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RAPPORT FINAL — Validation cluster${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo -e "  ${GREEN}Reussis  : ${PASS_COUNT}${NC}"
echo -e "  ${RED}Echoues  : ${FAIL_COUNT}${NC}"
echo ""

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}${PASS_COUNT}/${TOTAL} tests passes${NC}"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}${PASS_COUNT}/${TOTAL} tests passes${NC}"
    echo ""
    exit 1
fi
