#!/usr/bin/env bash
set -euo pipefail

cd /workspace

: "${PORT:=8008}"
: "${GUNICORN_WORKERS:=4}"
: "${GUNICORN_WORKER_CONNECTIONS:=1000}"
: "${GUNICORN_TIMEOUT:=60}"

DATA1_TARGET="$(readlink -f /data1 2>/dev/null || echo /data1)"

echo "=== Zhian BE3V120 face feature API ==="
echo "base app: /workspace/doorlock_api.py"
echo "data dir: /data1 -> ${DATA1_TARGET}"
echo "workers: ${GUNICORN_WORKERS}, worker_connections: ${GUNICORN_WORKER_CONNECTIONS}, timeout: ${GUNICORN_TIMEOUT}s"
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
