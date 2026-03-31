from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from esp_host_bridge.webui_app import create_app


class UnraidWebUiTests(unittest.TestCase):
    def test_api_status_merges_unraid_status_payload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            cfg_path = Path(td) / "config.json"
            cfg_path.write_text(
                json.dumps(
                    {
                        "serial_port": "",
                        "baud": 115200,
                        "interval": 1.0,
                        "timeout": 2.0,
                        "unraid_api_enabled": True,
                        "unraid_api_url": "http://127.0.0.1/graphql",
                        "unraid_api_key": "secret",
                    }
                ),
                encoding="utf-8",
            )
            with mock.patch.dict("os.environ", {"WEBUI_CONFIG": str(cfg_path), "AUTOSTART": "0"}, clear=False):
                with mock.patch(
                    "esp_host_bridge.webui_app.get_unraid_status_bundle",
                    return_value={"info": {"os": {"release": "7.2"}}, "array": {"state": "STARTED"}},
                ), mock.patch(
                    "esp_host_bridge.webui_app.get_unraid_optional_overview",
                    return_value={"server": {"name": "tower"}, "services": [], "shares": [], "plugins": [], "disks": []},
                ):
                    app = create_app(autostart_override=False)
                    client = app.test_client()
                    resp = client.get("/api/status")
                    self.assertEqual(resp.status_code, 200)
                    data = resp.get_json() or {}
                    status = data.get("unraid_status") or {}
                    self.assertTrue(status)
                    self.assertEqual(status.get("api_ok"), True)
                    self.assertEqual((status.get("array") or {}).get("state"), "STARTED")
                    self.assertEqual((status.get("server") or {}).get("name"), "tower")


if __name__ == "__main__":
    unittest.main()
