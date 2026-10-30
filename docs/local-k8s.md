# Build and deploy the local .NET Kubernetes project with native commands

Open PowerShell in the repository root. Install and start Docker Desktop (Linux containers), and make kind and kubectl available on PATH.

```powershell
winget install --id Kubernetes.kind --exact --version 0.33.0 --source winget
# If kubectl is not installed:
winget install --id Kubernetes.kubectl --exact --source winget
```

Reopen the terminal after installation. The Docker build provides the .NET SDK, so the host does not need it installed. The following steps require no temporary project-local tools or generated YAML files.

## 1. Create or recover the cluster

```powershell
docker info
kind get clusters
```

If `cicd-gitops` does not exist:

```powershell
kind create cluster --name cicd-gitops --config cluster/kind.yaml --wait 180s
```

If the cluster exists but its node container is stopped:

```powershell
docker start cicd-gitops-control-plane
kind export kubeconfig --name cicd-gitops
```

Check the target node:

```powershell
kubectl --context kind-cicd-gitops wait --for=condition=Ready nodes --all --timeout=180s
```

## 2. Build and load the image

```powershell
docker build --build-arg VERSION=local-k8s-20261018 -t podflow:local-k8s-20261018 .
kind load docker-image podflow:local-k8s-20261018 --name cicd-gitops
```

The image name matches `k8s/overlays/local/kustomization.yaml`. For subsequent versions, use a new tag and update `newTag` in that file. If reusing the same tag, run rollout restart after apply so existing Pods use the reloaded image.

## 3. Create the namespace and deploy Pods

```powershell
kubectl --context kind-cicd-gitops create namespace cicd-demo --dry-run=client -o yaml | kubectl --context kind-cicd-gitops apply -f -
kubectl --context kind-cicd-gitops apply -k k8s/overlays/local
kubectl --context kind-cicd-gitops -n cicd-demo rollout status deployment/demo --timeout=180s
kubectl --context kind-cicd-gitops -n cicd-demo rollout status deployment/demo-web --timeout=180s
kubectl --context kind-cicd-gitops -n cicd-demo get pods -o wide
```

Optional: after rebuilding and loading the same tag, run:

```powershell
kubectl --context kind-cicd-gitops -n cicd-demo rollout restart deployment/demo deployment/demo-web
```

Wait again for both Deployment rollouts to finish. The local overlay deploys three backend Pods, one web Pod, two Services, and one PDB, managed by kubectl. Do not let Argo CD simultaneously manage workloads with the same names in that namespace during local runs.

## 4. Access and verify

```powershell
kubectl --context kind-cicd-gitops -n cicd-demo port-forward svc/demo-web 8081:80 --address=127.0.0.1
```

Keep this terminal open and visit http://127.0.0.1:8081/. Ctrl+C stops only the port forward; it does not delete the cluster or Pods. Verify from another terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:8081/readyz
1..30 | ForEach-Object { (Invoke-RestMethod http://127.0.0.1:8081/api/whoami).pod } | Group-Object
```

The local Argo CD LoadBalancer is integrated through a separate Docker Compose configuration. See [cloud-provider-kind and AKS](kind-loadbalancer-and-aks.md).
