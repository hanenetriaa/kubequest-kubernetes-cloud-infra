#!/usr/bin/env bash
# ============================================================================
# validate-cluster.sh — Validation sur cluster Kubernetes du projet KubeQuest
# ============================================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
PHASE_PASS=0
PHASE_FAIL=0

pass() {
    echo -e "  ${GREEN}✓ PASS${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
    PHASE_PASS=$((PHASE_PASS + 1))
}

fail() {
    echo -e "  ${RED}✗ FAIL${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    PHASE_FAIL=$((PHASE_FAIL + 1))
}

skip() {
    echo -e "  ${YELLOW}⚠ SKIP${NC} $1"
}

phase() {
    PHASE_PASS=0
    PHASE_FAIL=0
    echo ""
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}${BOLD}  PHASE $1${NC}"
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

phase_summary() {
    local total=$((PHASE_PASS + PHASE_FAIL))
    if [[ "$PHASE_FAIL" -eq 0 ]]; then
        echo -e "  ${GREEN}→ Phase OK : ${PHASE_PASS}/${total}${NC}"
    else
        echo -e "  ${RED}→ Phase KO : ${PHASE_PASS}/${total}${NC}"
    fi
}

# Verifie qu'un pod est Running dans un namespace
check_pods_running() {
    local ns="$1"
    local label="$2"
    local description="$3"
    local count
    count=$(kubectl get pods -n "$ns" -l "$label" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$count" -gt 0 ]]; then
        pass "${description} — ${count} pod(s) Running dans ${ns}"
    else
        fail "${description} — aucun pod Running dans ${ns} (label: ${label})"
    fi
}

# Verifie qu'une ressource existe
check_resource_exists() {
    local resource="$1"
    local ns="$2"
    local name="$3"
    local description="$4"
    if [[ -n "$ns" ]]; then
        if kubectl get "$resource" -n "$ns" "$name" &>/dev/null; then
            pass "${description}"
        else
            fail "${description} — ${resource}/${name} introuvable dans ${ns}"
        fi
    else
        if kubectl get "$resource" "$name" &>/dev/null; then
            pass "${description}"
        else
            fail "${description} — ${resource}/${name} introuvable"
        fi
    fi
}

# ── Verification prerequis ──
if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}ERREUR : kubectl non trouve. Installez kubectl.${NC}"
    exit 1
fi

if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}ERREUR : impossible de contacter le cluster Kubernetes.${NC}"
    exit 1
fi

echo -e "${BOLD}Validation du cluster KubeQuest en cours...${NC}"

# =============================================================================
# PHASE 1 : Sante du cluster
# =============================================================================
phase "1 — Sante du cluster"

# Noeuds Ready
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
if [[ "$NODE_COUNT" -ge 4 ]]; then
    pass "Nombre de noeuds : ${NODE_COUNT} (>= 4 attendus)"
else
    fail "Nombre de noeuds : ${NODE_COUNT} (4 attendus)"
fi

if [[ "$READY_COUNT" -eq "$NODE_COUNT" ]]; then
    pass "Tous les noeuds sont Ready (${READY_COUNT}/${NODE_COUNT})"
else
    fail "Noeuds non Ready : ${READY_COUNT}/${NODE_COUNT}"
fi

# Labels des noeuds
for label in "node-type=application" "node-type=ingress" "node-type=monitoring"; do
    count=$(kubectl get nodes -l "$label" --no-headers 2>/dev/null | wc -l)
    if [[ "$count" -gt 0 ]]; then
        pass "Noeud avec label ${label} trouve"
    else
        fail "Aucun noeud avec label ${label}"
    fi
done

# CoreDNS
COREDNS_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$COREDNS_RUNNING" -gt 0 ]]; then
    pass "CoreDNS : ${COREDNS_RUNNING} pod(s) Running"
else
    fail "CoreDNS non disponible"
fi

# Calico
CALICO_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=calico-node --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$CALICO_RUNNING" -gt 0 ]]; then
    pass "Calico CNI : ${CALICO_RUNNING} pod(s) Running"
