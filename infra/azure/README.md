# Azure AKS Terraform simulation project

This example provisionally interprets the original requirement's ALS as **AKS**. It supports the existing ASP.NET Core/.NET 10 demo, three backend replicas, and web proxy. The Azure example is separate from kind and the original Argo CD configuration. The code supports learning and preparation for a real deployment, but Azure plan/apply has not been run and no billable resources have been created through it. See [the .NET CI/CD guide](../../docs/dotnet-cicd.md) for the complete release process.

## Directories and resources

| Path | Responsibility |
| --- | --- |
| `platform/network.tf` | VNet, AKS/database/Private Endpoint subnets, and database private DNS |
| `platform/aks.tf` | Private AKS, Entra RBAC, autoscaling, upgrades, Log Analytics, and auditing |
| `platform/database.tf` | PostgreSQL 16, separate appdb, TLS, 14-day backups, and production HA |
| `platform/security.tf` | Private Key Vault, RBAC, mandatory-tag policies, and Pod security baseline auditing |
| `application/main.tf` | Reuses existing `k8s/base`, replaces the image with a real GHCR digest, and deploys the application |
| `bootstrap/namespace.yaml` | Namespace precreated by a platform administrator with Pod Security restrictions |
| `azure-pipelines.terraform.yml` (repository root) | Separate static validation pipeline without credentials |

`platform` and `application` are separate Terraform root modules with separate state. Files within platform are organized by capability; each `.tf` file is not a child module.

```text
VNet 10.40.0.0/16
├── AKS subnet → private AKS API + application Pods
├── PostgreSQL delegated subnet → PostgreSQL / appdb
└── Private Endpoint subnet → Key Vault
                 ↓
       Private DNS + Log Analytics

Browser → kubectl port-forward → demo-web → demo Service → three demo Pods
```

The example retains the project's existing public GHCR image source and does not create an unused ACR. Access is through port-forward, with no public entry point. A real external service requires separate domain, TLS, Ingress/Gateway, and access-policy configuration.

An AKS cluster with Argo CD already installed can use the [internal LoadBalancer Service](../../argocd/aks/README.md) to expose a management endpoint over HTTPS/443 on a private IP. This configuration is separate from application Terraform and does not automatically enable GitOps ownership.

## Permissions and compliance design

- AKS disables local accounts and uses Entra + Azure RBAC. The platform administrator group has AKS Cluster Admin access. The application deployment identity has only RBAC Writer on `cicd-azure` and the Cluster User Role for obtaining a user kubeconfig.
- The AKS control-plane identity receives Network Contributor only on the AKS subnet. The cluster enables OIDC/Workload Identity, but the current application has no database functionality and is not granted access to the database administrator password.
- Key Vault disables public access and enables RBAC, 90-day soft delete, and purge protection. The Terraform execution identity receives Secrets Officer on that Vault to write the initial password. Ongoing permissions can be narrowed through a separate credential bootstrap process.
- Azure Policy denies new resources missing required tags. The built-in Kubernetes Pod security baseline uses `audit`; audit mode is not enforcement. Namespace Pod Security `restricted` does enforce admission restrictions.
- AKS, database, and Key Vault diagnostic logs go to Log Analytics with 30-day retention. No regulatory certification is assumed. Actual compliance also requires organization-specific retention, archiving, alerts, exception approvals, and audit evidence.
- PostgreSQL is private-only, requires TLS, keeps 14-day backups, and uses `prevent_destroy` to block accidental destruction. Prod enables zone-redundant HA, subject to regional support and quota.
- The application retains existing non-root execution, a read-only root filesystem, disabled privilege escalation, dropped capabilities, health checks, resource limits, and PDBs.

Pod default-deny NetworkPolicy, an outbound firewall, SIEM alerts, and fine-grained database roles are not configured. This is not a complete production security baseline.

## Prerequisites

1. Terraform >= 1.9, Azure CLI, kubectl, and kubelogin. AzureRM is pinned to 4.59.x and the Kubernetes provider to 2.38.x. Revalidate after upgrades. Both root modules contain `.terraform.lock.hcl` files generated during init.
2. An Azure subscription, Entra administrator group, and application deployment identity. Supply object IDs; do not substitute client/application IDs for object IDs.
3. Preregister required Resource Providers and arrange regional VM/database quotas. Private clusters, databases, and monitoring incur charges.
4. The Terraform runner must reach the VNet and resolve private AKS and Key Vault DNS. Connect a new VNet through planned hub peering/VPN and DNS forwarding, or initially run from a self-hosted runner with connectivity. A standard public hosted agent cannot complete the full deployment.
5. The infrastructure identity needs resource-creation permissions. Role assignments also require appropriate RBAC administration permissions; custom policy definitions require subscription-level policy management permissions. Do not grant these permissions to the application pipeline.

