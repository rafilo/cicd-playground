# Local LoadBalancer and the existing AKS cluster

kind and AKS are separate clusters. Workloads move through container images and Kubernetes declarations; kind nodes are not joined to AKS. `cloud-provider-kind` runs only locally. AKS uses the native Azure cloud controller and Standard Load Balancer.

## Native local commands

```powershell
kubectl --context kind-cicd-gitops label node cicd-gitops-control-plane node.kubernetes.io/exclude-from-external-load-balancers- --overwrite
docker compose -f cluster/cloud-provider-kind.compose.yaml up -d
kubectl --context kind-cicd-gitops -n argocd get service argocd-server
docker ps --filter name=kindccm --format '{{.Names}} {{.Ports}}'
```

Compose uses the official v0.12.0 image pinned by digest. It requires Docker socket access to discover kind clusters and manage load-balancer containers; no temporary tools directory is required. `--enable-lb-port-mapping` enables access from Windows through Docker-published host ports. These ports are not fixed; query them again after recreating the load balancer. Generated mappings may bind to all host interfaces by default; host networking and firewall rules determine accessibility.

The Service's external IP is a Docker network address, not an Azure public IP. On Windows, use the host port mapped to 443 in `docker ps`, for example `https://127.0.0.1:<HTTPS-port>`. Do not assume the Docker IP is directly routable.

```powershell
# Stop the controller; this does not automatically delete the Service or kind cluster.
docker compose -f cluster/cloud-provider-kind.compose.yaml down
```

## Current Azure target (2026-10-18)

| Item | Value |
| --- | --- |
| Subscription | Subscription 1 |
| Subscription ID | 147696b1-4588-433b-a0a8-e025d093c554 |
| Tenant ID | 0aacabb6-7680-4f70-be05-06b7f471b449 |
| Resource Group | argoCD-devops-test |
| AKS | argoCDcluster |
| Region | eastus |
| Kubernetes | 1.36.4 |
| Node pool | agentpool / Standard_D2ps_v6 / ARM64 |
| Autoscaling | Existing configuration min=1, max=2; automatically scaled to two nodes when scheduling Argo CD |
| API endpoint | Public API; Azure/Kubernetes identity authorization is still required |
| Network / LB | Azure CNI / Standard |
| Node Resource Group | MC_argoCD-devops-test_argoCDcluster_eastus |
| Argo CD namespace | argocd |
| App namespace | cicd-azure |
| Image repository | docker.io/rafilo/test-devops |

The `infra/azure/platform` Terraform configuration for a new cloud platform was not run, and no ACR or database was created. This deployment uses an existing AKS cluster; deploying workloads triggered its existing node autoscaling configuration.

## Build a multi-architecture image

The AKS nodes are ARM64 and cannot run an AMD64-only image. The Microsoft .NET base images in the Dockerfile support both architectures.

```powershell
docker login
# Create the builder if it does not exist; do not switch another project's default builder.
docker buildx create --name cicd-aks-builder --driver docker-container
docker buildx build --builder cicd-aks-builder --platform linux/amd64,linux/arm64 --build-arg VERSION=aks-20261018 -t docker.io/rafilo/test-devops:aks-20261018 --push .
docker buildx imagetools inspect docker.io/rafilo/test-devops:aks-20261018
```

Use a new version tag for later releases and update the image override in `argocd/aks/application/application.yaml` to the published immutable digest. Host Docker login does not automatically configure AKS pull credentials. Public images need no Secret; private images require a restricted imagePullSecret in `cicd-azure`, referenced by the workloads.

The multi-architecture image digest published for this deployment was `sha256:0402517132788a43149e2c1652d7056024778fd2ddc51a850d21c9ab8a96843a`. The repository rejects anonymous pulls. With user authorization, the AKS `cicd-azure/dockerhub-pull` Secret was created directly from the host's Docker credential store. Credentials were not printed or written to local files or Git. The Application's Kustomize patch injects this Secret reference into both Deployments. For ongoing maintenance, use a separate read-only image-pull token and rotate it in the Secret; do not commit the token to the repository.

