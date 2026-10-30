# Frontend homepage and load balancing

The application includes an English PodFlow homepage showing total requests, observed Pods, average response time, success rate, per-Pod request distribution, and the 12 most recent responses.
The scripts, page, and documentation are in English.

## Request path

Browser → local port forward → demo-web Service / entry Pod → demo ClusterIP Service → three demo application Pods.
The entry and backend use the same ASP.NET Core/.NET 10 image; the entry sets UPSTREAM_URL=http://demo.
Each proxied API request uses a new TCP connection. The demo Service has sessionAffinity=None, and the Kubernetes data plane selects the backend. JavaScript does not poll individual Pods, and request counts are not guaranteed to be equal.
The web entry adds one Pod. Both entry and backend Pods request 100m CPU/96Mi memory and have limits of 500m/256Mi. The three demo backend replicas remain unchanged.
A single entry replica reduces resource use in the local learning environment; it is not a highly available production entry point.

## Release and access

Code commits trigger CI to build and publish an image. The release PR delivers the real digest together with the entry manifests. Argo CD syncs automatically after merge.

```powershell
git pull --ff-only origin master
kubectl --context kind-cicd-gitops rollout status deploy/demo -n cicd-demo --timeout=180s
kubectl --context kind-cicd-gitops rollout status deploy/demo-web -n cicd-demo --timeout=180s
kubectl --context kind-cicd-gitops port-forward -n cicd-demo svc/demo-web 8081:80
```
Open http://localhost:8081 and click Send 30 requests. Repeat the sample to observe different Pods; a short batch may not reach every replica.
Forward demo-web. A direct port-forward to svc/demo selects a single Pod and cannot verify Service load balancing.

## Validation

The following is a historical record for the Node version before migration. Publish and verify the .NET version using [the complete CI/CD runbook](dotnet-cicd.md).
On 2026-10-09, a local test image was loaded and deployed in the temporary cicd-preview namespace:

- Three application Pods and one entry Pod were Ready.
- All 60 real Service requests succeeded, with a distribution of 20, 18, and 22.
- All 30 browser requests succeeded, and three backend Pods were observed.
- Desktop 1440px and mobile 390px layout checks passed, with no page script errors.
- Tests passed for the API, static files, 404/405 responses, inaccessible source files, separate upstream TCP connections, and 502 failure responses.
- These checks used an isolated preview. The actual cicd-demo release must be assessed using the Argo CD state after the image PR is merged.

Page counters belong to the current browser session and do not represent live cluster health; refreshing or clicking Reset clears them.
Preview screenshots are stored locally as evidence/frontend-desktop.png and frontend-mobile.png (not committed to Git).

Official references:

- https://kubernetes.io/docs/concepts/services-networking/service/
- https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/
