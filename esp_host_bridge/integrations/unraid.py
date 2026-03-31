from __future__ import annotations

import logging
from typing import Any, Dict

from ..unraid_api import (
    UNRAID_API_DEFAULT_URL,
    UNRAID_API_FALLBACK_URLS,
    get_unraid_status_bundle,
    normalize_unraid_docker_data,
    normalize_unraid_vm_data,
)
from .base import CleanerSet, ConfigFieldSpec, IntegrationSpec, PollContext

UNRAID_WARN_INTERVAL_SECONDS = 30.0
UNRAID_DEFAULT_COUNTS = {"running": 0, "stopped": 0, "unhealthy": 0}
UNRAID_DEFAULT_VM_COUNTS = {"running": 0, "stopped": 0, "paused": 0, "other": 0}

UNRAID_CONFIG_FIELDS = (
    ConfigFieldSpec(
        "unraid_api_enabled",
        "bool",
        False,
        checkbox=True,
        label="Enable Unraid API",
        hint="Use the Unraid 7.2+ GraphQL API for array info and as the preferred source for Docker and VM inventory on Unraid.",
        section_key="unraid_api",
    ),
    ConfigFieldSpec(
        "unraid_api_url",
        "str",
        UNRAID_API_DEFAULT_URL,
        cli_flag="--unraid-api-url",
        label="GraphQL URL",
        hint=(
            f"Default local endpoint is <code>{UNRAID_API_DEFAULT_URL}</code>. "
            f"If that fails, the bridge also tries <code>{UNRAID_API_FALLBACK_URLS[0]}</code>."
        ),
        section_key="unraid_api",
    ),
    ConfigFieldSpec(
        "unraid_api_key",
        "str",
        "",
        secret=True,
        cli_flag="--unraid-api-key",
        label="API Key",
        hint=(
            "Sent as the <code>x-api-key</code> header. Create a Unraid key with at least "
            "<code>INFO:READ_ANY</code>, <code>ARRAY:READ_ANY</code>, <code>DOCKER:READ_ANY</code>, "
            "<code>VMS:READ_ANY</code>, and <code>DISK:READ_ANY</code>."
        ),
        section_key="unraid_api",
    ),
    ConfigFieldSpec(
        "unraid_api_interval",
        "float",
        5.0,
        cli_flag="--unraid-api-interval",
        label="API Poll Interval (s)",
        hint="How often Unraid GraphQL data is refreshed. <code>5</code> is a good default.",
        section_key="unraid_api",
        input_step="0.1",
    ),
)


def _docker_summary_counts(rows: list[dict[str, Any]]) -> Dict[str, int]:
    counts = {"running": 0, "stopped": 0, "unhealthy": 0}
    for row in rows:
        if not isinstance(row, dict):
            continue
        state = str(row.get("state") or row.get("State") or row.get("status") or row.get("Status") or "").strip().lower()
        if "unhealthy" in state:
            counts["unhealthy"] += 1
        if any(token in state for token in ("running", "up", "healthy")):
            counts["running"] += 1
        else:
            counts["stopped"] += 1
    return counts


def _vm_summary_counts(rows: list[dict[str, Any]]) -> Dict[str, int]:
    counts = {"running": 0, "stopped": 0, "paused": 0, "other": 0}
    for row in rows:
        if not isinstance(row, dict):
            continue
        state = str(row.get("state_label") or row.get("state") or "").strip().lower()
        if any(token in state for token in ("running", "idle", "shutdown", "no state")):
            counts["running"] += 1
        elif any(token in state for token in ("paused", "suspended", "blocked")):
            counts["paused"] += 1
        elif any(token in state for token in ("stopped", "shut", "crashed")):
            counts["stopped"] += 1
        else:
            counts["other"] += 1
    return counts


def _cache(state: Any) -> Dict[str, Any]:
    integration_cache = getattr(state, "integration_cache", None)
    if not isinstance(integration_cache, dict):
        integration_cache = {}
        setattr(state, "integration_cache", integration_cache)
    cached = integration_cache.get("unraid")
    if not isinstance(cached, dict):
        cached = {
            "bundle": {},
            "docker_items": [],
            "docker_counts": dict(UNRAID_DEFAULT_COUNTS),
            "vm_items": [],
            "vm_counts": dict(UNRAID_DEFAULT_VM_COUNTS),
            "last_refresh_ts": 0.0,
            "last_success_ts": 0.0,
            "last_warn_ts": 0.0,
            "last_error": "",
            "last_error_ts": 0.0,
            "available": None,
            "api_ok": None,
            "source": "disabled",
        }
        integration_cache["unraid"] = cached
    return cached


def validate_cfg(cfg: Dict[str, Any], clean: CleanerSet) -> list[str]:
    errors: list[str] = []
    enabled = clean.clean_bool(cfg.get("unraid_api_enabled"), False)
    interval = clean.clean_float(cfg.get("unraid_api_interval"), 0.0)
    if interval < 0.0:
        errors.append("unraid_api_interval must be >= 0")
    if enabled:
        if not clean.clean_str(cfg.get("unraid_api_url"), ""):
            errors.append("unraid_api_url is required when Unraid API polling is enabled")
        if not clean.clean_str(cfg.get("unraid_api_key"), ""):
            errors.append("unraid_api_key is required when Unraid API polling is enabled")
    return errors


