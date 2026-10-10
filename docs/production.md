# Local production migration

This environment rehearses a production deployment on a separate local kind cluster. It does not provide physical fault isolation or a highly available control plane.

## Start

Install Docker Desktop (Linux containers), kubectl, Helm 3 or later, and the project kind executable at tools/kind.exe. Reserve loopback port 18080. Allow sufficient Docker memory for both clusters (12 GiB is recommended).

```powershell
cd <your-directory>/cicd-gitops
./scripts/start-production.ps1
kubectl --context kind-cicd-production -n argocd get application cicd-production
kubectl --context kind-cicd-production -n cicd-prod get pods -o wide
```

Open http://localhost:18080. The host port maps to Traefik NodePort 30080; no port-forward process is required. Traefik has two replicas, the frontend has two replicas, and the backend has three replicas. Workloads spread across three worker nodes. Pod disruption budgets protect against voluntary disruption; they do not prevent host failure.

The learning cluster and its port-forward remain separate. Every production command selects kind-cicd-production explicitly.

## Delivery and rollback

CI continues publishing immutable development image digests. Production reads its own overlay and changes only when that overlay changes in Git. Promote an accepted development image on a new branch:

```powershell
git switch -c codex/promote-production
./scripts/promote-production.ps1
kubectl kustomize k8s/overlays/prod
git add k8s/overlays/prod/kustomization.yaml
git commit -m "Promote validated image to production"
git push -u origin HEAD
gh pr create --base master --title "Promote validated image to production" --body "Promote the tested development image digest."
```

Review and merge the PR; ArgoCD then reconciles production automatically. Configure a protected master branch with required reviews and CI checks in the real production repository. Roll back by reverting the production digest commit through a reviewed PR. An imperative kubectl image update will be reverted by ArgoCD self-healing.

The production Argo project allows only this repository, namespace, and required namespaced resource types. Platform administrators manage ingress and ArgoCD separately from application reconciliation.

## Acceptance

```powershell
kubectl --context kind-cicd-production -n cicd-prod rollout status deployment/demo
kubectl --context kind-cicd-production -n cicd-prod rollout status deployment/demo-web
1..30 | ForEach-Object { (Invoke-RestMethod http://localhost:18080/api/whoami).pod } | Group-Object
kubectl --context kind-cicd-production -n cicd-prod get pdb
```

Delete one backend pod, repeat requests during replacement, and confirm all three replicas become Ready again. Resource requests, limits, non-root execution, read-only filesystems, health probes, rolling updates, and disruption budgets are inherited from the base.

## Before real production

Replace kind with a managed or independently operated Kubernetes cluster with independent failure domains and a highly available control plane. Provision infrastructure with reviewed infrastructure-as-code.

Replace the loopback NodePort mapping with a platform LoadBalancer. Add DNS and TLS certificates (for example cert-manager), HTTPS enforcement, and external ingress monitoring before exposing public traffic. HTTP is intentional only for this loopback simulation.

The default kind CNI does not enforce NetworkPolicy. Install a policy-capable CNI and validate default-deny rules plus ingress-to-web, web-to-backend, DNS, and monitoring exceptions before handling production data. This simulation makes no network-isolation claim.

Deploy persistent monitoring, centralized logs, alert routing, and tested cluster/configuration backups. An isolated Prometheus instance in cicd-prod-observe scrapes production backends and ArgoCD and evaluates availability alerts. Its local emptyDir storage is ephemeral and no external alert receiver is configured; replace this with persistent storage and an Alertmanager receiver for real production. The application is stateless; future databases require managed storage, backups, and restore drills. Use an external secret manager and workload identity instead of storing credentials in Git.

Pin and review platform upgrades, scan/sign images and validate provenance, enforce admission policies, restrict administrator access and service accounts, and test disaster recovery. Local replica distribution cannot survive failure of this computer.
