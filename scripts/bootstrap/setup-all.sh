#!/usr/bin/env bash
###############################################################################
# setup-all.sh
# Script principal : guide pas-a-pas pour le bootstrap complet du cluster
# KubeQuest Kubernetes (4 noeuds AWS EC2 Amazon Linux)
#
# Architecture du cluster :
#   - kube-1     : control-plane + worker (applications)
#   - kube-2     : worker (applications)
#   - ingress    : worker dedie au controleur ingress-nginx
#   - monitoring : worker dedie a Prometheus / Loki
#
# Ce script N'EXECUTE PAS les commandes a distance. Il affiche les
# instructions a suivre manuellement via SSH sur chaque noeud.
###############################################################################
set -euo pipefail

# --- Couleurs pour l'affichage ---
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # Pas de couleur

# Chemin des scripts (relatif au repertoire de ce script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<BANNER

${BOLD}╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║           KubeQuest - Bootstrap du Cluster Kubernetes            ║
║                                                                  ║
║   4 noeuds AWS EC2 (Amazon Linux) - Kubernetes 1.29 + Calico    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝${NC}

${CYAN}Architecture du cluster :${NC}
  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐
  │   kube-1    │  │   kube-2    │  │   ingress   │  │  monitoring  │
  │ ctrl+worker │  │   worker    │  │   worker    │  │    worker    │
  │ applications│  │ applications│  │ ingress-nginx│  │ prometheus   │
  │             │  │             │  │             │  │ loki         │
  └─────────────┘  └─────────────┘  └─────────────┘  └──────────────┘

BANNER

###############################################################################
# PREREQUIS
###############################################################################
echo -e "${BOLD}${YELLOW}=== PREREQUIS ===${NC}"
echo ""
echo "Avant de commencer, assurez-vous que :"
echo "  1. Les 4 instances EC2 sont demarrees et accessibles via SSH"
echo "  2. Vous avez acces root (sudo) sur chaque instance"
echo "  3. Les groupes de securite autorisent le trafic entre les noeuds :"
echo "     - TCP 6443  (API server)"
echo "     - TCP 2379-2380 (etcd)"
echo "     - TCP 10250-10252 (kubelet, kube-scheduler, kube-controller)"
echo "     - TCP 30000-32767 (NodePort services)"
echo "     - UDP 8472  (VXLAN pour Calico)"
echo "     - TCP 179   (BGP pour Calico)"
echo "  4. Les scripts sont copies sur chaque noeud dans le meme repertoire"
echo ""
echo "  Scripts disponibles dans : ${SCRIPT_DIR}/"
echo ""

