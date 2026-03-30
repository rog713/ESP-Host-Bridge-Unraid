#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_WORK_DIR="${ROOT_DIR}/unraid_plugin"
TEMPLATE_DIR="${PLUGIN_WORK_DIR}/templates"
PLUGIN_ID="esp-host-bridge"
LEGACY_PLUGIN_ID="host-metrics-usb-cdc"
DISPLAY_NAME="ESP Host Bridge"
PAGE_ID="ESPHostBridge"
VERSION="${VERSION:-$(python3 - "${ROOT_DIR}/pyproject.toml" <<'PY'
from __future__ import annotations
import re
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    raw = f.read()
section = re.search(r'(?ms)^\[project\]\s*(.*?)^(?:\[|\Z)', raw)
version = ''
if section:
    match = re.search(r'(?m)^version\s*=\s*"([^"\n]+)"\s*$', section.group(1))
    if match:
        version = match.group(1).strip()
print(version or 'dev')
PY
)}"
PACKAGE_BASENAME="${PLUGIN_ID}-${VERSION}-noarch-1"
PACKAGE_FILE="${PACKAGE_BASENAME}.txz"
DIST_DIR="${PLUGIN_WORK_DIR}/dist"
BUILD_DIR="${PLUGIN_WORK_DIR}/build"
PKGROOT="${BUILD_DIR}/pkgroot"
PLUGIN_ROOT="${PKGROOT}/usr/local/emhttp/plugins/${PLUGIN_ID}"
APP_DIR="${PLUGIN_ROOT}/app"
WHEEL_DIR="${BUILD_DIR}/wheelhouse"
VENDOR_DIR="${PLUGIN_ROOT}/vendor"
PLUGIN_LOCAL_BASE="file:///boot/config/plugins/${PLUGIN_ID}"
PACKAGE_PATH="${DIST_DIR}/${PACKAGE_FILE}"
PLG_PATH="${DIST_DIR}/${PLUGIN_ID}.plg"
REQ_FILE="${BUILD_DIR}/requirements-unraid.txt"

rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${PLUGIN_ROOT}/scripts" "${PLUGIN_ROOT}/php" "${PLUGIN_ROOT}/event" "${PLUGIN_ROOT}/packages" "${APP_DIR}" "${VENDOR_DIR}" "${WHEEL_DIR}" "${PKGROOT}/etc/rc.d" "${PKGROOT}/install" "${DIST_DIR}"

copy_runtime() {
  rsync -a --delete \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='config.json' \
    "${ROOT_DIR}/esp_host_bridge/" "${APP_DIR}/esp_host_bridge/"
  printf '%s\n' "${VERSION}" > "${PLUGIN_ROOT}/plugin.version"
}

copy_templates() {
  install -m 0755 "${TEMPLATE_DIR}/plugin-env.sh" "${PLUGIN_ROOT}/scripts/plugin-env.sh"
  install -m 0755 "${TEMPLATE_DIR}/run-webui.sh" "${PLUGIN_ROOT}/scripts/run-webui.sh"
  install -m 0755 "${TEMPLATE_DIR}/starting_array" "${PLUGIN_ROOT}/event/starting_array"
  install -m 0755 "${TEMPLATE_DIR}/stopped_array" "${PLUGIN_ROOT}/event/stopped_array"
  install -m 0644 "${TEMPLATE_DIR}/icon.svg" "${PLUGIN_ROOT}/icon.svg"
  install -m 0644 "${TEMPLATE_DIR}/esp-host-bridge.page" "${PLUGIN_ROOT}/${PAGE_ID}.page"
  install -m 0644 "${TEMPLATE_DIR}/service.php" "${PLUGIN_ROOT}/php/service.php"
  install -m 0755 "${TEMPLATE_DIR}/rc.esp_host_bridge" "${PKGROOT}/etc/rc.d/rc.esp_host_bridge"
  install -m 0644 "${TEMPLATE_DIR}/slack-desc" "${PKGROOT}/install/slack-desc"
}

generate_requirements() {
  python3 - "${ROOT_DIR}/pyproject.toml" > "${REQ_FILE}" <<'PY'
from __future__ import annotations
import re
import sys
with open(sys.argv[1], 'r', encoding='utf-8', errors='ignore') as f:
    raw = f.read()
section = re.search(r'(?ms)^\[project\]\s*(.*?)^(?:\[|\Z)', raw)
if not section:
    raise SystemExit("project section not found in pyproject.toml")
deps = re.search(r'(?ms)^dependencies\s*=\s*\[(.*?)\]', section.group(1))
if not deps:
    raise SystemExit(0)
for dep in re.findall(r'"([^"\n]+)"', deps.group(1)):
    print(dep.strip())
PY
}

bundle_vendor_deps() {
  generate_requirements
  python3 -m pip download \
    --only-binary=:all: \
    --platform manylinux2014_x86_64 \
    --python-version 39 \
    --implementation cp \
    --abi cp39 \
    --dest "${WHEEL_DIR}" \
    -r "${REQ_FILE}"

  python3 - "${WHEEL_DIR}" "${VENDOR_DIR}" <<'PY'
from __future__ import annotations
import pathlib
import sys
import zipfile

wheel_dir = pathlib.Path(sys.argv[1])
vendor_dir = pathlib.Path(sys.argv[2])
vendor_dir.mkdir(parents=True, exist_ok=True)

for wheel in sorted(wheel_dir.glob('*.whl')):
    with zipfile.ZipFile(wheel) as zf:
        zf.extractall(vendor_dir)
PY
}

