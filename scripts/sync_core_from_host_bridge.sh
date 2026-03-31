#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-${ESP_HOST_BRIDGE_SOURCE_DIR:-${ROOT_DIR}/../ESP-Host-Bridge-private}}"
PATCH_FILE="${ROOT_DIR}/scripts/unraid_core_overlay.patch"

if [ ! -d "${SOURCE_DIR}/esp_host_bridge" ]; then
  echo "Source repo not found at ${SOURCE_DIR}" >&2
  exit 1
fi
if [ ! -f "${PATCH_FILE}" ]; then
  echo "Overlay patch not found: ${PATCH_FILE}" >&2
  echo "Run scripts/refresh_unraid_overlay_patch.sh first." >&2
  exit 1
fi

rsync -a --delete \
  --exclude='config.json' \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  "${SOURCE_DIR}/esp_host_bridge/" "${ROOT_DIR}/esp_host_bridge/"

if [ -d "${SOURCE_DIR}/tests" ]; then
  rsync -a --delete --exclude='__pycache__' --exclude='*.pyc' "${SOURCE_DIR}/tests/" "${ROOT_DIR}/tests/"
fi

if [ -d "${SOURCE_DIR}/docs" ]; then
  rsync -a --delete --exclude='__pycache__' --exclude='*.pyc' "${SOURCE_DIR}/docs/" "${ROOT_DIR}/docs/"
fi

if [ -f "${SOURCE_DIR}/images/webui-dashboard.png" ]; then
  mkdir -p "${ROOT_DIR}/images"
  rsync -a "${SOURCE_DIR}/images/webui-dashboard.png" "${ROOT_DIR}/images/webui-dashboard.png"
fi

git -C "${ROOT_DIR}" apply --whitespace=nowarn "${PATCH_FILE}"
find "${ROOT_DIR}/esp_host_bridge" "${ROOT_DIR}/tests" "${ROOT_DIR}/docs" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true

echo "Synced refactored core from ${SOURCE_DIR}"
echo "Next: review git diff, bump version if needed, run tests, then rebuild unraid_plugin/."
