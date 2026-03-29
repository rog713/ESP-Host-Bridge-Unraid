#!/bin/bash
set -euo pipefail

HM_PLUGIN_NAME="esp-host-bridge"
HM_PLUGIN_DIR="/usr/local/emhttp/plugins/${HM_PLUGIN_NAME}"
HM_RUNTIME_DIR="${HM_PLUGIN_DIR}/app"
HM_RUNTIME_PACKAGE_DIR="${HM_RUNTIME_DIR}/esp_host_bridge"
HM_DEPS_DIR="${HM_PLUGIN_DIR}/vendor"
HM_STATE_DIR="/boot/config/plugins/${HM_PLUGIN_NAME}"
HM_PACKAGE_DIR="${HM_STATE_DIR}/packages"
HM_PLUGIN_CFG="${HM_STATE_DIR}/plugin.cfg"
HM_WEBUI_CFG="${HM_STATE_DIR}/config.json"
HM_LOG_FILE="/boot/logs/esp_host_bridge_webui.log"
HM_PID_FILE="/var/run/esp_host_bridge.pid"
HM_PORT_DEFAULT="8654"
HM_BIND_HOST_DEFAULT="0.0.0.0"
HM_AUTOSTART_DEFAULT="yes"

hm::ensure_dirs() {
  mkdir -p "${HM_STATE_DIR}" "${HM_PACKAGE_DIR}" "/boot/logs"
}

hm::ensure_plugin_cfg() {
  hm::ensure_dirs
  if [ -f "${HM_PLUGIN_CFG}" ]; then
    return 0
  fi
  cat > "${HM_PLUGIN_CFG}" <<'EOF'
HM_PORT="8654"
HM_BIND_HOST="0.0.0.0"
HM_AUTOSTART="yes"
EOF
}

hm::load_plugin_cfg() {
  hm::ensure_plugin_cfg
  set -a
  # shellcheck disable=SC1090
  . "${HM_PLUGIN_CFG}"
  set +a

  case "${HM_PORT:-}" in
    ''|*[!0-9]*) HM_PORT="${HM_PORT_DEFAULT}" ;;
  esac
  if [ "${HM_PORT}" -lt 1 ] || [ "${HM_PORT}" -gt 65535 ]; then
    HM_PORT="${HM_PORT_DEFAULT}"
  fi

  HM_BIND_HOST="${HM_BIND_HOST:-${HM_BIND_HOST_DEFAULT}}"
  if [ -z "${HM_BIND_HOST}" ]; then
    HM_BIND_HOST="${HM_BIND_HOST_DEFAULT}"
  fi

  HM_AUTOSTART="${HM_AUTOSTART:-${HM_AUTOSTART_DEFAULT}}"
}

hm::autostart_enabled() {
  hm::load_plugin_cfg
  case "${HM_AUTOSTART}" in
    1|yes|true|on|enabled|ENABLED|YES|TRUE|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

hm::python_cmd() {
  command -v python3
}

hm::ensure_python_runtime() {
  hm::load_plugin_cfg
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required but not available" >> "${HM_LOG_FILE}"
    return 1
  fi
  if [ ! -d "${HM_DEPS_DIR}" ]; then
    echo "bundled python dependencies are missing from ${HM_DEPS_DIR}" >> "${HM_LOG_FILE}"
    return 1
  fi
  if [ ! -f "${HM_RUNTIME_PACKAGE_DIR}/webui_app.py" ]; then
    echo "esp_host_bridge runtime package is missing from ${HM_RUNTIME_PACKAGE_DIR}" >> "${HM_LOG_FILE}"
    return 1
  fi
  if [ ! -f "${HM_DEPS_DIR}/psutil/__init__.py" ] || [ ! -d "${HM_DEPS_DIR}/flask" ] || [ ! -d "${HM_DEPS_DIR}/serial" ] || [ ! -d "${HM_DEPS_DIR}/yaml" ]; then
    echo "bundled python dependencies are incomplete in ${HM_DEPS_DIR}" >> "${HM_LOG_FILE}"
    return 1
  fi
}

hm::service_pid() {
  if [ -f "${HM_PID_FILE}" ]; then
    cat "${HM_PID_FILE}" 2>/dev/null || true
  fi
}

hm::find_webui_pid() {
  local pid=""
  pid="$(hm::service_pid)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    printf '%s\n' "${pid}"
    return 0
  fi

  pid="$(pgrep -f "esp_host_bridge webui" | head -n1 || true)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    printf '%s\n' "${pid}" > "${HM_PID_FILE}"
    printf '%s\n' "${pid}"
    return 0
  fi

  rm -f "${HM_PID_FILE}"
  return 1
}

hm::service_running() {
  local pid
  pid="$(hm::find_webui_pid || true)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi
  return 1
}

hm::write_plugin_cfg() {
  local port bind_host autostart
  port="${1:-${HM_PORT_DEFAULT}}"
  bind_host="${2:-${HM_BIND_HOST_DEFAULT}}"
  autostart="${3:-${HM_AUTOSTART_DEFAULT}}"
  hm::ensure_dirs
  cat > "${HM_PLUGIN_CFG}" <<EOF
HM_PORT="${port}"
HM_BIND_HOST="${bind_host}"
HM_AUTOSTART="${autostart}"
EOF
}
