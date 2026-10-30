# Application security scanning

`.github/workflows/ci.yaml` uses Trivy to scan the application for dependency vulnerabilities and exposed credentials. Scanning runs for the existing PR, master code-push, and manual triggers. No additional secret or GitHub Code Security subscription is required.

## Scan scope and release gates

| Location | Scan target | Behavior on failure |
| --- | --- | --- |
| `security` job | NuGet `packages.lock.json` in `app/` (including transitive dependencies) and credentials in application files | Blocks `probes` and `publish` |
| `probes` job | The `podflow:ci` image built in this run: OS packages, .NET dependencies, and credentials | Blocks container/Pod validation and `publish` |
| `publish` job | The exact published `image@sha256:…` in GHCR: OS packages, .NET dependencies, and credentials are checked again | Blocks GitOps manifest updates, deployment PR creation, and deployment review branch pushes |

Source scanning covers `app/`; it does not cover `test/`, infrastructure manifests, or the full Git history. Scanning uses known vulnerability databases and credential detection rules. It does not include C#/JavaScript semantic code analysis (SAST) or live penetration testing (DAST).

Scans return a nonzero exit code for **HIGH / CRITICAL** findings. Unfixed vulnerabilities also block progress, and `continue-on-error` is not enabled. Scanner installation, database download, and scan execution failures also fail the corresponding job. Low/Medium findings are outside the current blocking threshold. To restrict PR merges, make `Application dependency and secret scan` and `Container security and real Pod probes` required checks in GitHub branch protection.

Test and release builds may resolve different base images, so the published digest is scanned again. If the second image scan fails, the image already exists in GHCR but cannot proceed to GitOps deployment updates. Fix the issue and rerun the pipeline before reviewing the deployment PR.

## Reports and remediation

Download the `trivy-app`, `trivy-test-image`, or `trivy-release-image` JSON report from **Artifacts** in the corresponding GitHub Actions run. Reports are retained for 14 days. Upload steps use `always()` and still attempt to upload after a scan finds vulnerabilities. If the scanner fails before generating a report, inspect the failed step's logs. Reports are provided only through Actions artifacts and are not automatically uploaded to the GitHub Security page.

- NuGet vulnerabilities: upgrade the affected direct or transitive dependencies, regenerate and commit the lockfiles, and rerun CI.
- OS package or shared .NET runtime vulnerabilities: update the base image used by the Dockerfile, rebuild, and scan again. Findings are not automatically ignored when no patch is available.
- Exposed credentials: revoke/rotate the credentials and remove them from application files. Use a credential store such as GitHub Secrets or Kubernetes Secrets. Deleting file contents does not make leaked credentials safe again.

The Action is pinned to a full commit SHA (v0.36.0), and the scanner is pinned to `v0.76.1`; the vulnerability database continues to update online. When upgrading, review official release notes, Action commits, and compatibility. PR scans use the workflow's default `contents: read` permission, without the publish job's registry/PR write permissions.

References: [Trivy GitHub Action](https://github.com/aquasecurity/trivy-action/tree/ed142fd0673e97e23eac54620cfb913e5ce36c25), [.NET scanning support](https://trivy.dev/docs/latest/coverage/language/dotnet/), [secret scanning](https://www.trivy.dev/docs/latest/guide/scanner/secret/).
