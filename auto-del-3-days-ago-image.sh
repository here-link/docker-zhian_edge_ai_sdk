#!/usr/bin/env bash
set -euo pipefail

# Delete stale image/feature/log artifacts left by the Zhian API service.
# Defaults match the historical bp3V203 optimization: keep files from the
# most recent 3 days.  Override with:
#   IMAGE_RETENTION_DAYS=3
#   IMAGE_CLEANUP_PATHS="/data1 /workspace/tmp /workspace/apiservice/imagedata"
#   IMAGE_CLEANUP_EXCLUDE_NAMES="liu_de_hua.jpg ..."

: "${IMAGE_RETENTION_DAYS:=3}"
: "${IMAGE_CLEANUP_PATHS:=/data1 /workspace/tmp /workspace/apiservice/imagedata}"
: "${IMAGE_CLEANUP_EXCLUDE_NAMES:=guo_fu_cheng.jpg li_ming.jpg liu_de_hua.jpg zhang_xue_you.jpg}"

case "${IMAGE_RETENTION_DAYS}" in
  ''|*[!0-9]*)
    echo "[cleanup] invalid IMAGE_RETENTION_DAYS=${IMAGE_RETENTION_DAYS}" >&2
    exit 2
    ;;
esac

retention_minutes=$((IMAGE_RETENTION_DAYS * 24 * 60))
deleted_count=0

should_skip_file() {
  local base_name="$1"
  local excluded

  for excluded in ${IMAGE_CLEANUP_EXCLUDE_NAMES}; do
    if [[ "${base_name}" == "${excluded}" ]]; then
      return 0
    fi
  done

  return 1
}

# Intentionally restrict deletion to transient file types.  Do not delete
# arbitrary files from mounted /data1 because deployments sometimes keep
# sample/reference inputs there.
cleanup_one_dir() {
  local dir="$1"

  if [[ ! -d "${dir}" ]]; then
    echo "[cleanup] skip missing dir: ${dir}"
    return 0
  fi

  echo "[cleanup] scanning ${dir}, retention_days=${IMAGE_RETENTION_DAYS}"

  while IFS= read -r -d '' file; do
    if should_skip_file "${file##*/}"; then
      echo "[cleanup] keep excluded ${file}"
      continue
    fi

    if rm -f -- "${file}"; then
      deleted_count=$((deleted_count + 1))
      echo "[cleanup] deleted ${file}"
    else
      echo "[cleanup] warn: failed to delete ${file}" >&2
    fi
  done < <(
    find -L "${dir}" -xdev -type f -mmin "+${retention_minutes}" \
      \( -iname '*.jpg' \
      -o -iname '*.jpeg' \
      -o -iname '*.png' \
      -o -iname '*.bmp' \
      -o -iname '*.webp' \
      -o -iname '*.gif' \
      -o -iname '*.bin' \
      -o -iname '*.log' \
      -o -iname '*.txt' \
      -o -iname '*.tmp' \) \
      -print0 2>/dev/null || true
  )
}

for dir in ${IMAGE_CLEANUP_PATHS}; do
  cleanup_one_dir "${dir}"
done

echo "[cleanup] deleted_count=${deleted_count}"
