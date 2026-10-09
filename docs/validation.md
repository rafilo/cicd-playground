# 实测记录
2026-10-09，项目路径 C:\Users\AAA\Desktop\cicd-gitops。

| 项目 | 结果 |
|---|---|
| HTTP 业务、readiness/liveness、404、指标 | 通过 |
| 镜像 digest 更新及无效输入拒绝 | 通过，源清单不受测试修改 |
| npm test | 2 个测试通过 |
| 配置契约、PowerShell 语法 | 通过 |
| Actions actionlint v1.7.7 | 通过（静态检查，不代表 GitHub 实跑） |
| Docker 构建 | 通过，基础镜像固定摘要 |
| Kustomize dev/local 渲染 | 通过 |
| Service/Deployment/PDB 服务端 dry-run | 通过 |
| AppProject/Application CRD 服务端 dry-run | 通过，未创建占位 Application |
| 本地业务部署 | 3 个 Pod 均 1/1 Ready，0 restarts |
| HTTP Service | 返回中文消息、version=local-v2 |
| 删除一个 Pod 自动恢复 | 通过，Deployment 补回 3 Ready |
| 滚动更新 | 通过，maxUnavailable=0/maxSurge=1 |
| ArgoCD v3.5.2 组件 | 7 个组件全部 1/1 Ready，已配置资源限制 |
| Prometheus | 1 Pod Ready，3 业务 targets + Argo metrics 均 up |
| promtool | 配置通过，3 条告警规则通过 |
| GitHub Actions 实跑 / GHCR 发布 / 更新 PR | 未验证：没有远程仓库及凭据 |
| ArgoCD Application Synced/Healthy | 未验证：真实 Application 尚未引导 |
| 代码变更到 GitOps CD 全链路 | 未验证 |
| 新 kind 创建 / 备份跨集群恢复 | 提供脚本和手册，未实跑；当前复用已有集群 |

本地 overlay 是手工运行验证，不是 GitOps 发布。dev 的 OWNER 与全零 digest 为待配置项，bootstrap 会拒绝占位 digest。完整验收 scripts/accept.ps1 对当前缺少 Application 的状态应失败，不能当作通过。

无 Secret 的实测证据位于 evidence/business-pods.json、argocd-pods.json、monitoring-targets.json（本地保留，已忽略 Git）。
Docker 29.6.1，Kubernetes/kubectl v1.36.1，Kustomize v5.8.1，主机 Node v24.18.0，容器 Node v24.21.0。
运行中命名空间：cicd-demo、argocd、cicd-observe；未修改其他业务命名空间。
