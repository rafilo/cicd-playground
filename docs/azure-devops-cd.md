# Simulated Azure DevOps CD

The root azure-pipelines.cd.yml is a manually triggered Azure Pipelines YAML example. It prepares GitOps review artifacts for the existing dev and prod overlays. GitHub Actions remains the image builder and ArgoCD remains the cluster deployer.

## Run in Azure DevOps

1. Create an Azure DevOps pipeline connected to this GitHub repository using an authorized GitHub connection.
2. Select the existing YAML file azure-pipelines.cd.yml.
3. Run manually on master. Leave promoteToProd enabled to simulate both stages.
4. Download simulated-cd-dev and simulated-cd-prod from the run artifacts.

The pipeline requires Azure DevOps access to the GitHub source and a Microsoft-hosted Ubuntu agent with network access to dl.k8s.io. It does not require an Azure subscription, AKS cluster, ACR registry, Kubernetes credentials, Azure service connection, or Azure DevOps Environment resource. No Azure run has been provisioned by adding these files.

## Flow

SimulateDev renders the current development overlay. After it succeeds, SimulateProd copies the development image digest into the production overlay in its own checkout and renders production. This is a pipeline sequencing demonstration, not proof of development runtime acceptance: a real promotion must first verify the development application's health and acceptance results.

Both stages reuse pipelines/templates/simulate-gitops-cd.yml and publish:

- manifests.yaml: complete environment manifests produced by Kustomize.
- promotion.patch: proposed overlay changes; empty when no promotion change is necessary.
- simulation-plan.json: environment, source commit, Azure placeholders, and the next review action.

No task logs into Azure, applies manifests, pushes Git, creates a PR, or changes existing clusters. The production mutation is confined to the agent workspace and its published artifact. Kustomize rendering validates composition, not Kubernetes API acceptance.

## Placeholders

| Variable | Replace with for a future integration |
| --- | --- |
| azureSubscriptionId | Azure subscription ID |
| azureServiceConnection | Azure Resource Manager service connection name |
| azureResourceGroup | Resource group containing the target AKS cluster |
| aksClusterName | Target AKS cluster name |
| acrLoginServer | Registry hostname, such as example.azurecr.io |
| devEnvironment | Azure DevOps development Environment name |
| prodEnvironment | Azure DevOps production Environment name |

These values are descriptive simulation metadata. Replacing them does not enable deployment. The current rendered images still reference GHCR; the ACR placeholder does not migrate or publish images.

## Extend to real GitOps CD

Add authenticated GitHub PR creation for the production patch using a secret credential or GitHub App with scoped permissions. Keep review and merge separate from artifact preparation; ArgoCD reconciles the merged overlay. Configure AKS as an ArgoCD destination and update its AppProject destinations before moving workloads.

If deployment history and approvals are needed in Azure DevOps, introduce deployment jobs referencing pre-created Environment resources. Configure approvals/checks on those resources in Azure DevOps, outside this YAML. The simulation uses ordinary jobs so fake environment names do not require real resources. Do not add direct kubectl apply steps alongside ArgoCD reconciliation.

Use workload identity federation for Azure service connections when Azure access is actually needed. Store credentials in secret variables or an approved secret store, never in YAML. Add runtime health verification, protected-branch reviews, scanning and provenance checks before treating the example as a production release process.

## Official references

- [Azure Pipelines templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates)
- [Template parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters)
- [Deployment jobs](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/deployment-jobs)
- [Environments](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments)
