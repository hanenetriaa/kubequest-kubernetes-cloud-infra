# Guide d'installation KubeQuest

Guide complet pour deployer la plateforme KubeQuest sur un cluster Kubernetes de 4 noeuds AWS EC2.

---

## Table des matieres

1. [Prerequis](#prerequis)
2. [Etape 1 : Recuperer la cle SSH depuis AWS SSM](#etape-1--recuperer-la-cle-ssh-depuis-aws-ssm)
3. [Etape 2 : Demarrer les instances EC2](#etape-2--demarrer-les-instances-ec2)
4. [Etape 3 : Bootstrap du cluster](#etape-3--bootstrap-du-cluster)
5. [Etape 4 : Deployer l'infrastructure](#etape-4--deployer-linfrastructure)
6. [Etape 5 : Deployer l'application](#etape-5--deployer-lapplication)
7. [Etape 6 : Verifier le bon fonctionnement](#etape-6--verifier-le-bon-fonctionnement)
8. [Etape 7 : Commandes de demonstration](#etape-7--commandes-de-demonstration)
9. [Depannage](#depannage)
10. [Architecture](#architecture)

---

## Prerequis

Avant de commencer, assurez-vous d'avoir :

- **AWS CLI** configure avec les droits suffisants (EC2, SSM)
- **kubectl** installe (v1.28+)
- **helm** installe (v3.12+)
- **ssh** avec acces aux instances EC2
- Un compte AWS avec acces au Parameter Store SSM
- Les 4 instances EC2 deja provisionnees (via Terraform ou manuellement)

### Versions testees

| Outil      | Version minimum |
|------------|----------------|
| Kubernetes | 1.28           |
| Helm       | 3.12           |
| kubectl    | 1.28           |
| AWS CLI    | 2.x            |

---

## Etape 1 : Recuperer la cle SSH depuis AWS SSM

La cle SSH privee pour acceder aux instances EC2 est stockee dans AWS Systems Manager Parameter Store.

```bash
# Recuperer la cle SSH depuis SSM
aws ssm get-parameter \
  --name "/kubequest/ssh-key" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text > ~/.ssh/kubequest-key.pem

# Securiser les permissions
chmod 600 ~/.ssh/kubequest-key.pem

# Verifier l'acces a une instance
ssh -i ~/.ssh/kubequest-key.pem ubuntu@<MASTER_IP> "hostname"
```

---

## Etape 2 : Demarrer les instances EC2

Si les instances sont arretees, les demarrer via AWS CLI :

```bash
# Lister les instances KubeQuest
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=KubeQuest" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,Tags[?Key=='Name'].Value|[0]]" \
  --output table

# Demarrer toutes les instances
aws ec2 start-instances \
  --instance-ids i-master i-worker1 i-worker2 i-worker3

# Attendre que les instances soient en cours d'execution
aws ec2 wait instance-running \
  --instance-ids i-master i-worker1 i-worker2 i-worker3
```

> **Note** : Remplacez les IDs d'instance par les valeurs reelles.

---

## Etape 3 : Bootstrap du cluster

Executer les scripts de bootstrap dans l'ordre sur chaque noeud :

```bash
# Sur TOUS les noeuds (master + workers) :
# 1. Installation des paquets de base
ssh -i ~/.ssh/kubequest-key.pem ubuntu@<NODE_IP> \
  "sudo bash /home/ubuntu/scripts/01-install-base.sh"

# 2. Installation de containerd
ssh -i ~/.ssh/kubequest-key.pem ubuntu@<NODE_IP> \
  "sudo bash /home/ubuntu/scripts/02-install-containerd.sh"

# 3. Installation de kubeadm, kubelet, kubectl
ssh -i ~/.ssh/kubequest-key.pem ubuntu@<NODE_IP> \
  "sudo bash /home/ubuntu/scripts/03-install-kube.sh"

# Sur le MASTER uniquement :
# 4. Initialisation du cluster
ssh -i ~/.ssh/kubequest-key.pem ubuntu@<MASTER_IP> \
  "sudo bash /home/ubuntu/scripts/04-init-cluster.sh"

# Recuperer la commande join
JOIN_CMD=$(ssh -i ~/.ssh/kubequest-key.pem ubuntu@<MASTER_IP> \
  "kubeadm token create --print-join-command")

# Sur chaque WORKER :
ssh -i ~/.ssh/kubequest-key.pem ubuntu@<WORKER_IP> \
  "sudo ${JOIN_CMD}"
```

### Verifier le cluster

```bash
# Copier le kubeconfig depuis le master
scp -i ~/.ssh/kubequest-key.pem \
  ubuntu@<MASTER_IP>:/home/ubuntu/.kube/config \
  ~/.kube/config-kubequest

export KUBECONFIG=~/.kube/config-kubequest

# Verifier les noeuds
kubectl get nodes -o wide
```

Tous les noeuds doivent etre en status **Ready**.

---

## Etape 4 : Deployer l'infrastructure

L'infrastructure inclut le monitoring (Prometheus, Grafana), l'Ingress Controller et le stockage.

```bash
# Deployer toute l'infrastructure
cd /home/parisi/T-PRO
bash infrastructure/deploy-infra.sh
```

Ce script deploie :
- **Prometheus** et **Grafana** dans le namespace `monitoring`
- **NGINX Ingress Controller** dans le namespace `ingress-nginx`
- Les ConfigMaps et Secrets necessaires

### Verifier l'infrastructure

```bash
kubectl get pods -n monitoring
kubectl get pods -n ingress-nginx
```

---

## Etape 5 : Deployer l'application

### Option A : Script automatique (recommande)

```bash
# Deploiement complet en une seule commande
bash deploy-all.sh

# Ou en mode simulation d'abord
bash deploy-all.sh --dry-run
```

### Option B : Deploiement manuel

```bash
# Creer le namespace
kubectl apply -f gitops/base/namespace.yaml

# Deployer via Helm
helm upgrade --install sample-app \
  charts/sample-app \
  -n sample-app \
  -f charts/sample-app/values.yaml \
  --create-namespace \
  --wait

# Configurer les backups
kubectl apply -f scripts/backup/mysql-backup-cronjob.yaml
```

---

## Etape 6 : Verifier le bon fonctionnement

```bash
# Verifier les pods de l'application
kubectl get pods -n sample-app -o wide

# Verifier les services
kubectl get svc -n sample-app

# Tester l'endpoint de sante
curl http://<MASTER_IP>:<NODEPORT>/health

# Verifier le HPA
kubectl get hpa -n sample-app

# Verifier le CronJob de backup
kubectl get cronjobs -n sample-app

# Verifier les metriques Prometheus
curl http://<MASTER_IP>:<PROMETHEUS_PORT>/api/v1/targets
```

---

## Etape 7 : Commandes de demonstration

### Test de charge
```bash
# Envoie 1000 requetes avec 10 workers concurrents
bash scripts/demo/load-test.sh
```

### Deploiement casse + rollback
```bash
# Deploie une image cassee puis effectue un rollback
bash scripts/demo/broken-deploy.sh
```

### Stress CPU (declenchement HPA)
```bash
# Cree un pod gourmand en CPU, observe le scaling automatique
bash scripts/demo/cpu-stress.sh
```

### Fuite memoire (OOM Kill)
```bash
# Simule une fuite memoire, observe les OOM kills et redemarrages
bash scripts/demo/memory-leak.sh
```

### Test zero-downtime
```bash
# Verifie qu'aucune requete n'est perdue pendant un rolling update
bash scripts/demo/zero-downtime-test.sh
```

### Restauration de backup
```bash
# Restaurer depuis un fichier de backup
bash scripts/backup/restore-mysql.sh <fichier_backup.sql>
```

---

## Depannage

### Le noeud est en status "NotReady"

```bash
# Verifier le status du kubelet
ssh ubuntu@<NODE_IP> "sudo systemctl status kubelet"
ssh ubuntu@<NODE_IP> "sudo journalctl -u kubelet --tail=50"

# Verifier le CNI (Calico/Flannel)
kubectl get pods -n kube-system | grep -E "calico|flannel"
```

### Les pods sont en "ImagePullBackOff"

```bash
# Verifier les evenements du pod
kubectl describe pod <POD_NAME> -n <NAMESPACE>

# Verifier la disponibilite de l'image
# Si registre prive, verifier le secret imagePullSecrets
kubectl get secret -n <NAMESPACE>
```

### Le HPA ne scale pas

```bash
# Verifier que metrics-server fonctionne
kubectl get pods -n kube-system | grep metrics-server
kubectl top nodes
kubectl top pods -n sample-app

# Verifier la configuration du HPA
kubectl describe hpa -n sample-app
```

### Les backups echouent

```bash
# Verifier les logs du dernier job
kubectl get jobs -n sample-app
kubectl logs job/<JOB_NAME> -n sample-app

# Verifier le PVC
kubectl get pvc -n sample-app
kubectl describe pvc mysql-backup-pvc -n sample-app
```

### Impossible de se connecter au cluster

```bash
# Verifier le kubeconfig
kubectl config current-context
kubectl cluster-info

# Si le certificat a expire, regenerer sur le master
ssh ubuntu@<MASTER_IP> "sudo kubeadm certs check-expiration"
```

### Grafana ne s'affiche pas

```bash
# Verifier le pod Grafana
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana

# Identifiants par defaut : admin / admin (a changer au premier login)
```

---

## Architecture

```
+------------------------------------------------------------------+
|                        AWS VPC - KubeQuest                        |
+------------------------------------------------------------------+
|                                                                    |
|  +-----------------------------+  +-----------------------------+  |
|  |     MASTER (control-plane)  |  |        WORKER 1             |  |
|  |     k8s-master              |  |        k8s-worker-1         |  |
|  |-----------------------------|  |-----------------------------|  |
|  |  - kube-apiserver           |  |  - sample-app (pod)         |  |
|  |  - kube-controller-manager  |  |  - mysql (pod)              |  |
|  |  - kube-scheduler           |  |  - nginx-ingress-controller |  |
|  |  - etcd                     |  |                             |  |
|  |  - coredns                  |  |                             |  |
|  |  - calico/flannel (CNI)     |  |                             |  |
|  +-----------------------------+  +-----------------------------+  |
|                                                                    |
|  +-----------------------------+  +-----------------------------+  |
|  |        WORKER 2             |  |        WORKER 3             |  |
|  |        k8s-worker-2         |  |        k8s-worker-3         |  |
|  |-----------------------------|  |-----------------------------|  |
|  |  - sample-app (pod)         |  |  - prometheus               |  |
|  |  - sample-app (pod)         |  |  - grafana                  |  |
|  |  - metrics-server           |  |  - alertmanager             |  |
|  |                             |  |  - node-exporter            |  |
|  +-----------------------------+  +-----------------------------+  |
|                                                                    |
+------------------------------------------------------------------+

Flux reseau:
  Utilisateur --> NodePort/Ingress --> NGINX Ingress --> sample-app (pods)
  sample-app --> MySQL (ClusterIP)
  Prometheus --> scrape --> sample-app /metrics
  Prometheus --> scrape --> node-exporter (tous les noeuds)
  Grafana --> query --> Prometheus
  CronJob backup --> mysqldump --> PVC (stockage backups)
```

### Namespaces

| Namespace       | Contenu                                    |
|----------------|--------------------------------------------|
| `sample-app`    | Application, MySQL, CronJob backup         |
| `monitoring`    | Prometheus, Grafana, Alertmanager          |
| `ingress-nginx` | NGINX Ingress Controller                   |
| `kube-system`   | Composants systeme (coredns, metrics, CNI) |
