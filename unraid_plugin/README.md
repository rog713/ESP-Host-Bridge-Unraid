# Unraid Plugin

This directory contains the Unraid plugin scaffold for the maintained `esp_host_bridge` runtime.

## What it builds

- `dist/esp-host-bridge-<version>-noarch-1.txz`
- `dist/esp-host-bridge.plg`

The generated `.plg` is self-contained and embeds the `.txz` package as base64.

## Build

Run from the repo root:

```bash
unraid_plugin/build_unraid_plugin.sh
```

The build defaults to the version declared in `pyproject.toml`.

Override the version if needed:

```bash
VERSION=2026.03.30.1 unraid_plugin/build_unraid_plugin.sh
```

## Runtime layout on Unraid

- Runtime files:
  - `/usr/local/emhttp/plugins/esp-host-bridge/`
- Persistent state:
  - `/boot/config/plugins/esp-host-bridge/`
- Installed Python dependencies:
  - `/usr/local/emhttp/plugins/esp-host-bridge/vendor`
- Logs:
  - `/boot/logs/esp_host_bridge_webui.log`
- Service control:
  - `/etc/rc.d/rc.esp_host_bridge`

## Plugin page

The Unraid page provides:

- plugin enable/disable
- service start/stop/restart
- wrapper settings for port, bind host, and autostart
- live bridge status from `/api/status`
- bridge version, telemetry freshness, ESP display state, ESP Wi-Fi state, and ESP boot state
- optional Unraid API server, services, shares, disks, and plugins detail cards when the configured key has access
- recent log tail
- link into the main ESP Host Bridge Web UI

## Notes

- The plugin packages the maintained `esp_host_bridge` package, not the older `host_metrics.py` runtime.
- Optional Unraid GraphQL API support is configured in the main Web UI, not on the wrapper page.
- The preferred local Unraid GraphQL endpoint is `http://127.0.0.1/graphql`, with automatic fallback to `http://127.0.0.1:3001/graphql`.
- Docker socket and `virsh` remain available for control commands and fallback paths when the Unraid API is disabled or unavailable.
