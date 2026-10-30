# Remote CI / GitOps release validation (2026-10-09)

Repository: https://github.com/rafilo/cicd-playground; default branch: master.

Completed:

- Pushed the project configuration in code commit b279e0ae141375734af1fd29707bf6a350717c34.
- [The first CI run](https://github.com/rafilo/cicd-playground/actions/runs/37895316420) successfully tested, built, published to GHCR, and pushed the GitOps review branch.
- Image: ghcr.io/rafilo/cicd-playground@sha256:d2129e56e3ec25b692e111400b611527be05f37624649418a3bcc1386b8f582a.
- A temporary image-pull-check Pod actually pulled that digest and ran node --version, producing v24.21.0. The Pod Succeeded and was then deleted. Pulling worked without an imagePullSecret.
- [Release PR #1](https://github.com/rafilo/cicd-playground/pull/1) was created and changed only the dev image digest. The test and GitGuardian checks passed, and publish was correctly skipped for the PR event.
- The running release was still local-v2, with three application Pods Ready. ArgoCD components were Ready; the actual Application had not been bootstrapped.

Remaining at the time of this record:

- User review and merge of PR #1.
- Pull the merge result, then run bootstrap and acceptance below. This record does not claim Application Synced/Healthy or successful end-to-end GitOps CD.

```powershell
Set-Location C:\Users\AAA\Desktop\cicd-gitops
git pull --ff-only origin master
.\scripts\bootstrap.ps1 -RepoUrl https://github.com/rafilo/cicd-playground.git
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/cicd-demo -n argocd --timeout=180s
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/cicd-demo -n argocd --timeout=180s
.\scripts\accept.ps1
kubectl get deploy demo -n cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl port-forward -n cicd-demo svc/demo 8080:80
# Open http://localhost:8080/ from another terminal; version should be b279e0ae141375734af1fd29707bf6a350717c34
```

Credentials and permissions:
GITOPS_PR_TOKEN was not configured. CI pushed the review branch using the temporary GITHUB_TOKEN; the existing GitHub CLI login was used to create the PR.
Automatic approval review rejected a repository settings change to allow Actions to create/approve PRs, so that change was not executed. Settings remained default_workflow_permissions=read and can_approve_pull_request_reviews=false. The workflow above allowed work that did not depend on that setting to continue.
For automatic PR creation later, configure a dedicated token or GitHub App scoped to this repository with Contents/PR write permissions. Do not copy the local CLI OAuth token.