## Connect to the existing AKS cluster

The following commands use the user's kubeconfig and select an explicit context:

```powershell
az aks get-credentials --subscription 147696b1-4588-433b-a0a8-e025d093c554 --resource-group argoCD-devops-test --name argoCDcluster --context aks-argoCDcluster
kubectl --context aks-argoCDcluster get nodes
```

This deployment used `%TEMP%/cicd-gitops-aks.kubeconfig` to isolate credentials and did not change the default kind context. When reusing this file, add `--kubeconfig "$env:TEMP/cicd-gitops-aks.kubeconfig"` to each kubectl command below.

## Install Argo CD and the Azure entry point

```powershell
kubectl --context aks-argoCDcluster create namespace argocd --dry-run=client -o yaml | kubectl --context aks-argoCDcluster apply -f -
kubectl --context aks-argoCDcluster apply --server-side -k argocd/install
kubectl --context aks-argoCDcluster apply -k argocd/aks
kubectl --context aks-argoCDcluster -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl --context aks-argoCDcluster -n argocd get service argocd-server-internal-lb
```

The entry point is an Azure internal LB, directly accessible only through the VNet, VPN, or connected peered networks; it is not public. This deployment received `10.224.0.5:443`; use the actual Service status. Default TLS uses a self-signed certificate. Configure a trusted domain certificate for regular use.

## Deploy the application through AKS Argo CD

```powershell
kubectl --context aks-argoCDcluster apply -f infra/azure/bootstrap/namespace.yaml
kubectl --context aks-argoCDcluster apply -k argocd/aks/application
kubectl --context aks-argoCDcluster -n argocd get application cicd-azure
kubectl --context aks-argoCDcluster -n cicd-azure get pods -o wide
```

The Application reads the existing remote `master:k8s/base` and overrides the namespace and image in Argo CD, so deployment does not require pushing these new directories first. The AppProject restricts the repository, target namespace, and resource types. The new Application definition itself is currently applied by an administrator. Do not also manage these workloads with `infra/azure/application` Terraform.

The Secret is an administrator bootstrap resource and is not managed by this AppProject. Securely recreate `dockerhub-pull` after rebuilding the namespace.

Changing the image digest requires updating and applying the Application definition. Existing GitHub CI publishes to GHCR by default and does not automatically update this Docker Hub target. This deployment does not demonstrate an integrated automatic Docker Hub promotion pipeline.

## Access AKS from the local computer

Without a VPN, keep the following two terminals open to access services through the Kubernetes API; there is no need to change the management entry point to a public LB:

```powershell
kubectl --context aks-argoCDcluster -n argocd port-forward svc/argocd-server 18443:443 --address=127.0.0.1
kubectl --context aks-argoCDcluster -n cicd-azure port-forward svc/demo-web 18082:80 --address=127.0.0.1
```

The local kind application continues using 8081, the AKS application uses 18082, and AKS Argo CD uses 18443, avoiding port conflicts.

## Actual validation on 2026-10-18

- The local Argo CD LoadBalancer IP was `172.18.0.4`; Docker mapped HTTPS to host port `56005`, and the HTTP check returned 200.
- All AKS Argo CD Pods were Ready, and the internal LB received `10.224.0.5`. Access through the local API tunnel on 18443 returned 200. This does not claim the local computer had a direct network route to the private LB.
- AKS Application `cicd-azure` was `Synced / Healthy`; all three backend Pods and one web Pod were Running on ARM64 nodes.
- The AKS homepage returned 200 and readiness returned ok. All 30 requests returned `aks-20261018`; the three backends handled 16, 8, and 6 requests.
- The local kind application on 8081 still returned 200, and the default kubectl context remained `kind-cicd-gitops`.
- There were two nodes after scaling by the existing autoscaler. Its min/max settings were not changed, and no new AKS or ACR was created.

Official references: [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind), [AKS internal load balancer](https://learn.microsoft.com/en-us/azure/aks/internal-lb).
