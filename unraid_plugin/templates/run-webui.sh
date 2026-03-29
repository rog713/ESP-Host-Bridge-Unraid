#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/plugin-env.sh"

hm::load_plugin_cfg
hm::ensure_python_runtime

PYTHON_BIN="$(hm::python_cmd)"

export WEBUI_PORT="${HM_PORT}"
export WEBUI_HOST="${HM_BIND_HOST}"
export WEBUI_CONFIG="${HM_WEBUI_CFG}"
export WEBUI_PYTHON="${PYTHON_BIN}"
export AUTOSTART=1
export PYTHONUNBUFFERED=1
export PYTHONPATH="${HM_RUNTIME_DIR}:${HM_DEPS_DIR}${PYTHONPATH:+:${PYTHONPATH}}"
if [ -f "${HM_PLUGIN_DIR}/plugin.version" ]; then
  export ESP_HOST_BRIDGE_VERSION="$(cat "${HM_PLUGIN_DIR}/plugin.version" 2>/dev/null || true)"
fi

exec "${PYTHON_BIN}" -m esp_host_bridge webui --host "${HM_BIND_HOST}" --port "${HM_PORT}" >> "${HM_LOG_FILE}" 2>&1
