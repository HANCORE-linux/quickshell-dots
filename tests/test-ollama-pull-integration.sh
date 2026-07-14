#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
fixture_log="$fixture_root/requests.log"
fixture_port_file="$fixture_root/port"
fixture_script="$fixture_root/server.py"
fixture_pid=""
config_path="$repo_root/tests/fixtures/OllamaPullIntegrationSmoke.qml"
test_config_root="$fixture_root/test-config"
test_config_path="$test_config_root/tests/fixtures/OllamaPullIntegrationSmoke.qml"
runner_path="$test_config_root/versions/V1/FixtureRunner.qml"

mkdir -p "$test_config_root/tests/fixtures" "$test_config_root/versions/V1/modules"
cp "$config_path" "$test_config_path"
cp "$repo_root/versions/V1/modules/OllamaData.qml" \
    "$repo_root/versions/V1/modules/OllamaDataLogic.js" \
    "$test_config_root/versions/V1/modules/"

cleanup() {
    [[ -n "$fixture_pid" ]] && kill "$fixture_pid" 2>/dev/null || true
    rm -rf "$fixture_root"
}
trap cleanup EXIT

cat >"$runner_path" <<'QML'
import QtQuick
import Quickshell
import "modules"

ShellRoot {
    property var fixture

    Component.onCompleted: {
        var component = Qt.createComponent(Quickshell.env("QML_FIXTURE_PATH"))
        if (component.status !== Component.Ready) {
            console.error(component.errorString())
            Qt.quit()
            return
        }
        fixture = component.createObject(null)
    }
}
QML

cat >"$fixture_script" <<'PY'
import http.server
import json
import os
import select
import socketserver
import sys
import time

root, mode = sys.argv[1:]
log_path = os.path.join(root, "requests.log")
pulls = 0
tags = 0

def log(value):
    with open(log_path, "a", encoding="utf-8") as stream:
        stream.write(value + "\n")
        stream.flush()

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def reply(self, body):
        encoded = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        global tags
        if self.path != "/api/tags":
            self.reply('{"models":[]}')
            return
        tags += 1
        log("tags")
        if mode == "stale":
            time.sleep(0.4)
            self.reply('{"models":[{"name":"stale:model","details":{}}]}')
            return
        visible = mode in ("success", "retry") or (mode == "delayed" and tags >= 3)
        self.reply(json.dumps({"models": [{"name": "fixture:model", "details": {}}] if visible else []}))

    def do_POST(self):
        global pulls
        if self.path != "/api/pull":
            self.send_error(404)
            return
        pulls += 1
        log("pull")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(b'{"status":"downloading","completed":1,"total":2}\n')
        self.wfile.flush()
        if mode == "cancel" or (mode == "retry" and pulls == 1):
            try:
                for _ in range(100):
                    time.sleep(0.05)
                    ready, _, _ = select.select([self.connection], [], [], 0)
                    if ready and not self.connection.recv(1):
                        log("disconnect")
                        return
                    self.wfile.write(b'\n')
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                log("disconnect")
            return
        self.wfile.write(b'{"status":"success"}\n')
        self.wfile.flush()

class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

server = Server(("127.0.0.1", 0), Handler)
with open(os.path.join(root, "port"), "w", encoding="utf-8") as stream:
    stream.write(str(server.server_port))
server.serve_forever()
PY

run_case() {
    local mode="$1"
    : >"$fixture_log"
    python "$fixture_script" "$fixture_root" "$mode" &
    fixture_pid="$!"
    for _ in {1..50}; do
        [[ -s "$fixture_port_file" ]] && break
        sleep 0.05
    done
    [[ -s "$fixture_port_file" ]] || { printf 'fixture did not start\n' >&2; exit 1; }

    local output status=0
    output="$(mktemp)"
    if timeout --kill-after=1s 20s env QT_QPA_PLATFORM=offscreen \
        QML_FIXTURE_PATH="$test_config_path" \
        OLLAMA_PULL_TEST_CASE="$mode" \
        OLLAMA_PULL_TEST_URL="http://127.0.0.1:$(<"$fixture_port_file")" \
        qs --no-color -p "$runner_path" >"$output" 2>&1; then
        status=0
    else
        status=$?
    fi
    if [[ "$status" -ne 0 ]] || ! grep -Fq "OLLAMA_PULL_INTEGRATION_PASS: $mode" "$output"; then
        command cat "$output"
        rm -f "$output"
        exit 1
    fi
    rm -f "$output"

    if [[ "$mode" == "cancel" ]]; then
        grep -Fxq pull "$fixture_log"
        grep -Fxq disconnect "$fixture_log"
        ! grep -Fxq tags "$fixture_log"
    fi
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
    fixture_pid=""
    rm -f "$fixture_port_file"
}

run_case cancel
run_case success
run_case delayed
run_case timeout
run_case retry
run_case stale
printf '%s\n' "ollama pull integration: PASS"
