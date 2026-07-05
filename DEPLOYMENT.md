# AI BankApp DevOps - Deployment Guide

This guide walks you through provisioning the AWS infrastructure, configuring Kubernetes, deploying the application with ArgoCD, enabling Gateway API with Envoy Gateway, configuring HTTPS using cert-manager, and verifying the deployment.

---

# Prerequisites

Update the system packages.

```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```

## Install Terraform

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | \
sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install terraform -y
```

Verify installation.

```bash
terraform version
```

---

## Install Helm

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
```

Verify installation.

```bash
helm version
```

---

## Install AWS CLI

```bash
sudo apt-get install unzip -y

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
-o "awscliv2.zip"

unzip awscliv2.zip

sudo ./aws/install
```

Verify installation.

```bash
aws --version
```

---

## Install kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Verify installation.

```bash
kubectl version --client
```

---

# Step 1 - Clone the Repository

```bash
git clone https://github.com/RohitRawat891997/AI-BankApp-DevOps.git

cd AI-BankApp-DevOps/terraform
```

Initialize Terraform.

```bash
terraform init --upgrade
```

Validate the configuration.

```bash
terraform validate
```

---

## Terraform Validation Warning

If you receive the following warning:

```text
Warning: Deprecated value used

data.aws_region.current.name

name is deprecated. Use region instead.
```

Update the Terraform module using:

```bash
sed -i 's/data\.aws_region\.current\.name/data.aws_region.current.region/' \
.terraform/modules/ebs_csi_irsa/modules/iam-role-for-service-accounts-eks/main.tf
```

Verify the change.

```bash
sed -n '9p' \
.terraform/modules/ebs_csi_irsa/modules/iam-role-for-service-accounts-eks/main.tf
```

Expected output:

```text
region = data.aws_region.current.region
```

---

## Provision AWS Infrastructure

```bash
terraform plan
terraform apply
```

Terraform provisions:

- VPC
- EKS Cluster
- IAM Roles
- EBS CSI Driver
- ArgoCD
- Prometheus
- Grafana

---

# Step 2 - Configure kubectl

Configure kubectl to access the EKS cluster.

```bash
aws eks update-kubeconfig \
--name bankapp-eks \
--region us-west-2
```

Verify connectivity.

```bash
kubectl get nodes
```

Expected output:

- Three worker nodes
- All nodes should be in **Ready** state.

---

# Step 3 - Verify ArgoCD

Check ArgoCD pods.

```bash
kubectl get pods -n argocd
```

Get the ArgoCD LoadBalancer hostname.

```bash
kubectl get svc argocd-server -n argocd \
-o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Retrieve the admin password.

```bash
kubectl get secret argocd-initial-admin-secret \
-n argocd \
-o jsonpath='{.data.password}' | base64 -d
```

Login credentials:

```
Username : admin
Password : <above password>
```

---

# Step 4 - Install Gateway API and Envoy Gateway

Install Gateway API CRDs.

```bash
kubectl apply --server-side \
-f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

> **Note**
>
> Use `--server-side`. Without it, Envoy Gateway installation may fail because of CRD ownership conflicts.

Install Envoy Gateway.

```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm \
--version v1.2.6 \
--namespace envoy-gateway-system \
--create-namespace \
--skip-crds \
--wait
```

Install Envoy Gateway CRDs.

```bash
helm pull oci://docker.io/envoyproxy/gateway-helm \
--version v1.2.6 \
--untar \
-d /tmp/eg-chart

kubectl apply --server-side \
-f /tmp/eg-chart/gateway-helm/crds/generated/
```

Restart Envoy Gateway.

```bash
kubectl rollout restart deployment envoy-gateway \
-n envoy-gateway-system
```

Verify installation.

```bash
kubectl get gatewayclass
```

---

# Step 5 - Install cert-manager

```bash
helm install cert-manager \
oci://quay.io/jetstack/charts/cert-manager \
--namespace cert-manager \
--create-namespace \
--set crds.enabled=true \
--set config.enableGatewayAPI=true \
--wait
```

Verify installation.

```bash
kubectl get pods -n cert-manager
```

All pods should be **Running**.

---

# Step 6 - Deploy the Application

Deploy the ArgoCD application.

```bash
kubectl apply -f argocd/application.yml
```

Watch the synchronization.

```bash
kubectl get application bankapp -n argocd -w
```

---

# Step 7 - Verify the Deployment

Verify all application pods.

```bash
kubectl get pods -n bankapp
```

Check Persistent Volume Claims.

```bash
kubectl get pvc -n bankapp
```

Verify Gateway.

```bash
kubectl get gateway -n bankapp
```

Retrieve the Envoy Gateway LoadBalancer hostname.

```bash
kubectl get svc \
-n envoy-gateway-system \
-l gateway.envoyproxy.io/owning-gateway-name=bankapp-gateway \
-o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

---

## Verify Application

The home page should return **302** because Spring Security redirects to the login page.

```bash
curl -s -o /dev/null -w "%{http_code}" http://<APP_URL>/
```

Expected:

```
302
```

Verify the login page.

```bash
curl -L -s -o /dev/null -w "%{http_code}" \
http://<APP_URL>/login
```

Expected:

```
200
```

---

# Step 8 - Pull the Ollama Model

The Ollama container starts without any models.

Pull TinyLlama.

```bash
kubectl exec \
-n bankapp \
deploy/ollama \
-- ollama pull tinyllama
```

---

# Cleanup

Delete all Kubernetes resources.

```bash
kubectl delete -f argocd/application.yml