base64_file() {
  python3 - "$1" <<'PY'
from __future__ import annotations
import base64
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
print(base64.b64encode(path.read_bytes()).decode('ascii'))
PY
}

copy_runtime
copy_templates
bundle_vendor_deps

cat > "${PLUGIN_ROOT}/${PLUGIN_ID}.plg" <<PLGEOF
<?xml version="1.0"?>
<PLUGIN name="${PLUGIN_ID}" author="${DISPLAY_NAME}" version="${VERSION}" icon="line-chart" launch="Tools/${PAGE_ID}" pluginURL="${PLUGIN_LOCAL_BASE}.plg">
<CHANGES>
### ${VERSION}
- Package the maintained esp_host_bridge runtime and Web UI.
- Add richer bridge status, ESP Wi-Fi/display state, and log tail to the Unraid page.
- Clean up the Unraid wrapper page by hiding empty optional sections and filtering irrelevant disks.
</CHANGES>

<FILE Name="/boot/config/plugins/${PLUGIN_ID}/packages/${PACKAGE_FILE}" Run="upgradepkg --install-new --reinstall">
<URL>${PLUGIN_LOCAL_BASE}/packages/${PACKAGE_FILE}</URL>
</FILE>
</PLUGIN>
PLGEOF

tar -C "${PKGROOT}" -cJf "${PACKAGE_PATH}" .
PACKAGE_BASE64="$(base64_file "${PACKAGE_PATH}")"

cat > "${PLG_PATH}" <<EOF2
<?xml version="1.0"?>
<PLUGIN name="${PLUGIN_ID}" author="${DISPLAY_NAME}" version="${VERSION}" icon="line-chart" launch="Tools/${PAGE_ID}" pluginURL="${PLUGIN_LOCAL_BASE}.plg">
<CHANGES>
### ${VERSION}
- Package the maintained esp_host_bridge runtime and Web UI.
- Add richer bridge status, ESP Wi-Fi/display state, and log tail to the Unraid page.
- Clean up the Unraid wrapper page by hiding empty optional sections and filtering irrelevant disks.
</CHANGES>

<FILE Run="/bin/bash">
<INLINE><![CDATA[
if [ -d /boot/config/plugins/${LEGACY_PLUGIN_ID} ]; then
  if [ ! -d /boot/config/plugins/${PLUGIN_ID} ]; then
    mv /boot/config/plugins/${LEGACY_PLUGIN_ID} /boot/config/plugins/${PLUGIN_ID}
  fi
fi
mkdir -p /boot/config/plugins/${PLUGIN_ID} /boot/config/plugins/${PLUGIN_ID}/packages /boot/logs
/etc/rc.d/rc.host_metrics_usb_cdc stop || true
if ls /var/log/packages/${LEGACY_PLUGIN_ID}-* >/dev/null 2>&1; then
  removepkg ${LEGACY_PLUGIN_ID} || true
fi
rm -rf /usr/local/emhttp/plugins/${LEGACY_PLUGIN_ID}
rm -f /etc/rc.d/rc.host_metrics_usb_cdc
rm -f /usr/local/emhttp/plugins/${PLUGIN_ID}/${PLUGIN_ID}.page
rm -f /usr/local/emhttp/plugins/${PLUGIN_ID}/${PAGE_ID}.page
]]></INLINE>
</FILE>

<FILE Name="/boot/config/plugins/${PLUGIN_ID}/packages/${PACKAGE_FILE}" Min="0" Type="base64" Run="upgradepkg --install-new --reinstall">
<INLINE>${PACKAGE_BASE64}</INLINE>
</FILE>

<FILE Run="/bin/bash">
<INLINE>
mkdir -p /usr/local/emhttp/plugins/${PLUGIN_ID}/packages /boot/config/plugins
cp -f /usr/local/emhttp/plugins/${PLUGIN_ID}/${PLUGIN_ID}.plg /boot/config/plugins/${PLUGIN_ID}.plg
cp -f /boot/config/plugins/${PLUGIN_ID}/packages/${PACKAGE_FILE} /usr/local/emhttp/plugins/${PLUGIN_ID}/packages/${PACKAGE_FILE}
</INLINE>
</FILE>

<FILE Run="/bin/bash">
<INLINE>
if [ -x /usr/local/emhttp/plugins/${PLUGIN_ID}/scripts/plugin-env.sh ]; then
  # shellcheck disable=SC1091
  . /usr/local/emhttp/plugins/${PLUGIN_ID}/scripts/plugin-env.sh
  if hm::autostart_enabled; then
    /etc/rc.d/rc.esp_host_bridge restart || /etc/rc.d/rc.esp_host_bridge start || true
  fi
else
  /etc/rc.d/rc.esp_host_bridge restart || /etc/rc.d/rc.esp_host_bridge start || true
fi
</INLINE>
</FILE>

<FILE Run="/bin/bash" Method="remove">
<INLINE>
/etc/rc.d/rc.esp_host_bridge stop || true
removepkg ${PLUGIN_ID} || true
rm -rf /boot/config/plugins/${PLUGIN_ID}
</INLINE>
</FILE>
</PLUGIN>
EOF2

printf 'Built:\n- %s\n- %s\n' "${PACKAGE_PATH}" "${PLG_PATH}"
