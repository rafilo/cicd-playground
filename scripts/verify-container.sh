#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: verify-container.sh IMAGE EXPECTED_VERSION}"
expected_version="${2:?Expected application version is required}"
container=podflow-ci
base_url=http://127.0.0.1:18081
response_dir=$(mktemp -d)

cleanup() {
  status=$?
  trap - EXIT
  docker inspect --format '{{json .State}}' "$container" || true
  docker logs "$container" || true
  docker rm -f "$container" || true
  rm -rf -- "$response_dir"
  exit "$status"
}
trap cleanup EXIT

# This is the runner's Docker container, not a Pod on the developer's computer.
docker run -d --name "$container" --read-only --cap-drop ALL \
  --security-opt no-new-privileges --user 1000:1000 \
  -p 127.0.0.1:18081:8080 "$image"
docker port "$container" 8080/tcp

ready=false
for attempt in $(seq 1 30); do
  if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" != true ]]; then
    echo 'Container exited before readiness; see state and logs below.' >&2
    exit 1
  fi
  # Docker may reset a connection before Kestrel binds its port. Retry startup
  # failures explicitly, including reset/refused connections and HTTP errors.
  if curl --noproxy '*' --connect-timeout 2 --max-time 3 --fail --silent --show-error \
    --output "$response_dir/ready.json" "$base_url/readyz"; then
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "ok"' "$response_dir/ready.json"
    ready=true
    break
  fi
  echo "Waiting for application readiness ($attempt/30)..."
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo 'Application did not become ready within 30 bounded attempts.' >&2
  exit 1
fi

# Once ready, failures are test failures, not indefinitely retried.
curl --noproxy '*' --connect-timeout 2 --max-time 5 --fail --silent --show-error \
  --output "$response_dir/home.html" "$base_url/"
grep -q 'Traffic distribution' "$response_dir/home.html"
curl --noproxy '*' --connect-timeout 2 --max-time 5 --fail --silent --show-error \
  --output "$response_dir/identity.json" "$base_url/api/whoami"
python3 -c 'import json,sys; body=json.load(open(sys.argv[1])); assert body["version"] == sys.argv[2]; assert isinstance(body["pod"], str)' \
  "$response_dir/identity.json" "$expected_version"
echo 'Read-only non-root container checks passed.'
