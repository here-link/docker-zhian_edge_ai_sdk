#!/usr/bin/env bash
set -euo pipefail

cd /workspace

: "${PORT:=8008}"
: "${GUNICORN_WORKERS:=4}"
: "${GUNICORN_WORKER_CONNECTIONS:=1000}"
: "${GUNICORN_TIMEOUT:=60}"
: "${ENABLE_IMAGE_CLEANUP:=1}"
: "${IMAGE_CLEANUP_INTERVAL_SECONDS:=86400}"
: "${FEATURE_PROCESS_CONCURRENCY:=1}"

DATA1_TARGET="$(readlink -f /data1 2>/dev/null || echo /data1)"
CLEANUP_SCRIPT="/workspace/apiservice/auto-del-3-days-ago-image.sh"

if [[ "${ENABLE_IMAGE_CLEANUP}" != "0" && -x "${CLEANUP_SCRIPT}" ]]; then
  echo "image cleanup: enabled, script=${CLEANUP_SCRIPT}, interval=${IMAGE_CLEANUP_INTERVAL_SECONDS}s"
  (
    while true; do
      "${CLEANUP_SCRIPT}" || echo "[cleanup] warning: ${CLEANUP_SCRIPT} exited with $?" >&2
      sleep "${IMAGE_CLEANUP_INTERVAL_SECONDS}"
    done
  ) &
else
  echo "image cleanup: disabled or script missing"
fi

echo "=== Zhian BE3V120 face feature API ==="
echo "base app: /workspace/doorlock_api.py"
echo "data dir: /data1 -> ${DATA1_TARGET}"
echo "workers: ${GUNICORN_WORKERS}, worker_connections: ${GUNICORN_WORKER_CONNECTIONS}, timeout: ${GUNICORN_TIMEOUT}s"
echo "feature_process_concurrency: ${FEATURE_PROCESS_CONCURRENCY}"
echo "listen: 0.0.0.0:${PORT}"
echo "========================================"

exec gunicorn \
  -w "${GUNICORN_WORKERS}" \
  -k gevent \
  -b "0.0.0.0:${PORT}" \
  --worker-connections "${GUNICORN_WORKER_CONNECTIONS}" \
  --timeout "${GUNICORN_TIMEOUT}" \
  --access-logfile - \
  --error-logfile - \
  api_app:app
