#!/usr/bin/env bash
###############################################################################
# join-worker.sh
# Jointure d'un noeud worker au cluster Kubernetes
#
# A executer sur : kube-2, ingress, monitoring
# Prerequis : setup-node.sh deja execute sur ce noeud
#
# Usage :
#   sudo ./join-worker.sh <commande_kubeadm_join_complete>
#
# Exemple :
#   sudo ./join-worker.sh "kubeadm join 10.0.0.10:6443 --token abc123 --discovery-token-ca-cert-hash sha256:xyz789"
###############################################################################
set -euo pipefail

# --- Verification des privileges root ---
if [[ "$EUID" -ne 0 ]]; then
    echo "ERREUR : Ce script doit etre execute en tant que root (sudo)."
    exit 1
fi

# --- Verification de l'argument (commande de jointure) ---
if [[ $# -eq 0 ]]; then
    echo "ERREUR : Vous devez fournir la commande de jointure kubeadm en argument."
    echo ""
    echo "Usage : sudo $0 \"kubeadm join <IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>\""
    echo ""
    echo "Pour obtenir cette commande, executez sur kube-1 :"
    echo "  kubeadm token create --print-join-command"
    exit 1
fi

# Reconstruction de la commande de jointure a partir de tous les arguments
JOIN_COMMAND="$*"

echo "=== Jointure du noeud worker au cluster Kubernetes ==="
echo "Noeud : $(hostname)"
echo ""

###############################################################################
# Etape 1 : Verification que containerd et kubelet sont actifs
# Ces services doivent etre en cours d'execution avant la jointure.
###############################################################################
echo "[1/2] Verification des prerequis..."

if ! systemctl is-active --quiet containerd; then
    echo "ERREUR : containerd n'est pas actif. Executez d'abord setup-node.sh."
    exit 1
fi

if ! systemctl is-enabled --quiet kubelet; then
    echo "ERREUR : kubelet n'est pas active. Executez d'abord setup-node.sh."
    exit 1
fi

echo "  -> containerd et kubelet sont prets."

###############################################################################
# Etape 2 : Execution de la commande kubeadm join
# Le noeud rejoint le cluster en tant que worker.
###############################################################################
echo "[2/2] Execution de la commande de jointure..."
echo "  -> Commande : ${JOIN_COMMAND}"
echo ""

# Execution de la commande de jointure
eval "${JOIN_COMMAND}"

echo ""
echo "=== Noeud $(hostname) joint au cluster avec succes ==="
echo ""
echo "============================================================"
echo "  ETAPES SUIVANTES (a executer depuis kube-1)"
echo "============================================================"
echo ""
echo "1. Verifier que le noeud apparait dans le cluster :"
echo "   kubectl get nodes"
echo ""
echo "2. Appliquer les labels et taints avec label-nodes.sh :"
echo "   sudo ./label-nodes.sh"
echo ""
echo "3. Les labels suivants seront appliques selon le noeud :"
echo "   - kube-2     : node-role=worker, node-type=application"
echo "   - ingress    : node-role=ingress, node-type=ingress + taint NoSchedule"
echo "   - monitoring : node-role=monitoring, node-type=monitoring + taint NoSchedule"
echo ""
