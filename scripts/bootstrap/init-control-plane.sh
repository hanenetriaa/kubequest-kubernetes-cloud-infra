#!/usr/bin/env bash
###############################################################################
# init-control-plane.sh
# Initialisation du plan de controle Kubernetes sur le noeud kube-1
#
# Actions :
#   - Initialisation du cluster avec kubeadm init (pod-network-cidr=10.244.0.0/16)
#   - Copie du kubeconfig pour l'utilisateur courant
#   - Installation du CNI Calico
#   - Suppression du taint control-plane pour permettre les workloads sur kube-1
#   - Ajout des labels sur kube-1 (control-plane + worker)
#
# A executer UNIQUEMENT sur kube-1 apres setup-node.sh
###############################################################################
set -euo pipefail

# --- Verification des privileges root ---
if [[ "$EUID" -ne 0 ]]; then
    echo "ERREUR : Ce script doit etre execute en tant que root (sudo)."
    exit 1
fi

echo "=== Initialisation du plan de controle Kubernetes (kube-1) ==="

###############################################################################
# Etape 1 : Initialisation du cluster avec kubeadm
# Le CIDR 10.244.0.0/16 est compatible avec Calico.
###############################################################################
echo "[1/5] Initialisation du cluster avec kubeadm..."
kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --kubernetes-version="stable-1.29" \
    | tee /root/kubeadm-init-output.txt

echo "  -> Cluster initialise. Sortie sauvegardee dans /root/kubeadm-init-output.txt"

###############################################################################
# Etape 2 : Configuration du kubeconfig
# Copie du fichier kubeconfig pour pouvoir utiliser kubectl sans sudo.
###############################################################################
echo "[2/5] Configuration du kubeconfig pour l'utilisateur courant..."

# Configuration pour root
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p "$HOME/.kube"
cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Si un utilisateur non-root est connecte (ex: ec2-user), configurer aussi pour lui
SUDO_USER_HOME=""
if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    SUDO_USER_HOME=$(eval echo "~${SUDO_USER}")
    mkdir -p "${SUDO_USER_HOME}/.kube"
    cp -f /etc/kubernetes/admin.conf "${SUDO_USER_HOME}/.kube/config"
    chown "$(id -u "$SUDO_USER"):$(id -g "$SUDO_USER")" "${SUDO_USER_HOME}/.kube/config"
    echo "  -> kubeconfig copie pour l'utilisateur ${SUDO_USER} (${SUDO_USER_HOME}/.kube/config)"
fi

echo "  -> kubeconfig configure pour root ($HOME/.kube/config)"

###############################################################################
# Etape 3 : Installation du CNI Calico
# Calico fournit le reseau pod-to-pod et les politiques reseau.
###############################################################################
echo "[3/5] Installation du CNI Calico..."

# Installation de l'operateur Tigera (Calico)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Telechargement et modification de la configuration Calico pour utiliser le bon CIDR
curl -s https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml \
    | sed 's|192.168.0.0/16|10.244.0.0/16|g' \
    | kubectl apply -f -

echo "  -> Calico en cours d'installation. Attente que les pods soient prets..."

# Attente que les pods Calico soient prets (timeout de 5 minutes)
echo "  -> Attente du demarrage des pods systeme (max 5 minutes)..."
kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=300s || {
    echo "ATTENTION : Certains pods systeme ne sont pas encore prets."
    echo "Verifiez avec : kubectl get pods -n kube-system"
}

echo "  -> CNI Calico installe."

###############################################################################
# Etape 4 : Suppression du taint control-plane
# Par defaut, le control-plane ne peut pas executer de workloads.
# On le retire pour que kube-1 serve aussi de worker.
###############################################################################
echo "[4/5] Suppression du taint control-plane sur kube-1..."
kubectl taint nodes "$(hostname)" node-role.kubernetes.io/control-plane:NoSchedule- || {
    echo "  -> Taint deja absent ou noeud non trouve, continuation..."
}
echo "  -> kube-1 peut maintenant executer des workloads."

###############################################################################
# Etape 5 : Ajout des labels sur kube-1
# kube-1 a le double role : control-plane et worker
###############################################################################
echo "[5/5] Ajout des labels sur kube-1..."
kubectl label nodes "$(hostname)" node-role.kubernetes.io/worker="" --overwrite
kubectl label nodes "$(hostname)" node-type=application --overwrite
echo "  -> Labels appliques sur kube-1 : control-plane + worker"

###############################################################################
# Extraction de la commande de jointure pour les autres noeuds
###############################################################################
echo ""
echo "============================================================"
echo "  COMMANDE DE JOINTURE POUR LES NOEUDS WORKER"
echo "============================================================"
echo ""
echo "Executez la commande suivante sur kube-2, ingress et monitoring :"
echo ""
kubeadm token create --print-join-command
echo ""
echo "============================================================"
echo ""

# Sauvegarder la commande de jointure dans un fichier pour reference
kubeadm token create --print-join-command > /root/kubeadm-join-command.txt
echo "Commande de jointure sauvegardee dans /root/kubeadm-join-command.txt"

echo ""
echo "=== Initialisation du plan de controle terminee ==="
echo "Prochaine etape : executer join-worker.sh sur les 3 autres noeuds."
