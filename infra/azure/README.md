# Azure AKS Terraform 模拟项目

本示例将需求中的 ALS 暂按 **AKS** 理解。对应现有 ASP.NET Core/.NET 10 demo、3 个后端副本及 Web 代理；Azure 示例独立于 kind 和原有 Argo CD 配置。代码可用于学习和准备真实部署，但没有运行 Azure plan/apply，也没有创建付费资源。完整发布流程见 [.NET CI/CD 指南](../../docs/dotnet-cicd.md)。

## 目录与资源

| 路径 | 职责 |
| --- | --- |
| `platform/network.tf` | VNet、AKS/数据库/Private Endpoint 子网、数据库私有 DNS |
| `platform/aks.tf` | 私有 AKS、Entra RBAC、自动扩缩容、升级、Log Analytics、审计 |
| `platform/database.tf` | PostgreSQL 16、独立 appdb、TLS、14 天备份、生产环境 HA |
| `platform/security.tf` | 私有 Key Vault、RBAC、标签强制策略、Pod 安全基线审计 |
| `application/main.tf` | 复用现有 `k8s/base`，替换为真实 GHCR digest 并部署应用 |
| `bootstrap/namespace.yaml` | 平台管理员预创建受 Pod Security 限制的命名空间 |
| `azure-pipelines.terraform.yml`（仓库根目录） | 单独的无凭据静态校验流水线 |

`platform` 与 `application` 是两个独立 Terraform root module，分别管理状态。platform 内按能力分文件；不是每个 `.tf` 文件都是 child module。

```text
VNet 10.40.0.0/16
├── AKS subnet → 私有 AKS API + 应用 Pod
├── PostgreSQL delegated subnet → PostgreSQL / appdb
└── Private Endpoint subnet → Key Vault
                 ↓
       Private DNS + Log Analytics

浏览器 → kubectl port-forward → demo-web → demo Service → 3 个 demo Pod
```

保留项目已有的公共 GHCR 镜像来源，因此不创建未使用的 ACR。应用通过 port-forward 访问，没有公网入口；真实对外服务需要另行配置域名、TLS、Ingress/Gateway 和访问策略。

## 权限与合规设计

- AKS 禁用本地账户，使用 Entra + Azure RBAC。平台管理员组有 AKS Cluster Admin；应用部署身份只有 `cicd-azure` 的 RBAC Writer，并有获取用户 kubeconfig 的 Cluster User Role。
- AKS 控制面身份只在 AKS 子网获得 Network Contributor。集群启用 OIDC/Workload Identity，但没有为当前无数据库应用授予读取数据库管理员密码的权限。
- Key Vault 关闭公网入口、开启 RBAC、90 天软删除和清除保护。Terraform 执行身份获得该 Vault 的 Secrets Officer 用于写入初始密码；持续运行阶段可通过单独的凭据引导流程收窄权限。
- Azure Policy 拒绝缺失规定标签的新资源；Kubernetes 内置 Pod 安全基线采用 `audit`，不把审计模式描述为阻断。命名空间 Pod Security `restricted` 则实际执行准入限制。
- AKS、数据库、Key Vault 的诊断日志进入 Log Analytics，保留 30 天。没有预设法规认证；实际合规还需按组织要求配置更长保留、归档、告警、例外审批和审计证据。
- PostgreSQL 仅私网、强制 TLS、14 天备份，`prevent_destroy` 阻止意外销毁；prod 开启跨可用区 HA，需要目标区域和配额支持。
- 应用沿用现有非 root、只读根文件系统、禁止提权、删除 capabilities、健康检查、资源限制与 PDB。

当前并未设置 Pod 默认拒绝 NetworkPolicy、出站防火墙、SIEM 告警或数据库细粒度角色；不是完整生产安全基线。

## 部署前提

1. Terraform >= 1.9，Azure CLI，kubectl，kubelogin；AzureRM 固定在 4.59.x，Kubernetes provider 固定在 2.38.x。升级需要重新验证。两个 root module 已包含本次 init 生成的 `.terraform.lock.hcl`。
2. 已有 Azure 订阅、Entra 管理组、应用部署身份；填的是 object ID，不能把 client/application ID 当作 object ID。
3. 预注册所需 Resource Provider，准备区域 VM/数据库配额。私有集群、数据库、监控会产生费用。
4. Terraform runner 必须能到达 VNet、解析私有 AKS 和 Key Vault DNS。新建 VNet 可通过预先规划的 hub peering/VPN 和 DNS 转发接入，也可先在可达的自托管 runner 上执行。普通公网托管 agent 无法完成完整部署。
5. 基础设施身份需要创建资源的权限；角色分配还需要相应 RBAC 管理权限；自定义策略定义需要订阅级策略管理权限。不要把这些权限授予应用流水线。