## Step 1: Infrastructure

```powershell
cd infra/azure/platform
Copy-Item terraform.tfvars.example terraform.tfvars
# Set the real subscription_id, administrator group, and application deployment identity object IDs.
az login
terraform init
terraform fmt -check
terraform validate
terraform plan -out=platform.tfplan
# After reviewing the plan, apply if required; real resources incur charges:
terraform apply platform.tfplan
terraform output
```

Key Vault role assignments may take time to propagate. If the first secret write returns an authorization error, wait for permissions to take effect, then rerun plan/apply. For connection timeouts, check the runner's network and private DNS first.

Local state is suitable only for this simulation. Passwords remain in Terraform state and plans even when marked sensitive or stored in Key Vault. Do not upload them to Git or general-purpose pipeline artifacts. Real CI should use a separately precreated Azure Storage backend, Entra/OIDC authentication, container-scoped Storage Blob Data Contributor, state locking, and controlled networking. Use different state keys for platform and application. Do not read platform state containing administrator credentials from application.

## Step 2: Platform administrator bootstrap

From the repository root, an administrator runs:

```powershell
az aks get-credentials --resource-group rg-cicdlearn-dev --name aks-cicdlearn-dev --context aks-cicdlearn-dev
kubelogin convert-kubeconfig -l azurecli
kubectl --context aks-cicdlearn-dev apply -f infra/azure/bootstrap/namespace.yaml
```

Select the AKS context explicitly to avoid operating on the existing kind cluster. After role assignments propagate, the application deployment identity obtains this context using its own login credentials.

## Step 3: Deploy the existing application

```powershell
cd infra/azure/application
Copy-Item terraform.tfvars.example terraform.tfvars
# Set the AKS context and real public image digest from the existing k8s/overlays/dev/kustomization.yaml.
terraform init
terraform validate
terraform plan -out=application.tfplan
terraform apply application.tfplan
kubectl --context aks-cicdlearn-dev -n cicd-azure rollout status deployment/demo
kubectl --context aks-cicdlearn-dev -n cicd-azure rollout status deployment/demo-web
kubectl --context aks-cicdlearn-dev -n cicd-azure port-forward svc/demo-web 8081:80
```

Open http://localhost:8081. The image must be publicly pullable; this example does not create private GHCR pull credentials. For later application updates, change the image digest and rerun plan/apply.

Application Terraform connects to an existing AKS cluster during plan, so it cannot share the initial apply that creates AKS. Managing Kubernetes manifests does not replace rollout checks.

## Relationship to existing GitOps/CI/CD

Existing CI and Argo CD retain their workflows. The added Terraform validation pipeline does not log into Azure, produce a real plan, or apply changes. Real delivery can be extended through these stages:

```text
PR → fmt/validate/security scan → platform plan with OIDC identity
   → protected-environment approval → platform apply
   → administrator namespace bootstrap → application plan/apply → rollout verification
```

Real plan/apply requires a service connection, controlled state storage, and a VNet-connected self-hosted agent. The repository's existing simulated Azure CD does not automatically deploy this directory.

Terraform manages the application in this AKS demonstration; Argo CD continues to manage the original kind application. To switch AKS to Argo CD too, first plan the resource ownership migration, back up state, and remove Terraform management of application resources before Argo CD takes over. Do not let both manage the same Deployment.

## Database extension and cleanup

The existing `app/Program.cs` has no database driver or SQL logic. This example creates a database but does not claim the application is connected. Future integration needs a separate least-privilege database user, TLS database connections and migrations, and application-specific credentials supplied through Workload Identity + Key Vault CSI. Do not use the administrator password as the application password.

Delete application resources before addressing platform resources. The database has `prevent_destroy` by default, which blocks `terraform destroy`. If deletion is required, first back up the data and explicitly change that protection, then review the destruction plan. Key Vault purge protection retains soft-deleted records; rebuilding may require restoring the Vault or choosing another name.

## Official references

- [AKS Terraform resource](https://registry.terraform.io/providers/hashicorp/azurerm/4.59.0/docs/resources/kubernetes_cluster)
- [Azure Policy for AKS](https://learn.microsoft.com/azure/aks/use-azure-policy)
- [PostgreSQL Terraform deployment](https://learn.microsoft.com/en-us/azure/developer/terraform/deploy-postgresql-flexible-server-database)
- [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)
