# .NET migration verification — 2026-10-14

Validated locally with the checksum-verified Microsoft .NET SDK 10.0.402 installed in the ignored `tools/dotnet` directory.

| Check | Result |
| --- | --- |
| Restore application and HTTP test runner | Passed |
| Release build with warnings as errors | Passed, zero warnings/errors |
| C# real HTTP integration checks | Passed: frontend/assets, probes, identity, metrics, route isolation and security headers |
| Reverse proxy checks | Passed: four distinct upstream TCP connections, unavailable upstream → 502 |
| Invalid and oversized upstream response checks | Passed: both return 502 |
| Release publish (`UseAppHost=false`) | Passed; DLL and all three frontend assets present |
| Node image-update test | Passed |
| Repository configuration contracts | Passed |
| Frontend JavaScript syntax | Passed |
| Kustomize dev/prod rendering | Passed |
| PowerShell release verifier syntax | Passed |

Docker Desktop's engine was unavailable locally, so Linux image build, read-only container startup, and Kubernetes rollout were not executed locally. The GitHub Actions workflow now includes Linux image build and read-only/non-root HTTP smoke checks; no remote workflow run is claimed by this record.

No Git commit/push, image publication, cluster deployment, Azure plan/apply or production promotion was performed. Existing overlay digests still refer to the earlier published application and must be updated by the release process. See [the complete CI/CD runbook](dotnet-cicd.md).