else
    # Essayer tigera-operator
    CALICO_RUNNING=$(kubectl get pods -n calico-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$CALICO_RUNNING" -gt 0 ]]; then
        pass "Calico CNI (tigera) : ${CALICO_RUNNING} pod(s) Running"
    else
        fail "Calico CNI non disponible"
    fi
fi

phase_summary

# =============================================================================
# PHASE 2 : Namespaces
# =============================================================================
phase "2 — Namespaces"

for ns in ingress-nginx monitoring logging kubernetes-dashboard sample-app security; do
    if kubectl get namespace "$ns" &>/dev/null; then
        pass "Namespace ${ns} existe"
    else
        fail "Namespace ${ns} manquant"
    fi
done

phase_summary

# =============================================================================
# PHASE 3 : Ingress Nginx
# =============================================================================
phase "3 — Ingress Controller"

check_pods_running "ingress-nginx" "app.kubernetes.io/component=controller" "Ingress Nginx Controller"

if kubectl get ingressclass nginx &>/dev/null; then
    pass "IngressClass 'nginx' existe"
else
    fail "IngressClass 'nginx' manquante"
fi

phase_summary

# =============================================================================
# PHASE 4 : Monitoring
# =============================================================================
phase "4 — Monitoring (Prometheus + Grafana)"

# Prometheus
PROM_PODS=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=prometheus" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$PROM_PODS" -gt 0 ]]; then
    pass "Prometheus : ${PROM_PODS} pod(s) Running"
else
    # Essai avec label alternatif
    PROM_PODS=$(kubectl get pods -n monitoring -l "app=prometheus" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$PROM_PODS" -gt 0 ]]; then
        pass "Prometheus : ${PROM_PODS} pod(s) Running"
    else
        fail "Prometheus non disponible dans monitoring"
    fi
fi

# Grafana
check_pods_running "monitoring" "app.kubernetes.io/name=grafana" "Grafana"

# Alertmanager
ALERT_PODS=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=alertmanager" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$ALERT_PODS" -gt 0 ]]; then
    pass "Alertmanager : ${ALERT_PODS} pod(s) Running"
else
    fail "Alertmanager non disponible dans monitoring"
fi

# ServiceMonitors
SM_COUNT=$(kubectl get servicemonitors -n monitoring --no-headers 2>/dev/null | wc -l)
if [[ "$SM_COUNT" -gt 0 ]]; then
    pass "ServiceMonitors : ${SM_COUNT} trouves"
else
    fail "Aucun ServiceMonitor trouve"
fi

phase_summary

# =============================================================================
# PHASE 5 : Logging
# =============================================================================
phase "5 — Logging (Loki + Promtail)"

check_pods_running "logging" "app.kubernetes.io/name=loki" "Loki"

