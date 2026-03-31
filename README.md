# ESP Host Bridge for Unraid

This repository is the maintained Unraid plugin line for ESP Host Bridge.

It keeps the current `esp_host_bridge` runtime and Web UI together with a dedicated Unraid plugin scaffold so the old legacy plugin can remain untouched while the Unraid integration evolves separately.

## What it includes

- `esp_host_bridge/`
  - the maintained runtime package
  - local Web UI and USB CDC agent
  - refactored integration-registry runtime
  - optional Docker, VM, and Unraid API polling
- `unraid_plugin/`
  - Unraid plugin page templates
  - service wrapper scripts
  - packaging script for `.plg` and `.txz`
- `scripts/`
  - core sync helper for importing the latest Host Bridge runtime
  - overlay patch refresh helper for preserving Unraid-specific changes

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
VERSION=2026.03.31.5 unraid_plugin/build_unraid_plugin.sh
```

## Publish a GitHub release

Release publishing now happens through the local `gh` CLI script so the exact built `.plg` and `.txz` are uploaded immediately after validation.

Publish flow:

1. bump `pyproject.toml`
2. commit the release changes
3. run:

```bash
scripts/publish_github_release.sh
```

The script:

- refuses to reuse an existing tag or release
- runs the local test floor
- rebuilds the plugin once locally
- pushes `main`
- creates tag `v<version>` if needed
- creates the GitHub release and uploads:

- `esp-host-bridge.plg`
- `esp-host-bridge-<version>-noarch-1.txz`

## Keep the plugin in sync

The shared Host Bridge core now comes from the private source repo, and this repo keeps only the Unraid-specific overlay on top of it.

Sync the current refactored core from the private Host Bridge repo:

```bash
scripts/sync_core_from_host_bridge.sh
```

Or point at a different source checkout explicitly:

```bash
scripts/sync_core_from_host_bridge.sh /path/to/ESP-Host-Bridge-private
```

After changing Unraid-specific overlay files, refresh the overlay patch that the sync script reapplies:

```bash
scripts/refresh_unraid_overlay_patch.sh
```

Recommended flow:

1. sync from the private Host Bridge repo
2. review the diff and bump the Unraid repo version if needed
3. run the local test floor
4. publish a tagged release

Validation commands:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
python3 -m py_compile esp_host_bridge/*.py esp_host_bridge/integrations/*.py tests/test_*.py
node --check esp_host_bridge/host_ui.js
unraid_plugin/build_unraid_plugin.sh
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

## Install on Unraid

In Unraid, go to `Plugins` -> `Install Plugin` and paste the release `.plg` URL:

- `https://github.com/rog713/ESP-Host-Bridge-Unraid/releases/download/<version>/esp-host-bridge.plg`

After install:

1. open the `ESP Host Bridge` page under `Tools`
2. start the service if it is not already running
3. open the main Web UI from the wrapper page
4. configure serial and, if you want the Unraid API path, add your GraphQL API key there

## Unraid API

If you enable the optional Unraid API path in the main Web UI, use a Unraid 7.2+ GraphQL API key with at least:

- `INFO:READ_ANY`
- `ARRAY:READ_ANY`
- `DOCKER:READ_ANY`
- `VMS:READ_ANY`
- `DISK:READ_ANY`

The preferred local GraphQL endpoint is:

- `http://127.0.0.1/graphql`

If that fails, the bridge automatically falls back to:

- `http://127.0.0.1:3001/graphql`

With broader API access, the Unraid plugin page can also surface optional server, services, shares, disks, and plugins details.

## Troubleshooting

- If the Unraid API shows unavailable, start with:
  - `http://127.0.0.1/graphql`
- If you do not see optional details on the wrapper page, the API key is usually missing one or more read permissions.
- Disk temperature can still come from the local probe path if the Unraid API returns `null` for the selected disk.
- Network throughput, disk I/O, fan, and GPU metrics still come from local host probes, not the Unraid API.

## Notes

- This repo is the new Unraid-focused plugin line.
- The older Unraid plugin scaffold in the other workspace was left intact.
- The main Web UI remains the source of truth for telemetry and bridge configuration.
