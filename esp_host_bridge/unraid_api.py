from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any, Optional

from .metrics import normalize_docker_data, safe_float

UNRAID_API_DEFAULT_URL = "http://127.0.0.1/graphql"
UNRAID_API_FALLBACK_URLS = ("http://127.0.0.1:3001/graphql",)


def _normalize_disk_token(value: Any) -> str:
    text = str(value or "").strip().lower()
    if not text:
        return ""
    for prefix in ("/dev/", "/devices/", "/disk/by-id/"):
        if text.startswith(prefix):
            text = text[len(prefix):]
    return text


def _classify_vm_state(state_raw: Any) -> tuple[str, str]:
    text = str(state_raw or "").strip().lower()
    if not text:
        return "stopped", "Stopped"
    if any(token in text for token in ("running", "idle", "in shutdown", "shutdown", "no state")):
        return "running", "Running"
    if any(token in text for token in ("paused", "pmsuspended", "suspended", "blocked")):
        return "paused", "Paused"
    if any(token in text for token in ("shut off", "shutoff", "crashed")):
        return "stopped", "Stopped"
    return "other", text.title()


def normalize_unraid_docker_data(v: Any) -> list[dict[str, Any]]:
    rows = normalize_docker_data(v)
    out: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        names = row.get("names")
        if isinstance(names, list) and names:
            raw_name = names[0]
        else:
            raw_name = row.get("name") or row.get("Names") or "container"
        name = str(raw_name or "container").strip().lstrip("/") or "container"
        state = str(row.get("state") or row.get("State") or "").strip().lower()
        status = str(row.get("status") or row.get("Status") or "").strip()
        out.append(
            {
                "id": row.get("id"),
                "name": name,
                "Names": [f"/{name}"],
                "state": state,
                "State": state,
                "status": status,
                "Status": status,
                "auto_start": bool(row.get("autoStart")),
            }
        )
    return out


def normalize_unraid_vm_data(v: Any) -> list[dict[str, Any]]:
    rows = v.get("domain") if isinstance(v, dict) else v
    if not isinstance(rows, list):
        return []
    out: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "VM").strip() or "VM"
        state_raw = row.get("state")
        _state_key, state_label = _classify_vm_state(state_raw)
        out.append(
            {
                "id": row.get("id"),
                "uuid": row.get("uuid"),
                "name": name,
                "state": state_raw,
                "vcpus": 0,
                "max_mem_mib": 0,
                "state_label": state_label,
            }
        )
    return out


def get_unraid_cpu_percent(bundle: dict[str, Any]) -> Optional[float]:
    metrics = bundle.get("metrics")
    if not isinstance(metrics, dict):
        return None
    cpu = metrics.get("cpu")
    if not isinstance(cpu, dict):
        return None
    rows = cpu.get("cpus")
    if not isinstance(rows, list):
        return None
    vals: list[float] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        val = safe_float(row.get("percentTotal"), None)
        if val is None:
            continue
        vals.append(max(0.0, min(100.0, float(val))))
    if not vals:
        return None
    return sum(vals) / float(len(vals))


def get_unraid_mem_percent(bundle: dict[str, Any]) -> Optional[float]:
    metrics = bundle.get("metrics")
    if not isinstance(metrics, dict):
        return None
    memory = metrics.get("memory")
    if not isinstance(memory, dict):
        return None
    pct = safe_float(memory.get("percentTotal"), None)
    if pct is not None:
        return max(0.0, min(100.0, float(pct)))
    used = safe_float(memory.get("used"), None)
    total = safe_float(memory.get("total"), None)
    if used is None or total is None or total <= 0:
        return None
    return max(0.0, min(100.0, (float(used) * 100.0) / float(total)))


def get_unraid_array_usage_pct(bundle: dict[str, Any]) -> Optional[float]:
    array = bundle.get("array")
    if not isinstance(array, dict):
        return None
    capacity = array.get("capacity")
    if not isinstance(capacity, dict):
        return None
    disks = capacity.get("disks")
    if not isinstance(disks, dict):
        return None
    used = safe_float(disks.get("used"), None)
    total = safe_float(disks.get("total"), None)
    if used is None or total is None or total <= 0:
        return None
    return max(0.0, min(100.0, (float(used) * 100.0) / float(total)))


def get_unraid_disk_temp_c(bundle: dict[str, Any], disk_device: Optional[str] = None) -> Optional[float]:
    disk_rows = bundle.get("disks")
    if isinstance(disk_rows, list):
        preferred = _select_unraid_disk_temp(disk_rows, disk_device=disk_device)
        if preferred is not None:
            return preferred
    array = bundle.get("array")
    if not isinstance(array, dict):
        return None
    rows = array.get("disks")
    if not isinstance(rows, list):
        return None
    hint_name = _normalize_disk_token(disk_device)
    temps: list[float] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        temp = safe_float(row.get("temp"), None)
        if temp is None or not (-20.0 <= temp <= 150.0):
            continue
        temp = float(temp)
        temps.append(temp)
        if hint_name:
            for candidate in (row.get("name"), row.get("device"), row.get("id"), row.get("serial"), row.get("mountpoint")):
                if _normalize_disk_token(candidate) == hint_name:
                    return temp
    if temps:
        return max(temps)
    return None


def get_unraid_disk_inventory(url: str, api_key: str, timeout: float) -> list[dict[str, Any]]:
    data = _unraid_graphql_request(
        url,
        api_key,
        """
        query {
          disks {
            name
            device
            type
            size
            smartStatus
            temperature
            isSpinning
            vendor
            interfaceType
            firmwareRevision
            serialNum
          }
        }
        """,
        timeout,
    )
    rows = data.get("disks")
    return rows if isinstance(rows, list) else []