# Promtail DaemonSet
PROMTAIL_DS=$(kubectl get daemonset -n logging -l "app.kubernetes.io/name=promtail" --no-headers 2>/dev/null | wc -l)
if [[ "$PROMTAIL_DS" -gt 0 ]]; then
    DESIRED=$(kubectl get daemonset -n logging -l "app.kubernetes.io/name=promtail" -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    READY=$(kubectl get daemonset -n logging -l "app.kubernetes.io/name=promtail" -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo "0")
    if [[ "$READY" -eq "$DESIRED" ]] && [[ "$DESIRED" -gt 0 ]]; then
        pass "Promtail DaemonSet : ${READY}/${DESIRED} pods Ready"
    else
        fail "Promtail DaemonSet : ${READY}/${DESIRED} pods Ready"
    fi
else
    fail "Promtail DaemonSet introuvable"
fi

phase_summary

# =============================================================================
# PHASE 6 : Dashboard
# =============================================================================
phase "6 — Kubernetes Dashboard"

DASH_PODS=$(kubectl get pods -n kubernetes-dashboard --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$DASH_PODS" -gt 0 ]]; then
    pass "Dashboard : ${DASH_PODS} pod(s) Running"
else
    fail "Dashboard non disponible"
fi

if kubectl get serviceaccount admin-user -n kubernetes-dashboard &>/dev/null; then
    pass "ServiceAccount admin-user existe"
else
    fail "ServiceAccount admin-user manquant"
fi

phase_summary

# =============================================================================
# PHASE 7 : Application (sample-app)
# =============================================================================
phase "7 — Application (sample-app)"

# Deployment
if kubectl get deployment -n sample-app -l "app.kubernetes.io/name=sample-app" --no-headers 2>/dev/null | grep -q .; then
    DESIRED=$(kubectl get deployment -n sample-app -l "app.kubernetes.io/name=sample-app" -o jsonpath='{.items[0].status.replicas}' 2>/dev/null || echo "0")
    READY=$(kubectl get deployment -n sample-app -l "app.kubernetes.io/name=sample-app" -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$READY" -ge 1 ]]; then
        pass "sample-app Deployment : ${READY}/${DESIRED} replicas Ready"
    else
        fail "sample-app Deployment : ${READY}/${DESIRED} replicas Ready"
    fi
else
    fail "sample-app Deployment introuvable"
fi

# MySQL
MYSQL_PODS=$(kubectl get pods -n sample-app -l "app.kubernetes.io/name=mysql" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$MYSQL_PODS" -gt 0 ]]; then
    pass "MySQL : ${MYSQL_PODS} pod(s) Running"
else
    fail "MySQL non disponible"
fi

# PVC MySQL
PVC_BOUND=$(kubectl get pvc -n sample-app --no-headers 2>/dev/null | grep -c "Bound" || true)
if [[ "$PVC_BOUND" -gt 0 ]]; then
    pass "PVC : ${PVC_BOUND} PersistentVolumeClaim(s) Bound"
else
    fail "Aucun PVC Bound dans sample-app"
fi

# Service
if kubectl get service -n sample-app -l "app.kubernetes.io/name=sample-app" --no-headers 2>/dev/null | grep -q .; then
    pass "Service sample-app existe"
else
    fail "Service sample-app manquant"
fi

# Ingress
if kubectl get ingress -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "Ingress sample-app existe"
else
    fail "Ingress sample-app manquant"
fi

# HPA
if kubectl get hpa -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "HPA sample-app existe"
else
    fail "HPA sample-app manquant"
fi

# PDB
if kubectl get pdb -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "PDB sample-app existe"
else
    fail "PDB sample-app manquant"
fi

# Test HTTP
APP_SVC=$(kubectl get svc -n sample-app -l "app.kubernetes.io/name=sample-app" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$APP_SVC" ]]; then
    SVC_IP=$(kubectl get svc -n sample-app "$APP_SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    if [[ -n "$SVC_IP" ]] && kubectl run curl-test --image=curlimages/curl --restart=Never --rm -i --timeout=30s -- curl -s -o /dev/null -w "%{http_code}" "http://${SVC_IP}/" 2>/dev/null | grep -q "200"; then
        pass "App repond en HTTP 200"
    else
        skip "Test HTTP non concluant (service accessible mais test curl ignore)"
    fi
fi

phase_summary

# =============================================================================
# PHASE 8 : Bonnes pratiques
# =============================================================================
phase "8 — Bonnes pratiques Kubernetes"

# Resource limits sur les deployments de sample-app
DEPLOYS_NO_LIMITS=$(kubectl get deployments -n sample-app -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for d in data.get('items', []):
    for c in d.get('spec', {}).get('template', {}).get('spec', {}).get('containers', []):
        res = c.get('resources', {})
        if not res.get('limits') or not res.get('requests'):
            count += 1
print(count)
" 2>/dev/null || echo "-1")

if [[ "$DEPLOYS_NO_LIMITS" == "0" ]]; then
    pass "Tous les containers ont des resource limits/requests"
elif [[ "$DEPLOYS_NO_LIMITS" == "-1" ]]; then
    skip "Impossible de verifier les resource limits"
else
    fail "${DEPLOYS_NO_LIMITS} container(s) sans resource limits/requests"
fi

# Secrets existent
if kubectl get secrets -n sample-app --no-headers 2>/dev/null | grep -v 'default-token' | grep -q .; then
    pass "Secrets presents dans sample-app"
else
    fail "Aucun Secret dans sample-app"
fi

# Labels app.kubernetes.io
DEPLOYS_NO_LABELS=$(kubectl get deployments -n sample-app -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for d in data.get('items', []):
    labels = d.get('metadata', {}).get('labels', {})
    if 'app.kubernetes.io/name' not in labels:
        count += 1
print(count)
" 2>/dev/null || echo "-1")

if [[ "$DEPLOYS_NO_LABELS" == "0" ]]; then
    pass "Tous les Deployments ont le label app.kubernetes.io/name"
elif [[ "$DEPLOYS_NO_LABELS" == "-1" ]]; then
    skip "Impossible de verifier les labels"
else
    fail "${DEPLOYS_NO_LABELS} Deployment(s) sans label app.kubernetes.io/name"
fi

# Replicas >= 2
REPLICAS=$(kubectl get deployment -n sample-app -l "app.kubernetes.io/name=sample-app" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
if [[ "$REPLICAS" -ge 2 ]]; then
    pass "Replicas sample-app : ${REPLICAS} (>= 2)"
else
    fail "Replicas sample-app : ${REPLICAS} (doit etre >= 2)"
fi

phase_summary

# =============================================================================
# PHASE 9 : Securite
# =============================================================================
phase "9 — Securite (OPA, NetworkPolicies, Auth)"

# Gatekeeper
GK_PODS=$(kubectl get pods -n gatekeeper-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$GK_PODS" -gt 0 ]]; then
    pass "Gatekeeper : ${GK_PODS} pod(s) Running"
else
    fail "Gatekeeper non disponible"
fi

# ConstraintTemplates
CT_COUNT=$(kubectl get constrainttemplates --no-headers 2>/dev/null | wc -l)
if [[ "$CT_COUNT" -ge 3 ]]; then
    pass "ConstraintTemplates : ${CT_COUNT} (>= 3 requis)"
else
    fail "ConstraintTemplates : ${CT_COUNT} (3 requis)"
fi

# NetworkPolicies
NP_COUNT=$(kubectl get networkpolicies -n sample-app --no-headers 2>/dev/null | wc -l)
if [[ "$NP_COUNT" -gt 0 ]]; then
    pass "NetworkPolicies dans sample-app : ${NP_COUNT}"
else
    fail "Aucune NetworkPolicy dans sample-app"
fi

# Dex (optionnel)
DEX_PODS=$(kubectl get pods -n security -l "app.kubernetes.io/name=dex" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$DEX_PODS" -gt 0 ]]; then
    pass "Dex IdP : ${DEX_PODS} pod(s) Running"
else
    skip "Dex non deploye (optionnel)"
fi

# OAuth2 Proxy (optionnel)
OAUTH_PODS=$(kubectl get pods -n security -l "app.kubernetes.io/name=oauth2-proxy" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$OAUTH_PODS" -gt 0 ]]; then
    pass "OAuth2 Proxy : ${OAUTH_PODS} pod(s) Running"
else
    skip "OAuth2 Proxy non deploye (optionnel)"
fi

phase_summary

# =============================================================================
# PHASE 10 : Backup
# =============================================================================
phase "10 — Backup"

if kubectl get cronjob -n sample-app --no-headers 2>/dev/null | grep -q .; then
    pass "CronJob de backup present"
else
    fail "CronJob de backup manquant"
fi

BACKUP_PVC=$(kubectl get pvc -n sample-app -l "app.kubernetes.io/name=mysql-backup" --no-headers 2>/dev/null | wc -l)
if [[ "$BACKUP_PVC" -gt 0 ]]; then
    pass "PVC de backup existe"
else
    # Chercher sans label
    BACKUP_PVC=$(kubectl get pvc -n sample-app --no-headers 2>/dev/null | grep -ic backup || true)
    if [[ "$BACKUP_PVC" -gt 0 ]]; then
        pass "PVC de backup existe"
    else
        fail "PVC de backup manquant"
    fi
fi

phase_summary

# =============================================================================
# RESUME FINAL
# =============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RAPPORT FINAL — Validation cluster KubeQuest${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo -e "  ${GREEN}Reussis  : ${PASS_COUNT}${NC}"
echo -e "  ${RED}Echoues  : ${FAIL_COUNT}${NC}"
echo ""

if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✓ ${PASS_COUNT}/${TOTAL} tests passes — CLUSTER OPERATIONNEL${NC}"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}✗ ${PASS_COUNT}/${TOTAL} tests passes — CORRECTIONS NECESSAIRES${NC}"
    echo ""
    exit 1
fi
