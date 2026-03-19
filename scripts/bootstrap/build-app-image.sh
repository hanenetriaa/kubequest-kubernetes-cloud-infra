#!/usr/bin/env bash
# =============================================================================
# Script de construction de l'image Docker pour l'application sample-app
# =============================================================================
set -euo pipefail

# Repertoire racine du projet (deux niveaux au-dessus de ce script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

IMAGE_NAME="sample-app"
IMAGE_TAG="latest"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
IMAGE_TAR="/tmp/${IMAGE_NAME}-${IMAGE_TAG}.tar"

echo "=== Construction de l'image Docker : ${IMAGE_REF} ==="
docker build -t "${IMAGE_REF}" "${PROJECT_ROOT}/app"

echo "=== Image construite avec succes ==="

# Si crictl est disponible, on est probablement sur un noeud Kubernetes
# On sauvegarde et importe l'image dans containerd
if command -v crictl &>/dev/null; then
    echo "=== crictl detecte : importation de l'image dans containerd ==="
    docker save "${IMAGE_REF}" -o "${IMAGE_TAR}"
    sudo ctr -n k8s.io images import "${IMAGE_TAR}"
    rm -f "${IMAGE_TAR}"
    echo "=== Image importee dans containerd sur ce noeud ==="
else
    echo "=== crictl non disponible sur ce noeud ==="
    echo "    Pour charger l'image sur les noeuds du cluster :"
    echo ""
    echo "    1. Sauvegarder l'image localement :"
    echo "       docker save ${IMAGE_REF} -o ${IMAGE_TAR}"
    echo ""
    echo "    2. Copier le fichier tar sur chaque noeud :"
    echo "       scp ${IMAGE_TAR} utilisateur@noeud:/tmp/"
    echo ""
    echo "    3. Importer l'image sur chaque noeud :"
    echo "       sudo ctr -n k8s.io images import ${IMAGE_TAR}"
    echo ""
    echo "    Alternativement, pousser l'image vers un registre :"
    echo "       docker tag ${IMAGE_REF} mon-registre.example.com/${IMAGE_REF}"
    echo "       docker push mon-registre.example.com/${IMAGE_REF}"
fi

echo "=== Termine ==="
