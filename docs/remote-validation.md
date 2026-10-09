# 远程 CI / GitOps 发布验证（2026-10-09）
仓库：https://github.com/rafilo/cicd-playground ，默认分支 master。

已完成：
- 推送项目配置，代码提交 b279e0ae141375734af1fd29707bf6a350717c34。
- [首次 CI](https://github.com/rafilo/cicd-playground/actions/runs/37895316420) 测试、构建、GHCR 发布与 GitOps 审查分支推送成功。
- 镜像 ghcr.io/rafilo/cicd-playground@sha256:d2129e56e3ec25b692e111400b611527be05f37624649418a3bcc1386b8f582a。
- 用临时 image-pull-check Pod 实际拉取上述 digest 并运行 node --version，输出 v24.21.0，Pod Succeeded，随后已删除。未配置 imagePullSecret 亦可拉取。
- [发布 PR #1](https://github.com/rafilo/cicd-playground/pull/1) 已创建，只改变 dev 镜像摘要；test 与 GitGuardian 检查通过，publish 在 PR 事件下正确跳过。
- 当前运行仍是 local-v2，3 个业务 Pod Ready。ArgoCD 组件 Ready；实际 Application 尚未引导。

待完成：
- 用户审查并合并 PR #1。
- 拉取合并结果，执行下面引导与验收。尚未声称 Application Synced/Healthy 或完整 GitOps CD 已通过。

```powershell
Set-Location C:\Users\AAA\Desktop\cicd-gitops
git pull --ff-only origin master
.\scripts\bootstrap.ps1 -RepoUrl https://github.com/rafilo/cicd-playground.git
kubectl wait --for=jsonpath='{.status.sync.status}'=Synced application/cicd-demo -n argocd --timeout=180s
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy application/cicd-demo -n argocd --timeout=180s
.\scripts\accept.ps1
kubectl get deploy demo -n cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl port-forward -n cicd-demo svc/demo 8080:80
# 另一终端访问 http://localhost:8080/，version 应为 b279e0ae141375734af1fd29707bf6a350717c34
```

凭据和权限：
未配置 GITOPS_PR_TOKEN。CI 通过临时 GITHUB_TOKEN 推送审查分支，本次使用现有 GitHub CLI 登录创建 PR。
启用仓库 Actions 创建/批准 PR 的设置变更曾被自动审批审查拒绝，未执行；保持 default_workflow_permissions=read、can_approve_pull_request_reviews=false。采用上述流程继续完成不依赖此设置的工作。
日后需要全自动创建 PR，可配置仅授权此仓库 Contents/PR write 的专用 token 或 GitHub App；不应复制本机 CLI OAuth token。
