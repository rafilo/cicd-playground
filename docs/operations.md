# 运维与故障演练
## 每日巡检
运行 scripts/inspect.ps1；确认 Node Ready、业务 Ready 数 3、Restart 无异常、Argo Synced/Healthy、无 Warning events、监控 Targets up。磁盘不足时检查 Docker Desktop 磁盘，不盲目 prune 用户其他镜像。
应用输出结构化访问日志到 stdout；kubectl logs -n cicd-demo -l app=demo --prefix --tail=100，崩溃用 kubectl logs Pod -n cicd-demo --previous。
kubectl describe pod / events 定位调度、拉取、探针；资源通过 kubectl top（需要 metrics-server）或现有监控查看。

## 轻量监控和告警
kubectl create namespace cicd-observe
kubectl apply -f ops
kubectl port-forward -n cicd-observe deploy/demo-prometheus 9090:9090
访问 localhost:9090/targets 与 /alerts。DNS discovery 抓取 3 个业务 Pod，Service/headless 服务提供发现；业务不可达、Ready endpoint 不足 3、Argo 应用不健康规则已配置。
24h/256MB TSDB 与 emptyDir 控制开销，重启会丢历史，学习环境接受。没有外部收件人，默认告警在 UI 展示；需要通知时接入 Alertmanager 并在 Secret 管理 webhook，不能把 UI firing 当作通知已送达。
集群健康仍由 inspect.ps1 检查；此配置没有冒充完整生产节点监控。现有 monitoring-demo 可按需复用，不修改其配置。

## 故障恢复
删除一个业务 Pod：kubectl delete pod -n cicd-demo -l app=demo --field-selector=metadata.name=指定Pod
Deployment 自动补回；等待 rollout，确认新 UID、3 Ready 和 HTTP。PDB minAvailable=2 保护 eviction/drain，不阻止直接 delete 或节点故障。
单节点 drain 受 PDB 阻挡是预期，不能强制驱逐宣称高可用。学习项目无数据库，Pod 全为无状态。
滚动更新 maxUnavailable=0/maxSurge=1 需要额外一个 Pod 的容量；探针失败会阻止升级继续。

## 回滚与恢复
以 git revert 镜像更新 PR 的 merge commit 提交回滚 PR（merge commit 通常加 -m 1），审查合并，Argo 自动恢复旧 digest。保留 GHCR 旧 digest；kubectl rollout undo 会被 selfHeal 覆盖，不作为 GitOps 回滚。
备份：Git 远程和离线 mirror 是业务清单权威；kubectl get appproject,application -n argocd -o yaml 导出到 backups（忽略 Git）；记录 Argo 版本与镜像 digest。
Argo CLI 同版本时 argocd admin export -n argocd > 安全加密备份；备份可能含凭据，应加密存储并限权限。凭据原始来源为密码管理系统。
恢复演练在新的 kind 集群：cluster.ps1 → bootstrap.ps1 → 从密码管理系统重建 repo/imagePullSecret → Argo 同步 → accept.ps1。Argo 元数据需要时用同版本 argocd admin import -n argocd。无业务卷无需 etcd 数据备份；未来引入数据库必须额外做应用一致性备份，Git 不能代替数据备份。
建议每月演练恢复，目标学习环境 RTO 30 分钟；此目标未通过实际跨集群恢复验证。

## 常见故障
- ImagePullBackOff：检查 OWNER/全零 digest、GHCR 包可见性、Secret namespace、PAT scopes/SSO 和节点网络。
- Argo ComparisonError：仓库 URL、main、只读仓库凭据、Kustomize path；私有仓库需要先添加 Repo。
- PermissionDenied：AppProject 资源 whitelist 或目标不匹配。不要使用 * 扩权掩盖问题。
- PR 创建失败：GITOPS_PR_TOKEN 是否设置、有 Contents/PR write、组织策略是否允许。
- PR checks 未启动：检查 token、Actions 策略以及 GitHub 的 Approve workflows 按钮。
- Pending：资源不足；保留探针和限制，增加 Docker 分配资源。
- Probe failed：8080、路径、应用日志、只读文件系统是否兼容。
- Argo OutOfSync：确认 PR 已合并，轮询 Git 可能需数分钟；不要由 CI 强制 apply。
清理仅针对本项目 namespace，并先确认无其他资源：kubectl delete namespace cicd-demo cicd-observe；Argo 安装含共享 CRD/ClusterRole，禁止盲删全部 Argo CRD。删除本项目 Application 前了解 prune/finalizer 行为，本清单无级联删除 finalizer。