###############################################################################
# ETAPE 1 : Preparation de tous les noeuds
###############################################################################
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ETAPE 1 : Preparation de tous les noeuds (setup-node.sh)${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Executez setup-node.sh sur CHAQUE noeud (les 4 en parallele) :"
echo ""
for NODE in kube-1 kube-2 ingress monitoring; do
    echo -e "  ${CYAN}# SSH sur ${NODE} :${NC}"
    echo "  ssh ec2-user@${NODE}"
    echo "  sudo bash /chemin/vers/scripts/bootstrap/setup-node.sh"
    echo ""
done
echo -e "${YELLOW}  IMPORTANT : Attendez que setup-node.sh termine sur les 4 noeuds${NC}"
echo -e "${YELLOW}  avant de passer a l'etape suivante.${NC}"
echo ""

###############################################################################
# ETAPE 2 : Initialisation du control-plane (kube-1)
###############################################################################
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ETAPE 2 : Initialisation du control-plane (kube-1 uniquement)${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Connectez-vous a kube-1 et executez :"
echo ""
echo -e "  ${CYAN}# SSH sur kube-1 :${NC}"
echo "  ssh ec2-user@kube-1"
echo "  sudo bash /chemin/vers/scripts/bootstrap/init-control-plane.sh"
echo ""
echo "  Ce script va :"
echo "    - Initialiser le cluster (kubeadm init)"
echo "    - Configurer kubectl"
echo "    - Installer le CNI Calico"
echo "    - Retirer le taint control-plane (kube-1 = worker aussi)"
echo "    - Afficher la commande de jointure pour les workers"
echo ""
echo -e "${YELLOW}  IMPORTANT : Notez la commande 'kubeadm join ...' affichee a la fin.${NC}"
echo -e "${YELLOW}  Elle est aussi sauvegardee dans /root/kubeadm-join-command.txt sur kube-1.${NC}"
echo ""

###############################################################################
# ETAPE 3 : Jointure des noeuds worker
###############################################################################
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ETAPE 3 : Jointure des 3 noeuds worker${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Sur chaque noeud worker, executez join-worker.sh avec la commande"
echo "  de jointure obtenue a l'etape 2 :"
echo ""
for NODE in kube-2 ingress monitoring; do
    echo -e "  ${CYAN}# SSH sur ${NODE} :${NC}"
    echo "  ssh ec2-user@${NODE}"
    echo "  sudo bash /chemin/vers/scripts/bootstrap/join-worker.sh \"kubeadm join <IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>\""
    echo ""
done
echo -e "${YELLOW}  IMPORTANT : Attendez que les 3 noeuds aient rejoint le cluster.${NC}"
echo ""
echo "  Verification depuis kube-1 :"
echo "  kubectl get nodes"
echo "  (Tous les noeuds doivent apparaitre avec le statut 'Ready')"
echo ""

###############################################################################
# ETAPE 4 : Attribution des labels et taints
###############################################################################
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ETAPE 4 : Labels et taints (depuis kube-1)${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Depuis kube-1, executez le script de labellisation :"
echo ""
echo -e "  ${CYAN}# Sur kube-1 :${NC}"
echo "  sudo bash /chemin/vers/scripts/bootstrap/label-nodes.sh"
echo ""
echo "  Labels appliques :"
echo "    kube-2     -> node-role=worker,     node-type=application"
echo "    ingress    -> node-role=ingress,    node-type=ingress    + taint NoSchedule"
echo "    monitoring -> node-role=monitoring, node-type=monitoring + taint NoSchedule"
echo ""

###############################################################################
# ETAPE 5 : Verification finale
###############################################################################
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ETAPE 5 : Verification finale (depuis kube-1)${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Executez les commandes suivantes sur kube-1 pour verifier :"
echo ""
echo "  # Verifier l'etat des noeuds"
echo "  kubectl get nodes -o wide"
echo ""
echo "  # Verifier les labels"
echo "  kubectl get nodes --show-labels"
echo ""
echo "  # Verifier les taints"
echo "  kubectl describe nodes ingress | grep -A2 Taints"
echo "  kubectl describe nodes monitoring | grep -A2 Taints"
echo ""
echo "  # Verifier les pods systeme"
echo "  kubectl get pods -n kube-system"
echo "  kubectl get pods -n calico-system"
echo ""
echo "  # Resultat attendu : 4 noeuds Ready"
echo "  #   kube-1     Ready   control-plane,worker   ..."
echo "  #   kube-2     Ready   worker                 ..."
echo "  #   ingress    Ready   ingress                ..."
echo "  #   monitoring Ready   monitoring             ..."
echo ""

###############################################################################
# PROCHAINES ETAPES
###############################################################################
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  PROCHAINES ETAPES${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Une fois le cluster operationnel, vous pouvez deployer :"
echo ""
echo "  1. Ingress NGINX sur le noeud 'ingress' :"
echo "     -> Avec toleration pour node-type=ingress:NoSchedule"
echo "     -> Avec nodeSelector: node-type=ingress"
echo ""
echo "  2. Stack de monitoring sur le noeud 'monitoring' :"
echo "     -> Prometheus + Grafana + Loki"
echo "     -> Avec toleration pour node-type=monitoring:NoSchedule"
echo "     -> Avec nodeSelector: node-type=monitoring"
echo ""
echo "  3. Applications sur kube-1 et kube-2 :"
echo "     -> Avec nodeSelector: node-type=application"
echo ""
echo -e "${BOLD}Bon deploiement avec KubeQuest !${NC}"
echo ""
