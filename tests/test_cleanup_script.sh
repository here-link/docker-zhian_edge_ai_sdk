#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${1:-${repo_root}/auto-del-3-days-ago-image.sh}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

mkdir -p "${tmpdir}/data1" "${tmpdir}/workspace-tmp"

printf 'old image' > "${tmpdir}/data1/old.jpg"
printf 'old feature' > "${tmpdir}/data1/old_V2.bin"
printf 'old log' > "${tmpdir}/workspace-tmp/old.log"
printf 'old non-target' > "${tmpdir}/data1/old.keep"
printf 'built-in sample' > "${tmpdir}/data1/liu_de_hua.jpg"
printf 'new image' > "${tmpdir}/data1/new.jpg"
printf 'new feature' > "${tmpdir}/data1/new_V2.bin"

touch -t 202001010000 \
  "${tmpdir}/data1/old.jpg" \
  "${tmpdir}/data1/old_V2.bin" \
  "${tmpdir}/workspace-tmp/old.log" \
  "${tmpdir}/data1/old.keep" \
  "${tmpdir}/data1/liu_de_hua.jpg"

IMAGE_CLEANUP_PATHS="${tmpdir}/data1 ${tmpdir}/workspace-tmp ${tmpdir}/missing" \
IMAGE_RETENTION_DAYS=3 \
"${script}" >/tmp/cleanup-test.log

[[ ! -e "${tmpdir}/data1/old.jpg" ]]
[[ ! -e "${tmpdir}/data1/old_V2.bin" ]]
[[ ! -e "${tmpdir}/workspace-tmp/old.log" ]]
[[ -e "${tmpdir}/data1/old.keep" ]]
[[ -e "${tmpdir}/data1/liu_de_hua.jpg" ]]
[[ -e "${tmpdir}/data1/new.jpg" ]]
[[ -e "${tmpdir}/data1/new_V2.bin" ]]

grep -q 'deleted_count=3' /tmp/cleanup-test.log
