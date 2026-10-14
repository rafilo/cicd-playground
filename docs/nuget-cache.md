# .NET 单元测试与 NuGet 缓存

`test/UnitTests/PodFlow.UnitTests.csproj` 使用 xUnit。测试模拟后端 JSON，调用应用实际使用的 `IdentityResponseValidator`，检查正常身份以及缺少字段、字段类型错误、null 和非对象响应。无需启动 Kubernetes。

```powershell
dotnet restore test/UnitTests/PodFlow.UnitTests.csproj --configfile NuGet.Config --locked-mode
dotnet test test/UnitTests/PodFlow.UnitTests.csproj --no-restore
```

CI `.github/workflows/ci.yaml` 的 `test` job：

1. 设置 `NUGET_PACKAGES=${{ github.workspace }}/.nuget/packages`。
2. 使用 `actions/cache@v4` 恢复并在 job 成功后保存包目录。
3. 缓存键包含 OS、架构，以及 SDK 配置、NuGet.Config、csproj、packages.lock.json 和共享依赖 props/targets 的哈希；不包含普通 C# 源文件。
4. 依赖配置不变且缓存仍存在时，命中同一个缓存键。`dotnet restore --locked-mode` 复用已缓存的包，同时为当前工作目录生成必要的 `obj/project.assets.json`。
5. 单元测试使用 `dotnet test --no-restore`，集成测试先 build `--no-restore` 再 run `--no-build`，不会再次触发包恢复。
6. 输出缓存命中状态，并上传单元测试 TRX 结果。

不跳过 restore：缓存包目录不包含工作目录专属的 assets 文件。缓存未命中、被 GitHub 淘汰、跨分支不可见或包缺失时，restore 正常从 NuGet 获取依赖。缓存是加速机制，不能承诺每次运行都必定命中。命中后 NuGet 仍可能请求安全审计元数据；这不代表重新下载包。

所有项目通过 `Directory.Build.props` 生成并提交锁文件。修改 PackageReference 后，本地运行不带 `--locked-mode` 的 restore 更新锁文件，然后同时提交 csproj 和 lock 文件。CI 的 locked mode 会拒绝依赖配置与锁文件不一致的提交。

当前 xUnit、测试 SDK 和 runner 的外部依赖使缓存有实际内容。应用本身仍无外部 NuGet 包。Docker 的 restore 在单独的镜像构建环境中，GitHub job 的 NuGet 缓存不会自动共享到 Docker；此配置针对 .NET 测试依赖缓存。

本机验证采用所有 packageSources 均清空的临时配置，配合已有包目录执行强制 locked restore；仅这次离线验证关闭需要网络的 NuGet audit。CI 没有关闭 NuGet audit。

2026-10-14 验证结果：无下载源的 locked restore 成功，8 个 xUnit 测试全部通过，原有 HTTP 集成测试、镜像更新测试及配置检查通过。测试采用 Debug 输出，避免覆盖正在运行的 Release 应用。未运行远端 GitHub Actions，因此没有声称远端已产生缓存命中记录。

参考：[GitHub 依赖缓存](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)。