def cfg_to_agent_args(cfg: Dict[str, Any], clean: CleanerSet) -> list[str]:
    argv = [
        "--unraid-api-interval",
        str(clean.clean_float(cfg.get("unraid_api_interval"), 5.0)),
    ]
    url = clean.clean_str(cfg.get("unraid_api_url"), UNRAID_API_DEFAULT_URL)
    key = clean.clean_str(cfg.get("unraid_api_key"), "")
    if url:
        argv += ["--unraid-api-url", url]
    if key:
        argv += ["--unraid-api-key", key]
    if clean.clean_bool(cfg.get("unraid_api_enabled"), False):
        argv.append("--enable-unraid-api")
    return argv


def poll(ctx: PollContext) -> Dict[str, Any]:
    cache = _cache(ctx.state)
    enabled = bool(getattr(ctx.args, "enable_unraid_api", False)) and not ctx.homeassistant_mode
    interval = max(0.0, float(getattr(ctx.args, "unraid_api_interval", 5.0) or 0.0))

    if enabled and interval > 0.0 and (
        not cache.get("last_refresh_ts") or (ctx.now - float(cache.get("last_refresh_ts") or 0.0)) >= interval
    ):
        try:
            bundle = get_unraid_status_bundle(ctx.args.unraid_api_url, ctx.args.unraid_api_key, timeout=ctx.args.timeout)
            docker_items = normalize_unraid_docker_data(bundle.get("docker"))
            vm_items = normalize_unraid_vm_data(bundle.get("vms"))
            cache["bundle"] = bundle
            cache["docker_items"] = docker_items
            cache["docker_counts"] = _docker_summary_counts(docker_items)
            cache["vm_items"] = vm_items
            cache["vm_counts"] = _vm_summary_counts(vm_items)
            cache["available"] = True
            cache["api_ok"] = True
            cache["source"] = "unraid_graphql"
            cache["last_success_ts"] = ctx.now
            cache["last_error"] = ""
            cache["last_error_ts"] = 0.0
        except Exception as exc:
            cache["available"] = False
            cache["api_ok"] = False
            cache["source"] = "unraid_graphql"
            cache["last_error"] = str(exc).strip()[:200]
            cache["last_error_ts"] = ctx.now
            last_warn_ts = float(cache.get("last_warn_ts") or 0.0)
            if (ctx.now - last_warn_ts) >= UNRAID_WARN_INTERVAL_SECONDS:
                logging.warning(
                    "Unraid API unavailable via %s; continuing with local fallback sources (%s)",
                    getattr(ctx.args, "unraid_api_url", UNRAID_API_DEFAULT_URL),
                    exc,
                )
                cache["last_warn_ts"] = ctx.now
        cache["last_refresh_ts"] = ctx.now

    if not enabled:
        cache["available"] = None
        cache["api_ok"] = None
        cache["source"] = "disabled"
        cache["bundle"] = {}
        cache["docker_items"] = []
        cache["docker_counts"] = dict(UNRAID_DEFAULT_COUNTS)
        cache["vm_items"] = []
        cache["vm_counts"] = dict(UNRAID_DEFAULT_VM_COUNTS)

    last_refresh_ts = float(cache.get("last_refresh_ts") or 0.0)
    last_success_ts = float(cache.get("last_success_ts") or 0.0)
    last_error_ts = float(cache.get("last_error_ts") or 0.0)
    last_error = str(cache.get("last_error") or "").strip()
    bundle = dict(cache.get("bundle") or {})
    return {
        "enabled": enabled,
        "api_ok": cache.get("api_ok"),
        "source": cache.get("source") or "disabled",
        "bundle": bundle,
        "array": dict(bundle.get("array") or {}) if isinstance(bundle.get("array"), dict) else {},
        "info": dict(bundle.get("info") or {}) if isinstance(bundle.get("info"), dict) else {},
        "docker_items": list(cache.get("docker_items") or []),
        "docker_counts": dict(cache.get("docker_counts") or UNRAID_DEFAULT_COUNTS),
        "vm_items": list(cache.get("vm_items") or []),
        "vm_counts": dict(cache.get("vm_counts") or UNRAID_DEFAULT_VM_COUNTS),
        "health": {
            "integration_id": "unraid",
            "enabled": enabled,
            "available": cache.get("available"),
            "source": str(cache.get("source") or "disabled"),
            "last_refresh_ts": last_refresh_ts or None,
            "last_success_ts": last_success_ts or None,
            "last_error": last_error or None,
            "last_error_ts": last_error_ts or None,
            "commands": [],
            "api_ok": cache.get("api_ok"),
        },
    }


UNRAID_INTEGRATION = IntegrationSpec(
    integration_id="unraid",
    title="Unraid API",
    section_key="unraid_api",
    icon_class="mdi-server-network",
    sort_order=15,
    action_group_title="Unraid API",
    config_fields=UNRAID_CONFIG_FIELDS,
    validate_cfg=validate_cfg,
    cfg_to_agent_args=cfg_to_agent_args,
    poll=poll,
)
