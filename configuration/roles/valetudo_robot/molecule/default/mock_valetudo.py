#!/usr/bin/env python3
"""Mock of the Valetudo REST API for the valetudo_robot Molecule scenario.

Standard library only. It implements the version GET, the auth configuration
GET/PUT (with enforcement once auth is enabled), the Wi-Fi configuration PUT and
one generic capability GET/PUT. Every request is appended to a JSON lines log
with the Authorization header recorded as "present" or "absent" only, never its
value, and without any request body.

Endpoint paths follow Valetudo's documented v2 API; verify at recon (plan Task 0).

Start-up flag --scenario selects a failure mode:
  auth_mismatch    auth is pre-enabled with credentials that differ from anything
                   the role sends.
  auth_put_ignored an auth PUT is acknowledged with 200 but enables auth with the
                   preset credentials instead, so the role's re-probe fails.
  auth_put_noop    an auth PUT is acknowledged with 200 but changes nothing, so auth
                   stays disabled and only a re-read of the auth state shows it.
  wifi_drop        a valid Wi-Fi PUT is logged (status 0) and the connection is
                   closed without any response, like a robot leaving its AP.
"""

import argparse
import base64
import binascii
import hmac
import json
import re
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION_PATH = "/api/v2/valetudo/version"
AUTH_PATH = "/api/v2/valetudo/config/interfaces/http/auth"
CAPABILITIES_PATH = "/api/v2/robot/capabilities"
WIFI_PATH = "/api/v2/robot/capabilities/WifiConfigurationCapability"
CAPABILITY_RE = re.compile(r"^/api/v2/robot/capabilities/([A-Za-z]+)$")
MAX_BODY_BYTES = 65536

# Generated per process, so no credential literal is committed and the values
# differ from anything the role or Molecule sends.
PRESET_USERNAME = f"mock-preset-{secrets.token_hex(4)}"
PRESET_PASSWORD = secrets.token_hex(16)


class MockState:
    """Mutable server state shared by all request threads."""

    def __init__(self, scenario: str, log_path: str) -> None:
        self.lock = threading.Lock()
        self.scenario = scenario
        self.log_path = log_path
        self.auth_enabled = scenario == "auth_mismatch"
        self.auth_username = PRESET_USERNAME if self.auth_enabled else ""
        self.auth_password = PRESET_PASSWORD if self.auth_enabled else ""
        self.wifi_ssid: str | None = None
        self.capabilities: dict[str, dict] = {}


