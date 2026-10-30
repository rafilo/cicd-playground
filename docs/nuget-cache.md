# .NET unit tests and NuGet caching

`test/UnitTests/PodFlow.UnitTests.csproj` uses xUnit. Tests simulate backend JSON and call the same `IdentityResponseValidator` used by the application. They check valid identities, missing fields, incorrect field types, null values, and non-object responses. Kubernetes is not required.

```powershell
dotnet restore test/UnitTests/PodFlow.UnitTests.csproj --configfile NuGet.Config --locked-mode
dotnet test test/UnitTests/PodFlow.UnitTests.csproj --no-restore
```

The `test` job in CI `.github/workflows/ci.yaml`:

1. Sets `NUGET_PACKAGES=${{ github.workspace }}/.nuget/packages`.
2. Uses `actions/cache@v4` to restore the package directory and save it after a successful job.
3. Builds a cache key from the OS, architecture, and hashes of SDK configuration, NuGet.Config, csproj, packages.lock.json, and shared dependency props/targets. Ordinary C# source files are not part of the key.
4. Hits the same key when dependency configuration is unchanged and the cache still exists. `dotnet restore --locked-mode` reuses cached packages while generating the required `obj/project.assets.json` for the current working directory.
5. Runs unit tests with `dotnet test --no-restore`; integration tests build with `--no-restore` and run with `--no-build`, avoiding another package restore.
6. Logs cache-hit status and uploads unit test TRX results.

Do not skip restore: the cached package directory does not include workspace-specific assets files. If the cache misses, is evicted by GitHub, is unavailable across branches, or lacks packages, restore retrieves dependencies from NuGet as usual. Caching is an optimization and does not guarantee a hit on every run. NuGet may still request security audit metadata after a cache hit; that does not mean packages are being downloaded again.

All projects generate and commit lockfiles through `Directory.Build.props`. After changing PackageReference, run restore locally without `--locked-mode` to update the lockfiles, then commit both the csproj and lockfiles. CI locked mode rejects commits whose dependency configuration and lockfiles disagree.

External dependencies for xUnit, the test SDK, and the runner give the cache actual content. The application itself still has no external NuGet packages. Docker restore runs in a separate image-build environment; the GitHub job's NuGet cache is not automatically shared with Docker. This configuration caches .NET test dependencies.

Local validation used a temporary configuration with all packageSources cleared and an existing package directory to run a forced locked restore. Network-dependent NuGet audit was disabled only for that offline validation. CI does not disable NuGet audit.

Validation on 2026-10-14: locked restore succeeded without download sources, all eight xUnit tests passed, and the existing HTTP integration tests, image-update test, and configuration checks passed. Tests used Debug output to avoid overwriting the running Release application. Remote GitHub Actions was not run, so this record does not claim a remote cache hit.

Reference: [GitHub dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
