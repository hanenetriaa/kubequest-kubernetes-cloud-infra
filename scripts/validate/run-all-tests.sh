#!/usr/bin/env bash
# ============================================================================
# run-all-tests.sh — Script principal d'execution de toutes les validations
# ============================================================================
# Ce script orchestre l'execution des validations locales et cluster
# pour le projet KubeQuest.
#
# Utilisation :
#   ./run-all-tests.sh              # Validation locale uniquement
#   ./run-all-tests.sh --cluster    # Validation locale + cluster
#
# La validation locale est toujours executee.
# La validation cluster necessite un cluster Kubernetes actif.
# ============================================================================
set -uo pipefail

# --- Couleurs pour la sortie formatee ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # Pas de couleur

# --- Repertoire courant du script ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Analyse des arguments ---
RUN_CLUSTER=false
for arg in "$@"; do
    case "${arg}" in
        --cluster)
            RUN_CLUSTER=true
            ;;
        --help|-h)
            echo "Utilisation : $0 [--cluster]"
            echo ""
            echo "Options :"
            echo "  --cluster    Execute aussi la validation sur cluster (necessite kubectl)"
            echo "  --help, -h   Affiche cette aide"
            exit 0
            ;;
        *)
            echo -e "${RED}Option inconnue : ${arg}${NC}"
            echo "Utilisation : $0 [--cluster]"
            exit 1
            ;;
    esac
done

# --- Variables pour le suivi des resultats ---
LOCAL_EXIT=0
CLUSTER_EXIT=0

# =============================================================================
# Execution de la validation locale (toujours executee)
# =============================================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          VALIDATION LOCALE — KubeQuest                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Execution du script de validation locale
if bash "${SCRIPT_DIR}/validate-local.sh"; then
    LOCAL_EXIT=0
else
    LOCAL_EXIT=1
fi

# =============================================================================
# Execution de la validation cluster (seulement si --cluster est passe)
# =============================================================================
if [[ "${RUN_CLUSTER}" == true ]]; then
    echo ""
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          VALIDATION CLUSTER — KubeQuest                    ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Execution du script de validation cluster
    if bash "${SCRIPT_DIR}/validate-cluster.sh"; then
        CLUSTER_EXIT=0
    else
        CLUSTER_EXIT=1
    fi
else
    echo ""
    echo -e "${YELLOW}${BOLD}Note : Validation cluster ignoree (utilisez --cluster pour l'activer).${NC}"
fi

# =============================================================================
# Resume combine final
# =============================================================================
echo ""
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║               RESUME COMBINE — KubeQuest                   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Resultat de la validation locale
if [[ "${LOCAL_EXIT}" -eq 0 ]]; then
    echo -e "  ${GREEN}✓${NC} Validation locale   : ${GREEN}${BOLD}REUSSITE${NC}"
else
    echo -e "  ${RED}✗${NC} Validation locale   : ${RED}${BOLD}ECHEC${NC}"
fi

# Resultat de la validation cluster (si executee)
if [[ "${RUN_CLUSTER}" == true ]]; then
    if [[ "${CLUSTER_EXIT}" -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Validation cluster  : ${GREEN}${BOLD}REUSSITE${NC}"
    else
        echo -e "  ${RED}✗${NC} Validation cluster  : ${RED}${BOLD}ECHEC${NC}"
    fi
else
    echo -e "  ${YELLOW}-${NC} Validation cluster  : ${YELLOW}NON EXECUTEE${NC}"
fi

# Resultat global
echo ""
GLOBAL_EXIT=$((LOCAL_EXIT + CLUSTER_EXIT))
if [[ "${GLOBAL_EXIT}" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}RESULTAT GLOBAL : TOUTES LES VALIDATIONS SONT PASSEES${NC}"
else
    echo -e "  ${RED}${BOLD}RESULTAT GLOBAL : DES VALIDATIONS ONT ECHOUE${NC}"
fi

echo ""
exit "${GLOBAL_EXIT}"
