K8s Assignment

This document is used to Deploy a two-tier application (a web service and a database) within the local cluster.

Tools Used: Docker, Kind, Terraform, K8s, K9s(monitoring)

1. Provision the cluster with Terraform (IaC)
cd terraform
terraform init
terraform apply -auto-approve

This creates a Kind cluster named assignment-cluster and writes a

kubeconfig. Point kubectl at it:
kind get kubeconfig --name assignment-cluster > ~/.kube/config-assignment
export KUBECONFIG=~/.kube/config-assignment
kubectl get nodes

You should see one Ready node (assignment-cluster-control-plane).

2. Build the Docker image and load it into Kind
Kind clusters don't have access to your local Docker daemon's images by

default — you must explicitly load the image in.
cd ../app
docker build -t hello-web:latest .
cd ..
kind load docker-image hello-web:latest --name assignment-cluster

3. Deploy the two-tier app
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/02-secret.yaml
kubectl apply -f k8s/03-postgres-pvc.yaml
kubectl apply -f k8s/04-postgres-deployment.yaml
kubectl apply -f k8s/05-postgres-service.yaml
kubectl apply -f k8s/06-web-deployment.yaml
kubectl apply -f k8s/07-web-service.yaml

# Or simply: kubectl apply -f k8s/   (excluding the metrics-server patch file,
# which is applied separately in step 4)

kubectl -n assignment rollout status deployment/postgres
kubectl -n assignment rollout status deployment/web
kubectl -n assignment get pods,pvc,svc

Access the app
The Terraform config maps container NodePort 30080 to host port 8080:
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/db-time

(If port 8080 isn't reachable, fall back to kubectl -n assignment port-forward svc/web 8080:80 in another terminal.)

4. Deploy observability (metrics-server + k9s)

# 1. Install the base metrics-server manifest first (only needed once per cluster)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 2. Patch it (NOT apply) — and make sure your local copy has --secure-port=10250, not 4443
kubectl patch deployment metrics-server -n kube-system \
  --type strategic \
  --patch-file k8s/08-metrics-server-patch.yaml

# 3. Check rollout
kubectl -n kube-system rollout status deployment/metrics-server
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Wait ~30s for metrics to populate, then:
kubectl top nodes
kubectl top pods -n assignment

For live visual monitoring:
k9s

Inside k9s: type :pods, :deploy, or :pvc and hit Enter to browse

resources; 0 shows all namespaces.