helm uninstall cert-manager -n cert-manager

helm uninstall kube-prometheus -n monitoring

helm uninstall eg -n envoy-gateway-system
```

Delete Gateway API CRDs.

```bash
kubectl delete \
-f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

Wait for AWS Load Balancers to terminate.

```bash
sleep 60
```

Verify no Load Balancers remain.

```bash
aws elb describe-load-balancers \
--region us-west-2 \
--query 'LoadBalancerDescriptions[*].LoadBalancerName' \
--output text
```

Destroy the infrastructure.

```bash
cd terraform

terraform destroy
```

---

# Troubleshooting

## Terraform destroy gets stuck while deleting the VPC

List orphaned Security Groups.

```bash
aws ec2 describe-security-groups \
--region us-west-2 \
--filters Name=vpc-id,Values=<VPC_ID> \
--query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' \
--output table
```

Delete the Security Group.

```bash
aws ec2 delete-security-group \
--group-id <SG_ID> \
--region us-west-2
```

Delete the VPC.

```bash
aws ec2 delete-vpc \
--vpc-id <VPC_ID> \
--region us-west-2
```

Run Terraform destroy again.

```bash
terraform destroy
```

---

## Gotchas We Hit

### 1. Gateway API CRDs + Envoy Gateway Conflict
**Symptom:** `helm install` for Envoy Gateway fails with `conflict with "kubectl-client-side-apply"`.
**Cause:** `kubectl apply` uses client-side apply for CRDs. When Envoy Gateway tries to install the same CRDs via server-side apply, ownership conflicts.
**Fix:** Use `kubectl apply --server-side` for CRDs, then `--skip-crds` on helm install.

### 2. Docker Image Platform Mismatch
**Symptom:** Pods show `ErrImagePull` with error `no match for platform in manifest: not found`.
**Cause:** Building on Apple Silicon (arm64) produces arm64 images. EKS nodes are amd64.
**Fix:** Use `docker buildx build --platform linux/amd64 --push`. This does NOT apply to GitHub Actions CI (runs on ubuntu/amd64).

### 3. Image Doesn't Exist on First Deploy
**Symptom:** Pods show `ImagePullBackOff` with `repository does not exist or may require authorization`.
**Cause:** ArgoCD deploys immediately but CI hasn't pushed the first image to DockerHub yet.
**Fix:** Build and push the image manually (Step 6) before or right after applying the ArgoCD application.

### 4. Envoy Gateway Extension CRDs Missing After `--skip-crds`
**Symptom:** `BackendTrafficPolicy` resource fails with `no matches for kind`.
**Cause:** `--skip-crds` skips ALL CRDs, including Envoy Gateway's own extension CRDs (BackendTrafficPolicy, SecurityPolicy, etc.) — not just the Gateway API CRDs.
**Fix:**
```bash
helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.2.6 --untar -d /tmp/eg-chart
kubectl apply --server-side -f /tmp/eg-chart/gateway-helm/crds/generated/
kubectl rollout restart deployment envoy-gateway -n envoy-gateway-system
```

### 5. Login Redirect Loop with Multiple Replicas Behind Envoy Gateway
**Symptom:** Login page keeps redirecting back to itself. No error message shown.
**Cause:** Envoy Gateway bypasses K8s Service `sessionAffinity: ClientIP` and load-balances directly to pod endpoints. With in-memory sessions, GET /login hits pod A (creates CSRF token), POST /login hits pod B (CSRF mismatch → silent redirect to /login).
**Fix:** Add `BackendTrafficPolicy` with cookie-based consistent hashing (in `k8s/gateway.yml`) and `SERVER_FORWARD_HEADERS_STRATEGY=native` in configmap.

### 6. `terraform destroy` Stuck on VPC Deletion
**Symptom:** `terraform destroy` hangs on VPC delete with `DependencyViolation`.
**Cause:** Helm-installed resources (Envoy Gateway, Grafana LB) created AWS Load Balancers and Security Groups outside Terraform. When EKS is destroyed first, these orphan and block VPC deletion.
**Fix:** Always uninstall Helm releases and delete the ArgoCD app BEFORE running `terraform destroy`. If already stuck, delete orphaned ELBs and SGs via AWS CLI (see Cleanup section above).

### 7. ArgoCD Shows OutOfSync After Manual Rollout Restart
**Symptom:** ArgoCD status shows `OutOfSync` even though app is healthy.
**Cause:** `kubectl rollout restart` adds a restartedAt annotation that doesn't match the Git manifest.
**Fix:** Not a problem — next CI push updates the manifest and ArgoCD syncs to it, resolving the drift.

---

## Access Summary

| Service | URL Command | Credentials |
|---------|------------|-------------|
| **BankApp** | `kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=bankapp-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'` | App login |
| **ArgoCD** | `kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` | `admin` / see Step 3 |
| **Grafana** | `kubectl get svc kube-prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` | `admin` / see Step 5 |
