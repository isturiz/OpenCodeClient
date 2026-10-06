#!/usr/bin/env python3
"""Validate the installed V2 API in an isolated, disposable foreground server.

No shared service is stopped or modified. Prompts use resume=false: no inference
or tool execution occurs. Keep output to contract checks, never response bodies.
"""

import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request


def main():
    binary = shutil.which("opencode")
    if not binary:
        raise RuntimeError("Install OpenCode before running this check.")
    temporary_root = os.environ.get("TMPDIR", tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix="opencode-client-api-", dir=temporary_root) as root:
        root = Path(root)
        workspace = root / "workspace"
        workspace.mkdir()
        (workspace / "fixture #%.txt").write_text("fixture content", encoding="utf-8")
        subprocess.run(["git", "init", "--quiet", str(workspace)], check=True)
        home = root / "home"
        home.mkdir()
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        password = secrets.token_urlsafe(32)
        environment = {key: value for key, value in os.environ.items() if not key.startswith("OPENCODE_")}
        environment.update(
            HOME=str(home),
            XDG_CONFIG_HOME=str(home / "config"),
            XDG_DATA_HOME=str(home / "data"),
            XDG_STATE_HOME=str(home / "state"),
            XDG_CACHE_HOME=str(home / "cache"),
            OPENCODE_DB=str(root / "test.db"),
            OPENCODE_SERVER_PASSWORD=password,
            OPENCODE_SERVER_USERNAME="opencode",
        )
        authorization = "Basic " + base64.b64encode(f"opencode:{password}".encode()).decode()
        base = f"http://127.0.0.1:{port}"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def request(path, method="GET", body=None, query=None, raw=False):
            url = base + path + ("?" + urllib.parse.urlencode(query) if query else "")
            headers = {
                "Authorization": authorization,
                "Content-Type": "application/json",
                "Accept": "*/*" if raw else "application/json",
            }
            payload = json.dumps(body).encode() if body is not None else None
            with opener.open(urllib.request.Request(url, payload, headers, method=method), timeout=15) as response:
                content = response.read()
                return content if raw else (json.loads(content) if content else None)

        # Do not print server output: even isolated logs could contain request data.
        process = subprocess.Popen(
            [binary, "serve", "--hostname", "127.0.0.1", "--port", str(port)],
            cwd=workspace,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        stream = None
        try:
            deadline = time.monotonic() + 45
            while True:
                if process.poll() is not None:
                    raise RuntimeError("Isolated server exited before becoming ready.")
                try:
                    info = request("/api/info")
                    assert isinstance(info["version"], str)
                    break
                except (urllib.error.URLError, TimeoutError):
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Isolated server did not become ready in time.") from None
                    time.sleep(0.2)
            print("PASS: server info (no patch-version gate)")
            location = {"directory": str(workspace)}
            scope = {"directory": str(workspace)}
            location_scope = {**scope, "location[directory]": str(workspace)}

            created = request("/api/session", "POST", {"location": location}, scope)["data"]
            session_id = created["id"]
            assert created["location"] == location
            session_path = "/api/session/" + session_id
            assert request(session_path, query=scope)["data"]["id"] == session_id
            request(session_path, "PATCH", {"title": "Fixture session"}, scope)
            assert request(session_path, query=scope)["data"]["title"] == "Fixture session"
            listed = request("/api/session", query=scope)
            assert "cursor" in listed and any(row["id"] == session_id for row in listed["data"])
            assert isinstance(request("/api/project"), list)
            print("PASS: projects, session location, rename and paginated list")

            files = request("/api/fs/list", query={**location_scope, "path": ""})["data"]
            assert any(row["path"] == "fixture #%.txt" for row in files)
            path = urllib.parse.quote("fixture #%.txt", safe="")
            assert request("/api/fs/read/" + path, query=location_scope, raw=True) == b"fixture content"
            print("PASS: location-scoped listing and raw file bytes")

            agents = request("/api/agent", query=location_scope)["data"]
            models = request("/api/model", query=location_scope)["data"]
            assert isinstance(models, list) and isinstance(agents, list)
            primary = next((row for row in agents if not row["hidden"] and row["mode"] in ("primary", "all")), None)
            if primary:
                request(session_path + "/agent", "POST", {"agent": primary["id"]}, scope)
            if models:
                model = models[0]
                request(session_path + "/model", "POST", {"model": {"id": model["id"], "providerID": model["providerID"]}}, scope)
            print("PASS: model catalog and session selections")

            stream = opener.open(
                urllib.request.Request(base + "/api/event", headers={"Authorization": authorization, "Accept": "text/event-stream"}),
                timeout=10,
            )
            events = []

            def read_events():
                try:
                    for line in stream:
                        if line.startswith(b"data:"):
                            event = json.loads(line[5:])
                            events.append(event)
                            if event.get("type") == "session.inbox.enqueued":
                                return
                except (OSError, ValueError):
                    return

            thread = threading.Thread(target=read_events, daemon=True)
            thread.start()
            admitted = request(session_path + "/prompt", "POST", {"id": "msg_fixture", "text": "Fixture prompt", "resume": False}, scope)["data"]
            assert admitted["id"] == "msg_fixture"
            thread.join(timeout=10)
            assert any(event.get("type") == "server.connected" for event in events)
            assert any(event.get("type") == "session.inbox.enqueued" for event in events)
            messages = request(session_path + "/message", query={**scope, "limit": "100", "order": "desc"})
            assert "data" in messages and "cursor" in messages
            assert isinstance(request(session_path + "/permission", query=scope)["data"], list)
            assert isinstance(request("/api/session/active", query=scope)["data"], dict)
            request(session_path + "/interrupt", "POST", query={**scope, "resume": "false"})
            assert isinstance(request(session_path + "/diff", query=scope)["data"], list)
            print("PASS: durable admission, live SSE, timeline, permissions, active status and interrupt")
        finally:
            if stream:
                stream.close()
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Keep errors useful without leaking URLs, credentials or response bodies.
        line = traceback.extract_tb(error.__traceback__)[-1].lineno
        print(f"FAIL: {type(error).__name__} at line {line}; isolated server stopped, shared services unchanged.")
        raise SystemExit(1) from None
