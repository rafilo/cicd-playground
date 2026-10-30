# Argo CD LoadBalancer Service on AKS

This directory adds an `argocd-server-internal-lb` Service to an existing Argo CD installation. It does not install Argo CD, take over the application, or replace the existing `argocd-server` ClusterIP Service.

The defaults target the project's private AKS configuration: the Azure internal load balancer receives a private VNet address, and clients must access it from the same VNet, a VPN, or a connected peered network. The `EXTERNAL-IP` column still shows a private IP in this configuration; it does not indicate a public address.

Traffic path: `https://<private-IP>:443` → LoadBalancer Service → port 8080 on the `argocd-server` Pod. Only HTTPS is exposed. Argo CD must retain its default TLS mode; do not set `server.insecure=true`. Azure Load Balancer forwards TCP and does not terminate TLS. Configure the certificate for the production domain in Argo CD.

## Deploy

The following commands assume default names for the Terraform-created resources. Adjust them to match the actual resources, and run from a terminal that can access the private AKS API:

```powershell
az aks get-credentials --resource-group rg-cicdlearn-dev --name aks-cicdlearn-dev --context aks-cicdlearn-dev
kubelogin convert-kubeconfig -l azurecli
kubectl --context aks-cicdlearn-dev -n argocd get deployment argocd-server
kubectl --context aks-cicdlearn-dev -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl --context aks-cicdlearn-dev apply -k argocd/aks
kubectl --context aks-cicdlearn-dev -n argocd get service argocd-server-internal-lb --watch
```

If Argo CD is not installed, first follow the platform administrator procedure to create the `argocd` namespace and install a reviewed Argo CD version, then apply this directory.

After a private IP is assigned, open `https://<private-IP>/` from a client with network connectivity. The local kind port forward on `8443` and .NET port `8081` are host-local ports and do not conflict with the AKS LoadBalancer's separate IP/443.

## Permissions and checks

- A platform administrator creates this Service; a deployment Writer scoped to the application namespace cannot manage `argocd`.
- The AKS control-plane managed identity needs network permissions on the target subnet. This project's Terraform grants Network Contributor on the AKS subnet, where addresses are allocated by default.
- For another subnet, add the `azure-load-balancer-internal-subnet` annotation and grant the control-plane identity permissions on that subnet. This example does not hardcode a static IP.
- If the IP remains Pending, inspect Service events, Azure quotas, identity permissions, and available subnet addresses. Do not wait for an Azure IP on kind, which has no Azure cloud controller.

```powershell
kubectl --context aks-cicdlearn-dev -n argocd describe service argocd-server-internal-lb
kubectl --context aks-cicdlearn-dev -n argocd get endpointslice -l kubernetes.io/service-name=argocd-server-internal-lb
```

The top-level Kustomization in this directory manages only the entry Service. The `application/` subdirectory separately manages the .NET application's AppProject and Application. See [cloud-provider-kind and AKS](../../docs/kind-loadbalancer-and-aks.md) for deployment records and native commands for the existing AKS cluster.

Official reference: [AKS internal LoadBalancer](https://learn.microsoft.com/en-us/azure/aks/internal-lb).
