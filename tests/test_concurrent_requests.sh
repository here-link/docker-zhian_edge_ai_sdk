#!/usr/bin/env bash
set -euo pipefail

image="${1:-ghcr.io/here-link/docker-zhian_edge_ai_sdk:be3v120}"
requests="${CONCURRENT_REQUESTS:-12}"
port="${TEST_PORT:-5002}"

rm -f /tmp/zhian-conc-resp-*.json /tmp/zhian-conc-status-*.txt

cid="$(docker run -d \
  --platform linux/amd64 \
  -e ENABLE_IMAGE_CLEANUP=0 \
  -e IMAGE_CLEANUP_INTERVAL_SECONDS=999999 \
  -p "${port}:8008" \
  "${image}")"
cleanup() {
  docker rm -f "${cid}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:${port}/" >/dev/null; then
  echo "server did not become ready" >&2
  docker logs "${cid}" >&2 || true
  exit 1
fi

seq 1 "${requests}" | xargs -P "${requests}" -I{} sh -c '
  set +e
  code=$(curl -sS -w "%{http_code}" -o "/tmp/zhian-conc-resp-{}.json" "http://127.0.0.1:'"${port}"'/predict?image=data1/liu_de_hua.jpg&version=V2")
  ec=$?
  echo "${ec}:${code}" > "/tmp/zhian-conc-status-{}.txt"
'

ok=0
fail=0
for i in $(seq 1 "${requests}"); do
  status="$(cat "/tmp/zhian-conc-status-${i}.txt")"
  body="$(tr -d '\n' < "/tmp/zhian-conc-resp-${i}.json" | cut -c1-220)"
  if [[ "${status}" == "0:200" ]] && grep -q '"code":0' "/tmp/zhian-conc-resp-${i}.json"; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL req=%02d curl_http=%s body=%s\n' "${i}" "${status}" "${body}" >&2
  fi
done

printf 'concurrent_requests=%s ok=%s fail=%s\n' "${requests}" "${ok}" "${fail}"

if [[ "${fail}" -ne 0 ]]; then
  echo '--- container logs tail ---' >&2
  docker logs "${cid}" 2>&1 | tail -160 >&2 || true
  exit 1
fi
