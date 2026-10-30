# Operations and failure drills

## Daily checks

Run scripts/inspect.ps1. Confirm the Node is Ready, three application replicas are Ready, restart counts are normal, Argo is Synced/Healthy, there are no Warning events, and monitoring Targets are up. If disk space is low, inspect Docker Desktop disk usage rather than blindly pruning images belonging to other projects.
The application writes structured access logs to stdout. Use `kubectl logs -n cicd-demo -l app=demo --prefix --tail=100`; after a crash, use `kubectl logs Pod -n cicd-demo --previous`.
Use kubectl describe pod / events to investigate scheduling, image pulls, and probes. Check resources with kubectl top (requires metrics-server) or existing monitoring.

## Lightweight monitoring and alerts

kubectl create namespace cicd-observe
kubectl apply -f ops
kubectl port-forward -n cicd-observe deploy/demo-prometheus 9090:9090
Open localhost:9090/targets and /alerts. DNS discovery scrapes three application Pods through Service/headless Service discovery. Rules cover unreachable backends, fewer than three Ready endpoints, and an unhealthy Argo application.
A 24h/256MB TSDB and emptyDir limit overhead. Restarting can lose history, which is acceptable for this learning environment. No external receiver is configured; alerts appear in the UI by default. Connect Alertmanager and manage webhooks through Secrets when notifications are required. A firing UI alert does not prove notification delivery.
Cluster health is still checked by inspect.ps1; this configuration does not provide complete production node monitoring. The existing monitoring-demo can be reused as needed without changing its configuration.

## Failure recovery

Delete one application Pod: `kubectl delete pod -n cicd-demo -l app=demo --field-selector=metadata.name=<pod-name>`.
The Deployment replaces it automatically. Wait for rollout, then confirm a new UID, three Ready replicas, and working HTTP responses. PDB minAvailable=2 protects eviction/drain, but does not prevent direct deletion or node failure.
A single-node drain being blocked by the PDB is expected. Forced eviction does not demonstrate high availability. The learning application has no database, and its Pods are stateless.
Rolling updates with maxUnavailable=0/maxSurge=1 require capacity for one additional Pod. Failing probes prevent the rollout from proceeding.

## Rollback and restoration

Create a rollback PR by using git revert on the image-update PR's merge commit (a merge commit usually requires -m 1). Review and merge it, then let Argo restore the old digest. Retain old GHCR digests. Self-healing overwrites kubectl rollout undo, so it is not a GitOps rollback method.
Backups: the remote Git repository and an offline mirror are the authoritative application manifests. Export `kubectl get appproject,application -n argocd -o yaml` into backups (ignored by Git), and record the Argo version and image digest.
With a matching Argo CLI version, redirect `argocd admin export -n argocd` to a securely encrypted backup. Backups may contain credentials; encrypt them and restrict access. The password management system is the source of credentials.
Run restoration drills on a new kind cluster: cluster.ps1 → bootstrap.ps1 → recreate repository credentials/imagePullSecret from the password management system → Argo sync → accept.ps1. Restore Argo metadata with a matching version of argocd admin import -n argocd when necessary. There are no application volumes requiring an etcd data backup; any future database needs additional application-consistent backups. Git cannot replace data backups.
A monthly restoration drill is recommended, with a learning-environment RTO target of 30 minutes. This target has not been validated by an actual cross-cluster restoration.

## Common failures

- ImagePullBackOff: check OWNER/zero-filled digests, GHCR package visibility, the Secret namespace, PAT scopes/SSO, and node networking.
- Argo ComparisonError: check the repository URL, main, read-only repository credentials, and Kustomize path; add the repository first for private repositories.
- PermissionDenied: check the AppProject resource allowlist and destination. Do not hide the problem by granting wildcard (*) access.
- PR creation failed: check that GITOPS_PR_TOKEN is set, has Contents/PR write permissions, and is allowed by organization policy.
- PR checks did not start: check the token, Actions policy, and GitHub's Approve workflows button.
- Pending: check resource capacity. Keep probes and limits, and increase Docker's resource allocation.
- Probe failed: check port 8080, paths, application logs, and read-only filesystem compatibility.
- Argo OutOfSync: confirm the PR was merged; polling Git may take several minutes. Do not force an apply from CI.

Limit cleanup to this project's namespaces, after checking for unrelated resources: `kubectl delete namespace cicd-demo cicd-observe`. The Argo installation includes shared CRDs/ClusterRoles; do not blindly delete all Argo CRDs. Understand prune/finalizer behavior before deleting this project's Application. This manifest has no cascading-deletion finalizer.