## 第一步：基础设施

```powershell
cd infra/azure/platform
Copy-Item terraform.tfvars.example terraform.tfvars
# 编辑真实 subscription_id、管理组和应用部署身份 object ID。
az login
terraform init
terraform fmt -check
terraform validate
terraform plan -out=platform.tfplan
# 审查 plan 后，按需执行，真实资源会计费：
terraform apply platform.tfplan
terraform output
```

Key Vault 角色分配可能需要传播时间。若首次 secret 写入返回授权错误，等待授权生效后重新 plan/apply。若返回连接超时，应先检查 runner 的网络与私有 DNS。

本地状态仅适合此模拟。密码即便标记 sensitive 或存入 Key Vault，仍会存在 Terraform state 与 plan 中，禁止上传到 Git 或通用流水线制品。真实 CI 使用独立预创建的 Azure Storage backend、Entra/OIDC 认证、容器级 Storage Blob Data Contributor、状态锁及受控网络；platform 和 application 使用不同 state key。不要从 application 读取包含管理员凭据的 platform state。

## 第二步：平台管理员引导

在仓库根目录，由管理员执行：

```powershell
az aks get-credentials --resource-group rg-cicdlearn-dev --name aks-cicdlearn-dev --context aks-cicdlearn-dev
kubelogin convert-kubeconfig -l azurecli
kubectl --context aks-cicdlearn-dev apply -f infra/azure/bootstrap/namespace.yaml
```

显式使用 AKS context，避免操作原有 kind 集群。角色分配传播完成后，应用部署身份使用自己的登录凭据获取该 context。

## 第三步：部署已有应用

```powershell
cd infra/azure/application
Copy-Item terraform.tfvars.example terraform.tfvars
# 填写 AKS context 和现有 k8s/overlays/dev/kustomization.yaml 的真实公开镜像 digest。
terraform init
terraform validate
terraform plan -out=application.tfplan
terraform apply application.tfplan
kubectl --context aks-cicdlearn-dev -n cicd-azure rollout status deployment/demo
kubectl --context aks-cicdlearn-dev -n cicd-azure rollout status deployment/demo-web
kubectl --context aks-cicdlearn-dev -n cicd-azure port-forward svc/demo-web 8081:80
```

打开 http://localhost:8081。镜像必须公开可拉取；此示例不创建 GHCR 私有拉取凭据。后续更新应用时修改 image digest，重新 plan/apply。

应用 Terraform 会在 plan 时连接已有 AKS，因此不能和创建 AKS 放在首次同一个 apply。Kubernetes manifest 管理不会替代 rollout 检查。

## 与现有 GitOps/CI/CD 的关系

已有 CI 和 Argo CD 保持原流程。新增 Terraform 校验流水线不登录 Azure、不生成真实 plan、不 apply。真实交付可按以下阶段扩展：

```text
PR → fmt/validate/security scan → OIDC 身份的 platform plan
   → 受保护环境审批 → platform apply
   → 管理员引导 namespace → application plan/apply → rollout 验证
```

实际 plan/apply 需要接入服务连接、受控状态存储及 VNet 自托管 agent。仓库中的现有模拟 Azure CD 不会自动部署本目录。

此 AKS 演示由 Terraform 管理应用；原来的 kind 应用仍由 Argo CD 管理。若 AKS 也改用 Argo CD，先规划资源所有权迁移、备份状态并移除 Terraform 对应用资源的管理，再让 Argo CD 接管；不要让二者管理同一 Deployment。

## 数据库扩展与清理

现有 `app/Program.cs` 没有数据库驱动和 SQL 逻辑。此例只创建数据库，不宣称应用已连接。后续需创建独立最小权限 DB 用户、实现 TLS 数据库连接与迁移、通过 Workload Identity + Key Vault CSI 提供应用专用凭据；不能使用管理员密码作为应用密码。

先删除 application 资源，再处理 platform。数据库默认 `prevent_destroy`，所以 `terraform destroy` 会被阻止；确需删除时先备份并明确修改该保护，再审查销毁计划。Key Vault 清除保护仍会保留软删除记录；重建时可能需要恢复 Vault 或更换名称。

## 官方参考

- [AKS Terraform resource](https://registry.terraform.io/providers/hashicorp/azurerm/4.59.0/docs/resources/kubernetes_cluster)
- [Azure Policy for AKS](https://learn.microsoft.com/azure/aks/use-azure-policy)
- [PostgreSQL Terraform deployment](https://learn.microsoft.com/en-us/azure/developer/terraform/deploy-postgresql-flexible-server-database)
- [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)
