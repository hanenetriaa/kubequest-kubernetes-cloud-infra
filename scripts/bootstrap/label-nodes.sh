#!/usr/bin/env bash
###############################################################################
# label-nodes.sh
# Attribution des labels et taints sur les noeuds worker du cluster
#
# A executer UNIQUEMENT sur kube-1 (control-plane) apres que tous les
# noeuds aient rejoint le cluster.
#
# Labels et taints appliques :
#   kube-2     : node-role.kubernetes.io/worker=""     node-type=application
#   ingress    : node-role.kubernetes.io/ingress=""    node-type=ingress
#                + taint node-type=ingress:NoSchedule
#   monitoring : node-role.kubernetes.io/monitoring="" node-type=monitoring
#                + taint node-type=monitoring:NoSchedule
###############################################################################
set -euo pipefail

echo "=== Attribution des labels et taints sur les noeuds ==="

###############################################################################
# Verification que kubectl est disponible et que le cluster repond
###############################################################################
echo "[0/3] Verification de la connexion au cluster..."
if ! kubectl get nodes &> /dev/null; then
    echo "ERREUR : Impossible de se connecter au cluster Kubernetes."
    echo "Verifiez que le kubeconfig est configure correctement."
    exit 1
fi

# Affichage de l'etat actuel des noeuds
echo "  -> Noeuds actuels du cluster :"
kubectl get nodes -o wide
echo ""

###############################################################################
# Etape 1 : Labels pour kube-2 (noeud worker applicatif)
# Ce noeud hebergera les applications standard du cluster.
###############################################################################
echo "[1/3] Configuration du noeud kube-2 (worker applicatif)..."

if kubectl get node kube-2 &> /dev/null; then
    kubectl label nodes kube-2 node-role.kubernetes.io/worker="" --overwrite
    kubectl label nodes kube-2 node-type=application --overwrite
    echo "  -> kube-2 : labels appliques (worker, application)"
else
    echo "  ATTENTION : Le noeud 'kube-2' n'est pas trouve dans le cluster."
    echo "  Verifiez que le noeud a bien rejoint le cluster."
fi

###############################################################################
# Etape 2 : Labels et taint pour ingress (noeud dedie au controleur Ingress)
# Le taint NoSchedule empeche les pods non-tolerants d'etre planifies ici.
# Seul le controleur ingress-nginx (avec la toleration correspondante) sera
# deploye sur ce noeud.
###############################################################################
echo "[2/3] Configuration du noeud ingress (controleur Ingress NGINX)..."

if kubectl get node ingress &> /dev/null; then
    kubectl label nodes ingress node-role.kubernetes.io/ingress="" --overwrite
    kubectl label nodes ingress node-type=ingress --overwrite
    kubectl taint nodes ingress node-type=ingress:NoSchedule --overwrite
    echo "  -> ingress : labels appliques (ingress) + taint NoSchedule"
else
    echo "  ATTENTION : Le noeud 'ingress' n'est pas trouve dans le cluster."
    echo "  Verifiez que le noeud a bien rejoint le cluster."
fi

###############################################################################
# Etape 3 : Labels et taint pour monitoring (noeud dedie a la supervision)
# Le taint NoSchedule reserve ce noeud exclusivement pour Prometheus, Loki
# et les autres outils de monitoring.
###############################################################################
echo "[3/3] Configuration du noeud monitoring (Prometheus / Loki)..."

if kubectl get node monitoring &> /dev/null; then
    kubectl label nodes monitoring node-role.kubernetes.io/monitoring="" --overwrite
    kubectl label nodes monitoring node-type=monitoring --overwrite
    kubectl taint nodes monitoring node-type=monitoring:NoSchedule --overwrite
    echo "  -> monitoring : labels appliques (monitoring) + taint NoSchedule"
else
    echo "  ATTENTION : Le noeud 'monitoring' n'est pas trouve dans le cluster."
    echo "  Verifiez que le noeud a bien rejoint le cluster."
fi

###############################################################################
# Resume final
###############################################################################
echo ""
echo "=== Resume de la configuration des noeuds ==="
echo ""
echo "--- Noeuds et roles ---"
kubectl get nodes --show-labels | head -1
kubectl get nodes --show-labels | grep -v "^NAME" || true
echo ""
echo "--- Taints actifs ---"
for node in ingress monitoring; do
    if kubectl get node "$node" &> /dev/null; then
        echo "  ${node} :"
        kubectl describe node "$node" | grep -A5 "Taints:" | head -3
    fi
done
echo ""
echo "=== Labels et taints appliques avec succes ==="
