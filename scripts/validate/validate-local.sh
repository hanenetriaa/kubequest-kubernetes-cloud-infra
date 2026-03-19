#!/usr/bin/env bash
# ============================================================================
# validate-local.sh — Validation locale du projet KubeQuest (sans cluster)
# ============================================================================
# Ce script effectue des verifications locales (sans cluster Kubernetes)
# pour s'assurer que tous les fichiers du projet sont corrects et complets.
#
# Verifications effectuees :
#   - Structure du projet (fichiers requis)
#   - Syntaxe YAML de tous les fichiers .yaml
#   - Syntaxe Bash de tous les scripts .sh
#   - Lint du chart Helm (si helm disponible)
#   - Dockerfile (presence de FROM et EXPOSE)
#   - replicaCount >= 2 dans values.yaml
#   - Limites de ressources dans les templates Helm
#   - Utilisation correcte des Secrets (pas de mots de passe dans ConfigMap)
#   - podAntiAffinity dans deployment.yaml
#   - PodDisruptionBudget present
#   - HPA present
#   - NetworkPolicy present
#   - CronJob de backup present
#   - Contraintes OPA (3 fichiers minimum)
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

# --- Repertoire racine du projet ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Compteurs de resultats ---
PASS_COUNT=0
FAIL_COUNT=0

# =============================================================================
# Fonctions utilitaires
# =============================================================================

# Affiche un resultat PASS (reussite)
pass() {
    local msg="$1"
    echo -e "  ${GREEN}✓ PASS${NC} ${msg}"
    ((PASS_COUNT++))
}

# Affiche un resultat FAIL (echec) — n'arrete pas le script
fail() {
    local msg="$1"
    echo -e "  ${RED}✗ FAIL${NC} ${msg}"
    ((FAIL_COUNT++))
}

