#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

VERSION="${VERSION:-$(python3 - <<'PY'
from __future__ import annotations
import re
from pathlib import Path
raw = Path("pyproject.toml").read_text(encoding="utf-8")
match = re.search(r'(?m)^version\s*=\s*"([^"\n]+)"\s*$', raw)
print(match.group(1) if match else "")
PY
)}"
TAG="v${VERSION}"

if [ -z "${VERSION}" ]; then
  echo "Could not determine version from pyproject.toml" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree is not clean. Commit or stash changes first." >&2
  exit 1
fi

TAG_EXISTS_REMOTE=0
if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  TAG_EXISTS_REMOTE=1
fi

if gh release view "${TAG}" --repo "rog713/ESP-Host-Bridge-Unraid" >/dev/null 2>&1; then
  echo "GitHub release ${TAG} already exists. Bump the version before publishing." >&2
  exit 1
fi

python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m py_compile esp_host_bridge/*.py esp_host_bridge/integrations/*.py tests/test_*.py
node --check esp_host_bridge/host_ui.js
unraid_plugin/build_unraid_plugin.sh

git push origin main

if [ "${TAG_EXISTS_REMOTE}" -eq 0 ]; then
  git tag -a "${TAG}" -m "Release ${VERSION}"
  git push origin "${TAG}"
fi

gh api "repos/rog713/ESP-Host-Bridge-Unraid/releases" \
  -X POST \
  -f tag_name="${TAG}" \
  -f name="${TAG}" \
  -F draft=false \
  -F prerelease=false >/dev/null

gh release upload "${TAG}" \
  "unraid_plugin/dist/esp-host-bridge.plg" \
  "unraid_plugin/dist/esp-host-bridge-${VERSION}-noarch-1.txz" \
  --repo "rog713/ESP-Host-Bridge-Unraid"

echo "Published ${TAG} with plugin assets."
