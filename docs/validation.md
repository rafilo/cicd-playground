# Validation record

2026-10-09, project path C:\Users\AAA\Desktop\cicd-gitops.

| Check | Result |
|---|---|
| Application HTTP behavior, readiness/liveness, 404, metrics | Passed |
| Image digest updates and invalid input rejection | Passed; tests did not modify the source manifests |
| npm test | Two tests passed |
| Configuration contracts, PowerShell syntax | Passed |
| Actions actionlint v1.7.7 | Passed (static checks, not a real GitHub run) |
| Docker build | Passed; base image pinned by digest |
| Kustomize dev/local rendering | Passed |
| Service/Deployment/PDB server-side dry-run | Passed |
| AppProject/Application CRD server-side dry-run | Passed; no placeholder Application was created |
| Local application deployment | All three Pods 1/1 Ready, zero restarts |
| HTTP Service | Returned a Chinese-language message and version=local-v2 |
| Automatic recovery after deleting one Pod | Passed; Deployment restored three Ready replicas |
| Rolling update | Passed, maxUnavailable=0/maxSurge=1 |
| ArgoCD v3.5.2 components | All seven components 1/1 Ready, resource limits configured |
| Prometheus | One Pod Ready; all three application targets and Argo metrics up |
| promtool | Configuration and three alert rules passed |
| Real GitHub Actions run / GHCR publication / update PR | Not verified: no remote repository or credentials were available |
| ArgoCD Application Synced/Healthy | Not verified: the actual Application had not been bootstrapped |
| End-to-end code change through GitOps CD | Not verified |
| New kind creation / cross-cluster backup restoration | Scripts and runbooks provided, not executed; an existing cluster was reused |

The local overlay was validated manually, not through a GitOps release. OWNER and the zero-filled digest in dev were configuration placeholders; bootstrap rejects placeholder digests. Full acceptance with scripts/accept.ps1 should fail when the Application is absent and must not be reported as passed.

Evidence without Secrets is stored in evidence/business-pods.json, argocd-pods.json, and monitoring-targets.json (kept locally and ignored by Git).
Docker 29.6.1, Kubernetes/kubectl v1.36.1, Kustomize v5.8.1, host Node v24.18.0, container Node v24.21.0.
Active namespaces: cicd-demo, argocd, cicd-observe. Other application namespaces were not modified.
