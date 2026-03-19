#!/usr/bin/env bash
###############################################################################
# setup-node.sh
# Script de preparation de noeud Kubernetes (Amazon Linux / yum)
# A executer sur TOUS les 4 noeuds : kube-1, kube-2, ingress, monitoring
#
# Actions :
#   - Desactivation du swap
#   - Chargement des modules noyau (overlay, br_netfilter)
#   - Configuration des parametres sysctl pour le reseau K8s
#   - Installation de containerd
#   - Installation de kubeadm, kubelet, kubectl (v1.29)
###############################################################################
set -euo pipefail

# --- Verification des privileges root ---
if [[ "$EUID" -ne 0 ]]; then
    echo "ERREUR : Ce script doit etre execute en tant que root (sudo)."
    exit 1
fi

KUBE_VERSION="1.29"
echo "=== Preparation du noeud Kubernetes (v${KUBE_VERSION}) ==="

###############################################################################
# Etape 1 : Desactivation du swap
# Le swap doit etre desactive pour que kubelet fonctionne correctement.
###############################################################################
echo "[1/6] Desactivation du swap..."
swapoff -a
# Commenter toutes les lignes swap dans /etc/fstab pour persister apres reboot
sed -i '/ swap / s/^/#/' /etc/fstab
echo "  -> Swap desactive."

###############################################################################
# Etape 2 : Chargement des modules noyau necessaires
# overlay   : requis par containerd pour le systeme de fichiers
# br_netfilter : requis pour que iptables voie le trafic bridge
###############################################################################
echo "[2/6] Chargement des modules noyau (overlay, br_netfilter)..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
echo "  -> Modules noyau charges."

###############################################################################
# Etape 3 : Configuration des parametres sysctl
# Ces parametres permettent le routage reseau necessaire pour Kubernetes.
###############################################################################
echo "[3/6] Configuration des parametres sysctl..."
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system > /dev/null 2>&1
echo "  -> Parametres sysctl appliques."

###############################################################################
# Etape 4 : Installation de containerd
# containerd est le runtime de conteneurs utilise par Kubernetes.
###############################################################################
echo "[4/6] Installation de containerd..."

# Installation des dependances et de containerd
yum install -y yum-utils device-mapper-persistent-data lvm2 > /dev/null 2>&1
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
yum install -y containerd.io > /dev/null 2>&1

# Generation de la configuration par defaut de containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Activation du cgroup systemd (necessaire pour Kubernetes)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Demarrage et activation de containerd
systemctl daemon-reload
systemctl enable --now containerd
echo "  -> containerd installe et demarre."

###############################################################################
# Etape 5 : Installation de kubeadm, kubelet, kubectl
# Ajout du depot Kubernetes officiel et installation des paquets.
###############################################################################
echo "[5/6] Installation de kubeadm, kubelet, kubectl (v${KUBE_VERSION})..."

# Ajout du depot Kubernetes (format yum pour Amazon Linux)
cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Installation des paquets Kubernetes
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes > /dev/null 2>&1

# Activation de kubelet (il restera en attente jusqu'a kubeadm init/join)
systemctl enable --now kubelet
echo "  -> kubeadm, kubelet, kubectl installes."

###############################################################################
# Etape 6 : Desactivation de SELinux (si present)
# SELinux peut bloquer certaines operations de Kubernetes.
###############################################################################
echo "[6/6] Verification de SELinux..."
if command -v getenforce &> /dev/null; then
    setenforce 0 || true
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
    echo "  -> SELinux passe en mode permissif."
else
    echo "  -> SELinux non detecte, aucune action requise."
fi

###############################################################################
# Fin
###############################################################################
echo ""
echo "=== Preparation du noeud terminee avec succes ==="
echo "Le noeud est pret pour 'kubeadm init' (control-plane) ou 'kubeadm join' (worker)."
