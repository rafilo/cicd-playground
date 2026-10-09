# 前端主页与负载均衡
应用新增英文 PodFlow 主页，显示请求总数、实际观察到的 Pod、平均响应时间、成功率、各 Pod 请求分布与最近 12 次响应。
脚本和页面均不包含中文；中文仅保留在文档中。

## 请求链路
浏览器 → 本机端口转发 → demo-web Service / 入口 Pod → demo ClusterIP Service → 3 个 demo 业务 Pod。
入口与业务使用同一个 Node Alpine 镜像；入口设置 UPSTREAM_URL=http://demo。
每次 API 代理请求使用一个新 TCP 连接，demo Service 的 sessionAffinity=None，由 Kubernetes 数据平面选择后端；不是 JavaScript 轮询 Pod，也不保证请求数严格相等。
web 入口额外 1 个 Pod，请求 25m CPU/48Mi 内存，限制 250m/128Mi。3 个 demo 业务副本保持不变。
入口单副本是本地学习环境的资源取舍，不是生产高可用入口。

## 发布与访问
代码提交触发 CI 构建并发布镜像；发布 PR 将真实 digest 和入口清单一起交付。合并后由 ArgoCD 自动同步。
```powershell
git pull --ff-only origin master
kubectl --context kind-cicd-gitops rollout status deploy/demo -n cicd-demo --timeout=180s
kubectl --context kind-cicd-gitops rollout status deploy/demo-web -n cicd-demo --timeout=180s
kubectl --context kind-cicd-gitops port-forward -n cicd-demo svc/demo-web 8081:80
```
访问 http://localhost:8081 ，点击 Send 30 requests。多次采样可查看不同 Pod；短批次可能没有覆盖全部副本。
请转发 demo-web；直接 port-forward svc/demo 会选中单个 Pod，不能验证 Service 负载均衡。

## 验证
2026-10-09，在临时 cicd-preview 命名空间加载本地测试镜像并部署：
- 3 个业务 Pod + 1 个入口 Pod Ready。
- 60 次真实 Service 请求分布为 20、18、22，全部成功。
- 浏览器执行 30 次请求全部成功，并观察到 3 个后端 Pod。
- 桌面 1440px 与手机 390px 布局检查通过，无页面脚本错误。
- API、静态文件、404/405、源码不可访问、独立 upstream TCP 连接和 502 故障响应测试通过。
- 这些是隔离预览验证；正式 cicd-demo 发布仍以镜像 PR 合并后 ArgoCD 状态为准。
页面计数属于当前浏览器会话，不代表实时集群健康；刷新或 Reset 会清空。
预览截图保存在本机 evidence/frontend-desktop.png 与 frontend-mobile.png（未提交到 Git）。

官方依据：
- https://kubernetes.io/docs/concepts/services-networking/service/
- https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/
