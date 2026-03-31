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
VERSION=2026.03.31.4 unraid_plugin/build_unraid_plugin.sh
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

## Install on Unraid

In Unraid, go to `Plugins` -> `Install Plugin` and paste:

- `https://github.com/rog713/ESP-Host-Bridge-Unraid/releases/download/<version>/esp-host-bridge.plg`

Then open `Tools` -> `ESP Host Bridge` and use `Open Web UI` to finish the bridge configuration.

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
- Disk temperature may still fall back to the local probe path if the Unraid API returns `null` for the selected disk.
- When you sync from the private Host Bridge repo, rerun `scripts/refresh_unraid_overlay_patch.sh` if you changed any Unraid-specific overlay files.