def make_handler(state: MockState) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "MockValetudo/1.0"

        def log_message(self, format: str, *args: object) -> None:  # noqa: A002
            """Silence the default stderr logging; the JSON log is the record."""

        def _authorized(self) -> bool:
            header = self.headers.get("Authorization", "")
            scheme, _, encoded = header.partition(" ")
            if scheme.lower() != "basic":
                return False
            try:
                decoded = base64.b64decode(encoded.strip(), validate=True)
            except (binascii.Error, ValueError):
                return False
            expected = f"{state.auth_username}:{state.auth_password}".encode()
            return hmac.compare_digest(decoded, expected)

        def _read_json(self) -> object:
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                return None
            if length <= 0 or length > MAX_BODY_BYTES:
                return None
            try:
                return json.loads(self.rfile.read(length))
            except ValueError:
                return None

        def _finish(
            self, status: int, payload: object, headers: dict | None = None
        ) -> None:
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            for name, value in (headers or {}).items():
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(body)
            self._record(status)

        def _record(self, status: int) -> None:
            entry = {
                "method": self.command,
                "path": self.path.split("?", 1)[0],
                "authorization": "present"
                if self.headers.get("Authorization")
                else "absent",
                "status": status,
            }
            with Path(state.log_path).open("a", encoding="utf-8") as log:
                log.write(json.dumps(entry, sort_keys=True) + "\n")

        def _route(self, method: str) -> None:
            path = self.path.split("?", 1)[0]
            with state.lock:
                if state.auth_enabled and not self._authorized():
                    self._finish(
                        401,
                        {"error": "unauthorized"},
                        {"WWW-Authenticate": 'Basic realm="mock"'},
                    )
                    return
                self._dispatch(method, path)

        def _dispatch(self, method: str, path: str) -> None:
            capability = CAPABILITY_RE.match(path)
            if method == "GET" and path == VERSION_PATH:
                self._finish(200, {"release": "mock", "commit": "mock"})
            elif method == "GET" and path == CAPABILITIES_PATH:
                self._finish(200, ["WifiConfigurationCapability"])
            elif path == AUTH_PATH:
                self._auth_config(method)
            elif path == WIFI_PATH:
                self._wifi(method)
            elif capability:
                self._capability(method, capability.group(1))
            else:
                self._finish(404, {"error": "not found"})

        def _auth_config(self, method: str) -> None:
            if method == "GET":
                self._finish(
                    200,
                    {"enabled": state.auth_enabled, "username": state.auth_username},
                )
                return
            body = self._read_json()
            valid = isinstance(body, dict) and isinstance(body.get("enabled"), bool)
            if valid and body["enabled"]:
                valid = all(
                    isinstance(body.get(key), str) and body[key]
                    for key in ("username", "password")
                )
            if not valid:
                self._finish(400, {"error": "invalid auth configuration"})
                return
            if state.scenario == "auth_put_ignored":
                state.auth_enabled = True
                state.auth_username = PRESET_USERNAME
                state.auth_password = PRESET_PASSWORD
                self._finish(200, {"status": "ok"})
                return
            if state.scenario == "auth_put_noop":
                self._finish(200, {"status": "ok"})
                return
            enabled = body["enabled"]
            state.auth_enabled = enabled
            state.auth_username = body["username"] if enabled else ""
            state.auth_password = body["password"] if enabled else ""
            self._finish(200, {"status": "ok"})

        def _wifi(self, method: str) -> None:
            if method == "GET":
                self._finish(200, {"ssid": state.wifi_ssid})
                return
            body = self._read_json()
            credentials = body.get("credentials") if isinstance(body, dict) else None
            settings = (
                credentials.get("typeSpecificSettings")
                if isinstance(credentials, dict)
                else None
            )
            valid = (
                isinstance(credentials, dict)
                and isinstance(body.get("ssid"), str)
                and bool(body["ssid"])
                and credentials.get("type") == "wpa2_psk"
                and isinstance(settings, dict)
                and isinstance(settings.get("password"), str)
                and bool(settings["password"])
            )
            if not valid:
                self._finish(400, {"error": "invalid wifi configuration"})
                return
            state.wifi_ssid = body["ssid"]
            if state.scenario == "wifi_drop":
                self._record(0)
                self.close_connection = True
                return
            self._finish(200, {"status": "ok"})

        def _capability(self, method: str, name: str) -> None:
            current = state.capabilities.setdefault(
                name, {"enabled": False, "level": "medium"}
            )
            if method == "GET":
                self._finish(200, current)
                return
            body = self._read_json()
            if not isinstance(body, dict):
                self._finish(400, {"error": "invalid capability body"})
                return
            current.update(body)
            self._finish(200, {"status": "ok"})

        def do_GET(self) -> None:
            self._route("GET")

        def do_PUT(self) -> None:
            self._route("PUT")

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--log", default="/tmp/requests.jsonl")
    parser.add_argument(
        "--scenario",
        choices=[
            "default",
            "auth_mismatch",
            "auth_put_ignored",
            "auth_put_noop",
            "wifi_drop",
        ],
        default="default",
    )
    args = parser.parse_args()
    state = MockState(args.scenario, args.log)
    Path(args.log).write_text("", encoding="utf-8")
    ThreadingHTTPServer((args.host, args.port), make_handler(state)).serve_forever()


if __name__ == "__main__":
    main()
