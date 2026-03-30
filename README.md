# ESP Host Bridge for Unraid

This repository is the maintained Unraid plugin line for ESP Host Bridge.

It keeps the current `esp_host_bridge` runtime and Web UI together with a dedicated Unraid plugin scaffold so the old legacy plugin can remain untouched while the Unraid integration evolves separately.

## What it includes

- `esp_host_bridge/`
  - the maintained runtime package
  - local Web UI and USB CDC agent
  - optional Docker, VM, and Unraid API polling
- `unraid_plugin/`
  - Unraid plugin page templates
  - service wrapper scripts
  - packaging script for `.plg` and `.txz`

## Web UI

![ESP Host Bridge Web UI](images/webui-dashboard.png)

## Unraid plugin improvements in this repo

- packages the maintained `esp_host_bridge` package instead of the older `host_metrics.py` fork
- exposes richer Unraid page status for:
  - bridge version
  - telemetry freshness
  - ESP serial / boot / display / Wi-Fi state
  - recent log tail
- adds optional Unraid 7.2+ GraphQL API support for:
  - system information
  - array state and capacity
  - Docker container inventory
  - VM inventory
  - CPU utilization
  - memory utilization
  - disk temperature
- keeps Docker socket and `virsh` available as fallback and control-command paths

## Build the Unraid plugin

Run from the repo root:

```bash
unraid_plugin/build_unraid_plugin.sh
```

Artifacts are written to:

- `unraid_plugin/dist/esp-host-bridge-<version>-noarch-1.txz`
- `unraid_plugin/dist/esp-host-bridge.plg`

The plugin build reads its version from `pyproject.toml` by default.

Override the version if needed:

```bash
VERSION=2026.03.29.4 unraid_plugin/build_unraid_plugin.sh
```

## Runtime configuration on Unraid

The Unraid plugin installs files under:

- runtime files:
  - `/usr/local/emhttp/plugins/esp-host-bridge/`
- persistent state:
  - `/boot/config/plugins/esp-host-bridge/`
- logs:
  - `/boot/logs/esp_host_bridge_webui.log`
- service control:
  - `/etc/rc.d/rc.esp_host_bridge`

## Unraid API

If you enable the optional Unraid API path in the main Web UI, use a Unraid 7.2+ GraphQL API key with at least:

- `INFO:READ_ANY`
- `ARRAY:READ_ANY`
- `DOCKER:READ_ANY`
- `VMS:READ_ANY`
- `DISK:READ_ANY`

The default local GraphQL endpoint is:

- `http://127.0.0.1:3001/graphql`

With broader API access, the Unraid plugin page can also surface optional server, services, shares, disks, and plugins details.

## Notes

- This repo is the new Unraid-focused plugin line.
- The older Unraid plugin scaffold in the other workspace was left intact.
- The main Web UI remains the source of truth for telemetry and bridge configuration.
