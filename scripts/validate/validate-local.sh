#!/usr/bin/env bash
# ============================================================================
# validate-local.sh — Validation locale du projet KubeQuest (sans cluster)
# ============================================================================
set -uo pipefail

# --- Couleurs ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Repertoire racine du projet ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Compteurs ---
PASS_COUNT=0
FAIL_COUNT=0

pass() {
    echo -e "  ${GREEN}✓ PASS${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "  ${RED}✗ FAIL${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

skip() {
    echo -e "  ${YELLOW}⚠ SKIP${NC} $1"
}

section() {
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# SECTION 1 : Fichiers requis
# =============================================================================
section "Verification des fichiers requis"

REQUIRED_FILES=(
    # Bootstrap
    "scripts/bootstrap/setup-node.sh"
    "scripts/bootstrap/init-control-plane.sh"
    "scripts/bootstrap/join-worker.sh"
    "scripts/bootstrap/label-nodes.sh"
    "scripts/bootstrap/setup-all.sh"
    "scripts/bootstrap/build-app-image.sh"
    # Helm chart
    "charts/sample-app/Chart.yaml"
    "charts/sample-app/values.yaml"
    "charts/sample-app/templates/_helpers.tpl"
    "charts/sample-app/templates/deployment.yaml"
    "charts/sample-app/templates/service.yaml"
    "charts/sample-app/templates/ingress.yaml"
    "charts/sample-app/templates/hpa.yaml"
    "charts/sample-app/templates/pdb.yaml"
    "charts/sample-app/templates/configmap.yaml"
    "charts/sample-app/templates/secret.yaml"
    "charts/sample-app/templates/NOTES.txt"
    # Deploiement
    "deploy-all.sh"
    "infrastructure/deploy-infra.sh"
    # Infrastructure - ingress
    "infrastructure/base/ingress-nginx/install.sh"
    "infrastructure/base/ingress-nginx/values.yaml"
    # Infrastructure - monitoring
    "infrastructure/base/monitoring/install.sh"
    "infrastructure/base/monitoring/values.yaml"
    # Infrastructure - logging
    "infrastructure/base/logging/install.sh"
    "infrastructure/base/logging/loki-values.yaml"
    "infrastructure/base/logging/promtail-values.yaml"
    # Infrastructure - dashboard
    "infrastructure/base/dashboard/install.sh"
    "infrastructure/base/dashboard/values.yaml"
    "infrastructure/base/dashboard/admin-user.yaml"
    # Infrastructure - security
    "infrastructure/base/security/opa/install.sh"
    "infrastructure/base/security/opa/constraints/require-labels.yaml"
    "infrastructure/base/security/opa/constraints/require-resource-limits.yaml"
    "infrastructure/base/security/opa/constraints/disallow-privileged.yaml"
    "infrastructure/base/security/dex/install.sh"
    "infrastructure/base/security/dex/values.yaml"
    "infrastructure/base/security/dex/oauth2-proxy-values.yaml"
    "infrastructure/base/security/network-policies.yaml"
    # Namespaces
    "infrastructure/base/namespaces/namespaces.yaml"
    # Backup
    "scripts/backup/mysql-backup-cronjob.yaml"
    "scripts/backup/restore-mysql.sh"
    # Demo
    "scripts/demo/load-test.sh"
    "scripts/demo/broken-deploy.sh"
    "scripts/demo/cpu-stress.sh"
    "scripts/demo/memory-leak.sh"
    "scripts/demo/zero-downtime-test.sh"
    # Validation
    "scripts/validate/validate-cluster.sh"
    # GitOps
    "gitops/base/kustomization.yaml"
    "gitops/base/namespace.yaml"
    "gitops/overlays/production/kustomization.yaml"
    # Docs et app
    "docs/setup-guide.md"
    "app/Dockerfile"
    "app/docker-compose.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        pass "Fichier present : ${file}"
    else
        fail "Fichier manquant : ${file}"
    fi
done

# =============================================================================
# SECTION 2 : Syntaxe YAML
# =============================================================================
section "Validation syntaxe YAML"

yaml_errors=0
yaml_ok=0
while IFS= read -r yaml_file; do
    [[ -z "$yaml_file" ]] && continue
    relative_path="${yaml_file#${PROJECT_ROOT}/}"
    # Ignorer les fichiers Helm avec des templates Go {{ }}
    if grep -q '{{' "$yaml_file" 2>/dev/null; then
        skip "Template Helm ignore : ${relative_path}"
        continue
    fi
    if python3 -c "
import yaml, sys
try:
    with open(sys.argv[1], 'r') as f:
        list(yaml.safe_load_all(f))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
" "$yaml_file" 2>/dev/null; then
        pass "YAML valide : ${relative_path}"
        yaml_ok=$((yaml_ok + 1))
    else
        fail "YAML invalide : ${relative_path}"
        yaml_errors=$((yaml_errors + 1))
    fi
done < <(find "${PROJECT_ROOT}" -name '*.yaml' -o -name '*.yml' | grep -v '.git/' | grep -v 'vendor/' | grep -v 'node_modules/' | sort)

# =============================================================================
# SECTION 3 : Syntaxe Shell
# =============================================================================
section "Validation syntaxe Shell"

while IFS= read -r sh_file; do
    [[ -z "$sh_file" ]] && continue
    relative_path="${sh_file#${PROJECT_ROOT}/}"
    if bash -n "${sh_file}" 2>/dev/null; then
        pass "Shell valide : ${relative_path}"
    else
        fail "Shell invalide : ${relative_path}"
    fi
done < <(find "${PROJECT_ROOT}" -name '*.sh' | grep -v '.git/' | sort)

# =============================================================================
# SECTION 4 : Helm lint
# =============================================================================
section "Helm lint"

if command -v helm &>/dev/null; then
    output=$(helm lint "${PROJECT_ROOT}/charts/sample-app/" 2>&1)
    if echo "$output" | grep -q "0 chart(s) failed"; then
        pass "helm lint charts/sample-app/ reussi"
    elif echo "$output" | grep -qi "error"; then
        fail "helm lint charts/sample-app/ echoue"
    else
        pass "helm lint charts/sample-app/ reussi"
    fi
else
    skip "helm non disponible, lint ignore"
fi

# =============================================================================
# SECTION 5 : Dockerfile
# =============================================================================
section "Verification du Dockerfile"

DOCKERFILE="${PROJECT_ROOT}/app/Dockerfile"
if [[ -f "${DOCKERFILE}" ]]; then
    if grep -q '^FROM ' "${DOCKERFILE}"; then
        pass "Dockerfile contient FROM"
    else
        fail "Dockerfile ne contient pas FROM"
    fi
    if grep -q '^EXPOSE ' "${DOCKERFILE}"; then
        pass "Dockerfile contient EXPOSE"
    else
        fail "Dockerfile ne contient pas EXPOSE"
    fi
else
    fail "Dockerfile introuvable"
fi

# =============================================================================
# SECTION 6 : replicaCount >= 2
# =============================================================================
section "Verification values.yaml"

VALUES_FILE="${PROJECT_ROOT}/charts/sample-app/values.yaml"
if [[ -f "${VALUES_FILE}" ]]; then
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
# SECTION 7 : Resources limits/requests dans deployment.yaml
# =============================================================================
section "Verification ressources (limits/requests)"

DEPLOY_TEMPLATE="${PROJECT_ROOT}/charts/sample-app/templates/deployment.yaml"
if [[ -f "${DEPLOY_TEMPLATE}" ]]; then
    if grep -q 'resources' "${DEPLOY_TEMPLATE}" && grep -q 'limits' "${DEPLOY_TEMPLATE}" && grep -q 'requests' "${DEPLOY_TEMPLATE}"; then
        pass "resources.limits et resources.requests dans deployment.yaml"
    else
        fail "resources manquants dans deployment.yaml"
    fi
else
    fail "deployment.yaml introuvable"
fi

# =============================================================================
# SECTION 8 : Secrets (pas de password dans ConfigMap)
# =============================================================================
section "Verification securite (secrets vs configmap)"

SECRET_TEMPLATE="${PROJECT_ROOT}/charts/sample-app/templates/secret.yaml"
if [[ -f "${SECRET_TEMPLATE}" ]]; then
    pass "Template secret.yaml existe"
else
    fail "Template secret.yaml manquant"
fi

CONFIGMAP_TEMPLATE="${PROJECT_ROOT}/charts/sample-app/templates/configmap.yaml"
if [[ -f "${CONFIGMAP_TEMPLATE}" ]]; then
    if grep -iq 'password' "${CONFIGMAP_TEMPLATE}"; then
        fail "Mot de passe detecte dans configmap.yaml"
    else
        pass "Pas de mot de passe dans configmap.yaml"
    fi
fi

# =============================================================================
# SECTION 9 : podAntiAffinity
# =============================================================================
section "Verification podAntiAffinity"

if [[ -f "${DEPLOY_TEMPLATE}" ]]; then
    if grep -q 'podAntiAffinity' "${DEPLOY_TEMPLATE}"; then
        pass "podAntiAffinity present dans deployment.yaml"
    else
        fail "podAntiAffinity absent de deployment.yaml"
    fi
fi

# =============================================================================
# SECTION 10 : PDB
# =============================================================================
section "Verification PodDisruptionBudget"

if [[ -f "${PROJECT_ROOT}/charts/sample-app/templates/pdb.yaml" ]]; then
    pass "Template PDB (pdb.yaml) existe"
else
    fail "Template PDB (pdb.yaml) manquant"
fi

# =============================================================================
# SECTION 11 : HPA
# =============================================================================
section "Verification HPA"

if [[ -f "${PROJECT_ROOT}/charts/sample-app/templates/hpa.yaml" ]]; then
    pass "Template HPA (hpa.yaml) existe"
else
    fail "Template HPA (hpa.yaml) manquant"
fi

# =============================================================================
# SECTION 12 : NetworkPolicy
# =============================================================================
section "Verification NetworkPolicy"

if find "${PROJECT_ROOT}" -name '*network-polic*' -o -name '*networkpolic*' 2>/dev/null | grep -q .; then
    NP_COUNT=$(find "${PROJECT_ROOT}" -name '*network-polic*' -o -name '*networkpolic*' 2>/dev/null | wc -l)
    pass "Fichiers NetworkPolicy trouves : ${NP_COUNT}"
else
    fail "Aucun fichier NetworkPolicy trouve"
fi

# =============================================================================
# SECTION 13 : CronJob backup
# =============================================================================
section "Verification CronJob de sauvegarde"

BACKUP_FILE="${PROJECT_ROOT}/scripts/backup/mysql-backup-cronjob.yaml"
if [[ -f "${BACKUP_FILE}" ]]; then
    if grep -q 'CronJob' "${BACKUP_FILE}"; then
        pass "CronJob de sauvegarde present"
    else
        fail "CronJob invalide (kind CronJob manquant)"
    fi
else
    fail "mysql-backup-cronjob.yaml manquant"
fi

# =============================================================================
# SECTION 14 : Contraintes OPA (3 min)
# =============================================================================
section "Verification contraintes OPA"

OPA_DIR="${PROJECT_ROOT}/infrastructure/base/security/opa/constraints"
if [[ -d "${OPA_DIR}" ]]; then
    OPA_COUNT=$(find "${OPA_DIR}" -name '*.yaml' | wc -l)
    if [[ "${OPA_COUNT}" -ge 3 ]]; then
        pass "Contraintes OPA : ${OPA_COUNT} fichier(s) (>= 3 requis)"
    else
        fail "Contraintes OPA : ${OPA_COUNT} fichier(s) (3 requis)"
    fi
else
    fail "Repertoire contraintes OPA manquant"
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
    echo -e "  ${GREEN}${BOLD}✓ ${PASS_COUNT}/${TOTAL} tests passes — TOUT EST BON${NC}"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}✗ ${PASS_COUNT}/${TOTAL} tests passes — CORRECTIONS NECESSAIRES${NC}"
    echo ""
    exit 1
fi
