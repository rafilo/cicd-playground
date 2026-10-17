#!/usr/bin/env bash
set -euo pipefail
image="${1:?Image is required}"
expected_version="${2:?Expected version is required}"
cluster=podflow-ci
context=kind-$cluster
work=$(mktemp -d)
forward_pid=
cleanup() {
  status=$?
  trap - EXIT
  kubectl --context "$context" -n cicd-demo get pods -o wide || true
  kubectl --context "$context" -n cicd-demo get events --sort-by=.lastTimestamp || true
  kubectl --context "$context" -n cicd-demo logs -l app=demo --all-containers --tail=80 || true
  kubectl --context "$context" -n cicd-demo logs -l app=demo-web --all-containers --tail=80 || true
  if [[ -n "$forward_pid" ]]; then kill "$forward_pid" 2>/dev/null || true; fi
  kind delete cluster --name "$cluster" || true
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
curl -fsSLo "$work/kind" https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
curl -fsSLo "$work/kind.sha256sum" https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64.sha256sum
(cd "$work" && sed 's/kind-linux-amd64/kind/' kind.sha256sum | sha256sum --check)
chmod +x "$work/kind"
export PATH="$work:$PATH"
kind create cluster --name "$cluster" --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed --wait 180s
kind load docker-image "$image" --name "$cluster"
# Copy manifests so CI can override the image without modifying Git-managed environments.
cp -R k8s "$work/k8s"
(cd "$work/k8s/overlays/dev" && printf '\n' >> kustomization.yaml)
python3 - "$work/k8s/overlays/dev/kustomization.yaml" "$image" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text, count = re.subn(r"    newName: .*\n    digest: .*", "    newName: " + sys.argv[2].rsplit(":", 1)[0] + "\n    newTag: " + sys.argv[2].rsplit(":", 1)[1], text)
assert count == 1, "Expected exactly one development image override"
path.write_text(text)
PY
kubectl --context "$context" create namespace cicd-demo
kubectl --context "$context" apply -k "$work/k8s/overlays/dev"
kubectl --context "$context" -n cicd-demo rollout status deployment/demo --timeout=180s
kubectl --context "$context" -n cicd-demo rollout status deployment/demo-web --timeout=180s
# Allow repeated kubelet liveness checks, not just initial readiness.
sleep 25
kubectl --context "$context" -n cicd-demo get pods -o json > "$work/pods.json"
python3 - "$work/pods.json" "$image" <<'PY'
import json, sys
pods = json.load(open(sys.argv[1]))["items"]
assert len(pods) == 4, "Expected three backend Pods and one Web Pod"
for pod in pods:
    spec = pod["spec"]["containers"][0]
    assert spec["image"] == sys.argv[2]
    assert spec["readinessProbe"]["httpGet"]["path"] == "/readyz"
    assert spec["livenessProbe"]["httpGet"]["path"] == "/healthz"
    assert any(c["type"] == "Ready" and c["status"] == "True" for c in pod["status"]["conditions"])
    assert all(c["ready"] and c["restartCount"] == 0 for c in pod["status"]["containerStatuses"])
print("All Pods are Ready with zero restarts after repeated liveness checks.")
PY
kubectl --context "$context" -n cicd-demo port-forward service/demo-web 18082:80 > "$work/forward.log" 2>&1 &
forward_pid=$!
for attempt in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:18082/readyz > "$work/ready.json"; then break; fi
  sleep 1
done
curl -fsS --max-time 5 http://127.0.0.1:18082/readyz > "$work/ready.json"
curl -fsS --max-time 5 http://127.0.0.1:18082/healthz > "$work/health.json"
curl -fsS --max-time 5 http://127.0.0.1:18082/metrics > "$work/metrics.txt"
curl -fsS --max-time 5 http://127.0.0.1:18082/api/whoami > "$work/identity.json"
python3 - "$work" "$expected_version" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for name in ("ready", "health"):
    assert json.loads((root / (name + ".json")).read_text())["status"] == "ok"
assert "app_requests_total " in (root / "metrics.txt").read_text()
assert json.loads((root / "identity.json").read_text())["version"] == sys.argv[2]
print("Pod probe endpoints, request metrics and deployed version checks passed.")
PY
