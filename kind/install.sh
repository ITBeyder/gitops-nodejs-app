# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Create Custom Docker Network
docker network create kind-network --driver bridge --subnet 172.18.0.0/16

# Create DevOps (ArgoCd) cluster

cd kindClusters
kind create cluster --config kind-devops-cluster.yaml

# Create additional clusters
kind create cluster --config kind-test-cluster.yaml
kind create cluster --config kind-stage-cluster.yaml
kind create cluster --config kind-prod-cluster.yaml

# Connect argocd-cluster to the network
docker network connect kind-network kind-devops-cluster-control-plane
docker network connect kind-network kind-test-cluster-control-plane
docker network connect kind-network kind-stage-cluster-control-plane
docker network connect kind-network kind-prod-cluster-control-plane

# Install ArgoCD on the ArgoCD Cluster
kubectl config use-context kind-kind-devops-cluster

# Create namespace and install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
# DWhsg0IUeCO5Dhm7

# Port-forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# # # # # # # # # # # # # # # # # # # # # # #
# # #  Register Test Cluster with ArgoCD # # 
# # # # # # # # # # # # # # # # # # # # # # #

# First, make sure you're on the test cluster context
kubectl config use-context kind-kind-test-cluster

# Create a service account for ArgoCD (if not exists)
kubectl create serviceaccount argocd-manager -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Create cluster role binding
kubectl create clusterrolebinding argocd-manager-role-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager \
  --dry-run=client -o yaml | kubectl apply -f -

  # Get the service account token
TOKEN=$(kubectl create token argocd-manager -n kube-system --duration=87600h)

# Get the CA certificate
CA_CERT=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="kind-kind-test-cluster")].cluster.certificate-authority-data}')

# Get the internal IP address
MANAGED_API_SERVER=$(docker inspect kind-test-cluster-control-plane --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}: {{.IPAddress}}{{println}}{{end}}')

echo "API Server IP: $MANAGED_API_SERVER"
echo "Token: $TOKEN"
echo "CA Cert: $CA_CERT"

# # # # # # # # # # # # # # # # # # # # # # #
# # #  Register Stage Cluster with ArgoCD # # 
# # # # # # # # # # # # # # # # # # # # # # #

# First, make sure you're on the stage cluster context
kubectl config use-context kind-kind-stage-cluster

# Create a service account for ArgoCD (if not exists)
kubectl create serviceaccount argocd-manager -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Create cluster role binding
kubectl create clusterrolebinding argocd-manager-role-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager \
  --dry-run=client -o yaml | kubectl apply -f -

  # Get the service account token
TOKEN=$(kubectl create token argocd-manager -n kube-system --duration=87600h)

# Get the CA certificate
CA_CERT=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="kind-kind-stage-cluster")].cluster.certificate-authority-data}')

# Get the internal IP address
MANAGED_API_SERVER=$(docker inspect kind-stage-cluster-control-plane --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}: {{.IPAddress}}{{println}}{{end}}')

echo "API Server IP: $MANAGED_API_SERVER"
echo "Token: $TOKEN"
echo "CA Cert: $CA_CERT"

# # # # # # # # # # # # # # # # # # # # # # #
# # #  Register Prod Cluster with ArgoCD # # 
# # # # # # # # # # # # # # # # # # # # # # #

# First, make sure you're on the stage cluster context
kubectl config use-context kind-kind-prod-cluster

# Create a service account for ArgoCD (if not exists)
kubectl create serviceaccount argocd-manager -n kube-system --dry-run=client -o yaml | kubectl apply -f -

# Create cluster role binding
kubectl create clusterrolebinding argocd-manager-role-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager \
  --dry-run=client -o yaml | kubectl apply -f -

  # Get the service account token
TOKEN=$(kubectl create token argocd-manager -n kube-system --duration=87600h)

# Get the CA certificate
CA_CERT=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="kind-kind-prod-cluster")].cluster.certificate-authority-data}')

# Get the internal IP address
MANAGED_API_SERVER=$(docker inspect kind-prod-cluster-control-plane --format '{{range $net,$v := .NetworkSettings.Networks}}{{$net}}: {{.IPAddress}}{{println}}{{end}}')

echo "API Server IP: $MANAGED_API_SERVER"
echo "Token: $TOKEN"
echo "CA Cert: $CA_CERT"