def get_unraid_status_bundle(url: str, api_key: str, timeout: float) -> dict[str, Any]:
    data = _unraid_graphql_request(
        url,
        api_key,
        """
        query {
          info {
            os {
              platform
              distro
              release
              uptime
            }
            cpu {
              manufacturer
              brand
              cores
              threads
            }
          }
          metrics {
            cpu {
              cpus {
                percentTotal
              }
            }
            memory {
              percentTotal
              used
              total
            }
          }
          array {
            state
            capacity {
              disks {
                free
                used
                total
              }
            }
            disks {
              name
              size
              status
              temp
            }
          }
          docker {
            containers {
              id
              names
              state
              status
              autoStart
            }
          }
          vms {
            domain {
              id
              name
              state
              uuid
            }
          }
        }
        """,
        timeout,
    )
    out: dict[str, Any] = {
        "info": data.get("info") if isinstance(data.get("info"), dict) else {},
        "metrics": data.get("metrics") if isinstance(data.get("metrics"), dict) else {},
        "array": data.get("array") if isinstance(data.get("array"), dict) else {},
        "docker": data.get("docker") if isinstance(data.get("docker"), dict) else {},
        "vms": data.get("vms") if isinstance(data.get("vms"), dict) else {},
    }
    return out


def get_unraid_optional_overview(url: str, api_key: str, timeout: float) -> dict[str, Any]:
    data = _unraid_graphql_request(
        url,
        api_key,
        """
        query {
          server {
            name
            status
            lanip
            localurl
            remoteurl
          }
          services {
            name
            online
            version
          }
          shares {
            name
            free
            used
            size
            cache
            comment
            luksStatus
          }
          plugins {
            name
            version
            hasApiModule
            hasCliModule
          }
          disks {
            name
            device
            type
            size
            smartStatus
            temperature
            isSpinning
            vendor
            interfaceType
            firmwareRevision
            serialNum
          }
        }
        """,
        timeout,
    )
    return {
        "server": data.get("server") if isinstance(data.get("server"), dict) else {},
        "services": data.get("services") if isinstance(data.get("services"), list) else [],
        "shares": data.get("shares") if isinstance(data.get("shares"), list) else [],
        "plugins": data.get("plugins") if isinstance(data.get("plugins"), list) else [],
        "disks": data.get("disks") if isinstance(data.get("disks"), list) else [],
    }


def _unraid_graphql_request(url: str, api_key: str, query: str, timeout: float) -> dict[str, Any]:
    endpoint = str(url or "").strip()
    if not endpoint:
        raise RuntimeError("Unraid API URL is not configured")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    key = str(api_key or "").strip()
    if key:
        headers["x-api-key"] = key
    endpoints: list[str] = []
    seen: set[str] = set()
    for candidate in [endpoint, UNRAID_API_DEFAULT_URL, *UNRAID_API_FALLBACK_URLS]:
        text = str(candidate or "").strip()
        if text and text not in seen:
            seen.add(text)
            endpoints.append(text)
    last_error = "unknown error"
    response_body = ""
    for candidate in endpoints:
        req = urllib.request.Request(
            candidate,
            data=json.dumps({"query": query}).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=max(1.0, float(timeout))) as resp:  # nosec B310 - caller controls endpoint
                response_body = resp.read().decode("utf-8", errors="ignore")
            break
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="ignore") if hasattr(exc, "read") else ""
            last_error = f"{candidate}: HTTP {exc.code}: {detail or exc.reason}"
        except Exception as exc:  # pragma: no cover - depends on runtime networking
            last_error = f"{candidate}: request failed: {exc}"
    else:
        raise RuntimeError(f"Unraid API request failed after fallback attempts ({last_error})")

    try:
        payload = json.loads(response_body)
    except Exception as exc:
        raise RuntimeError("Unraid API returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise RuntimeError("Unraid API returned an invalid response payload")
    errors = payload.get("errors")
    if isinstance(errors, list) and errors:
        msg = "; ".join(str(row.get("message") or "GraphQL error") for row in errors if isinstance(row, dict))
        raise RuntimeError(msg or "Unraid API returned GraphQL errors")
    data = payload.get("data")
    if not isinstance(data, dict):
        raise RuntimeError("Unraid API response is missing data")
    return data


def _select_unraid_disk_temp(rows: list[dict[str, Any]], disk_device: Optional[str] = None) -> Optional[float]:
    hint = _normalize_disk_token(disk_device)
    temps: list[float] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        temp = safe_float(row.get("temperature"), None)
        if temp is None or not (-20.0 <= temp <= 150.0):
            continue
        temp = float(temp)
        temps.append(temp)
        if hint:
            for candidate in (row.get("name"), row.get("device"), row.get("serialNum"), row.get("serial")):
                if _normalize_disk_token(candidate) == hint:
                    return temp
    if temps:
        return max(temps)
    return None


__all__ = [
    "UNRAID_API_DEFAULT_URL",
    "UNRAID_API_FALLBACK_URLS",
    "get_unraid_array_usage_pct",
    "get_unraid_cpu_percent",
    "get_unraid_disk_inventory",
    "get_unraid_disk_temp_c",
    "get_unraid_mem_percent",
    "get_unraid_optional_overview",
    "get_unraid_status_bundle",
    "normalize_unraid_docker_data",
    "normalize_unraid_vm_data",
]