# Affiche un titre de section
section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $title${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# SECTION 1 : Verification de l'existence des fichiers requis
# =============================================================================
section "Verification des fichiers requis"

# Liste complete de tous les fichiers obligatoires du projet
REQUIRED_FILES=(
    # Scripts de bootstrap
    "scripts/bootstrap/setup-node.sh"
    "scripts/bootstrap/init-control-plane.sh"
    "scripts/bootstrap/join-worker.sh"
    "scripts/bootstrap/label-nodes.sh"
    "scripts/bootstrap/setup-all.sh"
    "scripts/bootstrap/build-app-image.sh"
    # Chart Helm — fichiers principaux
    "charts/sample-app/Chart.yaml"
    "charts/sample-app/values.yaml"
    # Chart Helm — tous les templates
    "charts/sample-app/templates/deployment.yaml"
    "charts/sample-app/templates/service.yaml"
    "charts/sample-app/templates/ingress.yaml"
    "charts/sample-app/templates/hpa.yaml"
    "charts/sample-app/templates/pdb.yaml"
    "charts/sample-app/templates/configmap.yaml"
    "charts/sample-app/templates/secret.yaml"
    "charts/sample-app/templates/networkpolicy.yaml"
    "charts/sample-app/templates/mysql-deployment.yaml"
    "charts/sample-app/templates/mysql-service.yaml"
    "charts/sample-app/templates/mysql-pvc.yaml"
    "charts/sample-app/templates/backup-cronjob.yaml"
    # Script de deploiement principal
    "deploy-all.sh"
    # Infrastructure
    "infrastructure/deploy-infra.sh"
    "infrastructure/ingress-nginx/install.sh"
    "infrastructure/ingress-nginx/values.yaml"
    "infrastructure/monitoring/install.sh"
    "infrastructure/monitoring/values.yaml"
    "infrastructure/logging/install.sh"
    "infrastructure/logging/values.yaml"
    "infrastructure/dashboard/install.sh"
    "infrastructure/dashboard/values.yaml"
    # Scripts de demo
    "scripts/demo/demo-scaling.sh"
    "scripts/demo/demo-rollback.sh"
    "scripts/demo/demo-monitoring.sh"
    "scripts/demo/demo-network-policy.sh"
    "scripts/demo/demo-backup-restore.sh"
    "scripts/demo/demo-opa.sh"
    # Documentation et application
    "docs/setup-guide.md"
    "app/Dockerfile"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        pass "Fichier present : ${file}"
    else
        fail "Fichier manquant : ${file}"
    fi
done

# =============================================================================
# SECTION 2 : Validation de la syntaxe YAML
# =============================================================================
section "Validation syntaxe YAML"

# Recherche et verification de tous les fichiers YAML du projet
while IFS= read -r -d '' yaml_file; do
    relative_path="${yaml_file#${PROJECT_ROOT}/}"
    if python3 -c "
import yaml, sys
try:
    with open('${yaml_file}', 'r') as f:
        list(yaml.safe_load_all(f))
    sys.exit(0)
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
        pass "YAML valide : ${relative_path}"
    else
        fail "YAML invalide : ${relative_path}"
    fi
done < <(find "${PROJECT_ROOT}" -name '*.yaml' -o -name '*.yml' | grep -v '.git/' | grep -v 'vendor/' | sort | tr '\n' '\0')

# =============================================================================
# SECTION 3 : Validation de la syntaxe Shell
# =============================================================================
section "Validation syntaxe Shell"

# Verification de la syntaxe de tous les scripts bash avec bash -n
while IFS= read -r -d '' sh_file; do
    relative_path="${sh_file#${PROJECT_ROOT}/}"
    if bash -n "${sh_file}" 2>/dev/null; then
        pass "Shell valide : ${relative_path}"
    else
        fail "Shell invalide : ${relative_path}"
    fi
done < <(find "${PROJECT_ROOT}" -name '*.sh' -print0 | sort -z)

# =============================================================================
# SECTION 4 : Helm lint (si helm est disponible)
# =============================================================================
section "Helm lint"

if command -v helm &>/dev/null; then
    if helm lint "${PROJECT_ROOT}/charts/sample-app/" &>/dev/null; then
        pass "helm lint charts/sample-app/ reussi"
    else
        fail "helm lint charts/sample-app/ echoue"
    fi
else
    echo -e "  ${YELLOW}⚠ SKIP${NC}: helm non disponible, lint ignore"
fi

# =============================================================================
# SECTION 5 : Verification du Dockerfile
# =============================================================================
section "Verification du Dockerfile"

DOCKERFILE="${PROJECT_ROOT}/app/Dockerfile"
if [[ -f "${DOCKERFILE}" ]]; then
    # Verification de la presence de l'instruction FROM
    if grep -q '^FROM ' "${DOCKERFILE}"; then
        pass "Dockerfile contient FROM"
    else
        fail "Dockerfile ne contient pas FROM"
    fi

    # Verification de la presence de l'instruction EXPOSE
    if grep -q '^EXPOSE ' "${DOCKERFILE}"; then
        pass "Dockerfile contient EXPOSE"
    else
        fail "Dockerfile ne contient pas EXPOSE"
    fi
else
    fail "Dockerfile introuvable dans app/"
fi

# =============================================================================
# SECTION 6 : Verification de replicaCount dans values.yaml
# =============================================================================
section "Verification values.yaml (replicaCount)"

VALUES_FILE="${PROJECT_ROOT}/charts/sample-app/values.yaml"
if [[ -f "${VALUES_FILE}" ]]; then
    # Extraction de replicaCount avec python3
    REPLICA_COUNT=$(python3 -c "
import yaml
with open('${VALUES_FILE}', 'r') as f:
    data = yaml.safe_load(f)
print(data.get('replicaCount', 0))
" 2>/dev/null || echo "0")

    if [[ "${REPLICA_COUNT}" -ge 2 ]] 2>/dev/null; then
        pass "replicaCount = ${REPLICA_COUNT} (>= 2)"
    else
        fail "replicaCount = ${REPLICA_COUNT} (doit etre >= 2)"
    fi
else
    fail "values.yaml introuvable"
fi

# =============================================================================
# SECTION 7 : Verification des ressources (limits/requests) dans les templates
# =============================================================================
section "Verification des ressources (limits/requests) dans les templates"

TEMPLATES_DIR="${PROJECT_ROOT}/charts/sample-app/templates"
if [[ -d "${TEMPLATES_DIR}" ]]; then
    # Verification dans chaque template de deploiement
    for tmpl in "${TEMPLATES_DIR}/deployment.yaml" "${TEMPLATES_DIR}/mysql-deployment.yaml"; do
        if [[ -f "${tmpl}" ]]; then
            basename_tmpl=$(basename "${tmpl}")
            if grep -q 'resources' "${tmpl}" && grep -q 'limits' "${tmpl}" && grep -q 'requests' "${tmpl}"; then
                pass "resources.limits et resources.requests dans ${basename_tmpl}"
            else
                fail "resources.limits ou resources.requests manquant dans ${basename_tmpl}"
            fi
        fi
    done
else
    fail "Repertoire templates/ introuvable"
fi

# =============================================================================
# SECTION 8 : Verification de securite — secrets et configmap
# =============================================================================
section "Verification de securite (secrets/configmap)"

# Le template secret doit exister
SECRET_TEMPLATE="${TEMPLATES_DIR}/secret.yaml"
if [[ -f "${SECRET_TEMPLATE}" ]]; then
    pass "Template secret.yaml existe (mots de passe securises)"
else
    fail "Template secret.yaml manquant (risque de mots de passe dans configmap)"
fi

# Verification qu'aucun mot de passe n'est dans le configmap
CONFIGMAP_TEMPLATE="${TEMPLATES_DIR}/configmap.yaml"
if [[ -f "${CONFIGMAP_TEMPLATE}" ]]; then
    if grep -iq 'password' "${CONFIGMAP_TEMPLATE}"; then
        fail "Mot de passe detecte dans configmap.yaml (utiliser secret a la place)"
    else
        pass "Pas de mot de passe dans configmap.yaml"
    fi
fi

# =============================================================================
# SECTION 9 : Verification de podAntiAffinity dans deployment.yaml
# =============================================================================
section "Verification podAntiAffinity"

DEPLOY_TEMPLATE="${TEMPLATES_DIR}/deployment.yaml"
if [[ -f "${DEPLOY_TEMPLATE}" ]]; then
    if grep -q 'podAntiAffinity' "${DEPLOY_TEMPLATE}"; then
        pass "podAntiAffinity present dans deployment.yaml"
    else
        fail "podAntiAffinity absent de deployment.yaml"
    fi
else
    fail "deployment.yaml introuvable"
fi

# =============================================================================
# SECTION 10 : Verification du PodDisruptionBudget
# =============================================================================
section "Verification PodDisruptionBudget (PDB)"

PDB_TEMPLATE="${TEMPLATES_DIR}/pdb.yaml"
if [[ -f "${PDB_TEMPLATE}" ]]; then
    pass "Template PDB (pdb.yaml) existe"
else
    fail "Template PDB (pdb.yaml) manquant"
fi

# =============================================================================
# SECTION 11 : Verification du HorizontalPodAutoscaler
# =============================================================================
section "Verification HPA (HorizontalPodAutoscaler)"

HPA_TEMPLATE="${TEMPLATES_DIR}/hpa.yaml"
if [[ -f "${HPA_TEMPLATE}" ]]; then
    pass "Template HPA (hpa.yaml) existe"
else
    fail "Template HPA (hpa.yaml) manquant"
fi

# =============================================================================
# SECTION 12 : Verification des NetworkPolicies
# =============================================================================
section "Verification NetworkPolicy"

# Recherche de fichiers NetworkPolicy dans tout le projet
if find "${PROJECT_ROOT}" -name '*networkpolicy*' -o -name '*network-policy*' -o -name '*network-policies*' | grep -q .; then
    pass "Fichiers NetworkPolicy trouves"
else
    fail "Aucun fichier NetworkPolicy trouve"
fi

# =============================================================================
# SECTION 13 : Verification du CronJob de sauvegarde
# =============================================================================
section "Verification CronJob de sauvegarde"

BACKUP_CRONJOB="${TEMPLATES_DIR}/backup-cronjob.yaml"
if [[ -f "${BACKUP_CRONJOB}" ]]; then
    if grep -q 'CronJob' "${BACKUP_CRONJOB}"; then
        pass "CronJob de sauvegarde existe et contient le kind CronJob"
    else
        fail "backup-cronjob.yaml ne contient pas le kind CronJob"
    fi
else
    fail "backup-cronjob.yaml introuvable"
fi

# =============================================================================
# SECTION 14 : Verification des contraintes OPA (3 fichiers minimum)
# =============================================================================
section "Verification contraintes OPA"

# Recherche de tous les fichiers de contraintes OPA dans le projet
OPA_COUNT=$(find "${PROJECT_ROOT}" -path '*/opa/*' -name '*.yaml' -o -path '*/security/*' -name '*constraint*' | wc -l)
if [[ "${OPA_COUNT}" -ge 3 ]]; then
    pass "Contraintes OPA trouvees : ${OPA_COUNT} fichier(s) (>= 3 requis)"
else
    fail "Contraintes OPA insuffisantes : ${OPA_COUNT} fichier(s) (3 requis)"
fi

# =============================================================================
# RESUME FINAL
# =============================================================================
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  RAPPORT FINAL — Validation locale${NC}"
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
