#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-${ESP_HOST_BRIDGE_SOURCE_DIR:-${ROOT_DIR}/../ESP-Host-Bridge-private}}"
MANIFEST="${ROOT_DIR}/scripts/unraid_overlay_files.txt"
PATCH_FILE="${ROOT_DIR}/scripts/unraid_core_overlay.patch"

if [ ! -d "${SOURCE_DIR}/esp_host_bridge" ]; then
  echo "Source repo not found at ${SOURCE_DIR}" >&2
  exit 1
fi
if [ ! -f "${MANIFEST}" ]; then
  echo "Overlay manifest not found: ${MANIFEST}" >&2
  exit 1
fi

: > "${PATCH_FILE}"
while IFS= read -r rel_path; do
  [ -n "${rel_path}" ] || continue
  src="${SOURCE_DIR}/${rel_path}"
  dst="${ROOT_DIR}/${rel_path}"
  if [ -f "${src}" ]; then
    diff -u --label "a/${rel_path}" "${src}" --label "b/${rel_path}" "${dst}" >> "${PATCH_FILE}" || true
  else
    diff -u --label "a/${rel_path}" /dev/null --label "b/${rel_path}" "${dst}" >> "${PATCH_FILE}" || true
  fi
done < "${MANIFEST}"

echo "Wrote ${PATCH_FILE}"
