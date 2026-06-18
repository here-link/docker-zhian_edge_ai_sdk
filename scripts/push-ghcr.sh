#!/usr/bin/env bash
set -euo pipefail

# Load the vendor BE3V120 image archive, push it as a private GHCR base image,
# then build and push this repository's optimized wrapper image.
#
# Required before running:
#   echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

ARCHIVE_PATH="${ARCHIVE_PATH:-BE3V120.tar}"
OWNER="${OWNER:-here-link}"
BASE_LOCAL="${BASE_LOCAL:-faceedge01/zhian_edge_ai_sdk:BE3V120}"
BASE_REMOTE="${BASE_REMOTE:-ghcr.io/${OWNER}/zhian_edge_ai_sdk-base:BE3V120}"
IMAGE_REMOTE="${IMAGE_REMOTE:-ghcr.io/${OWNER}/docker-zhian_edge_ai_sdk:be3v120}"
PUSH_LATEST="${PUSH_LATEST:-1}"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "archive not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

echo "==> Loading vendor archive: ${ARCHIVE_PATH}"
docker load -i "${ARCHIVE_PATH}"

echo "==> Tagging base image: ${BASE_LOCAL} -> ${BASE_REMOTE}"
docker tag "${BASE_LOCAL}" "${BASE_REMOTE}"

echo "==> Pushing base image: ${BASE_REMOTE}"
docker push "${BASE_REMOTE}"

echo "==> Building optimized image: ${IMAGE_REMOTE}"
docker build \
  --platform linux/amd64 \
  --build-arg "BASE_IMAGE=${BASE_REMOTE}" \
  -t "${IMAGE_REMOTE}" \
  .

echo "==> Pushing optimized image: ${IMAGE_REMOTE}"
docker push "${IMAGE_REMOTE}"

if [[ "${PUSH_LATEST}" == "1" ]]; then
  latest_ref="${IMAGE_REMOTE%:*}:latest"
  echo "==> Pushing latest tag: ${latest_ref}"
  docker tag "${IMAGE_REMOTE}" "${latest_ref}"
  docker push "${latest_ref}"
fi

echo "Done."
