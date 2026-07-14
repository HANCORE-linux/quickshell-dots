#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
fixture_log="$fixture_root/requests.log"
fixture_port_file="$fixture_root/port"
fixture_script="$fixture_root/server.py"
fixture_pid=""
config_path="$repo_root/tests/fixtures/OllamaLifecycleSmoke.qml"
test_config_root="$fixture_root/tests/fixtures"
test_config_path="$test_config_root/OllamaLifecycleSmoke.qml"
output="$fixture_root/qs.log"

cleanup() {
    [[ -n "$fixture_pid" ]] && kill "$fixture_pid" 2>/dev/null || true
    rm -rf "$fixture_root"
}
trap cleanup EXIT

mkdir -p "$test_config_root/modules"
cp "$config_path" "$test_config_path"
cp "$repo_root/versions/V1/modules/OllamaData.qml" \
    "$repo_root/versions/V1/modules/OllamaDataLogic.js" \
    "$repo_root/versions/V1/modules/OllamaPullLogic.js" \
    "$repo_root/versions/V1/modules/OllamaGpuSampler.qml" \
    "$repo_root/versions/V1/modules/OllamaGpuLogic.js" \
    "$test_config_root/modules/"

# Compress both the former intervals and the lifecycle interval in the test copy.
sed -i \
    -e 's/interval: 15000/interval: 120/g' \
    -e 's/interval: ollama.panelVisible ? 2000 : 15000/interval: 120/g' \
    -e 's/property int loadedPollIntervalMs: 2000/property int loadedPollIntervalMs: 120/' \
    "$test_config_root/modules/OllamaData.qml"

cat >"$fixture_script" <<'PY'
import http.server
import json
import os
import socketserver
import sys
import threading
import time

root = sys.argv[1]
log_path = os.path.join(root, "requests.log")
log_lock = threading.Lock()
state_lock = threading.Lock()
delay_next_ps = False


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        global delay_next_ps
        with log_lock:
            with open(log_path, "a", encoding="utf-8") as stream:
                stream.write(f"{time.monotonic_ns()} {self.path}\n")
                stream.flush()

        if self.path in (
            "/test/phase/delayed-open-start",
            "/test/phase/manual-pending-open-start",
        ):
            with state_lock:
                delay_next_ps = True
        delayed = False
        if self.path == "/api/ps":
            with state_lock:
                delayed = delay_next_ps
                delay_next_ps = False
        if delayed:
            time.sleep(0.35)

        if self.path == "/api/version":
            body = {"version": "fixture"}
        else:
            body = {"models": []}
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


server = Server(("127.0.0.1", 0), Handler)
with open(os.path.join(root, "port"), "w", encoding="utf-8") as stream:
    stream.write(str(server.server_port))
server.serve_forever()
PY

: >"$fixture_log"
python "$fixture_script" "$fixture_root" &
fixture_pid="$!"
for _ in {1..50}; do
    [[ -s "$fixture_port_file" ]] && break
    sleep 0.05
done
[[ -s "$fixture_port_file" ]] || { printf 'fixture did not start\n' >&2; exit 1; }

status=0
timeout --kill-after=1s 10s env QT_QPA_PLATFORM=offscreen \
    OLLAMA_LIFECYCLE_TEST_URL="http://127.0.0.1:$(<"$fixture_port_file")" \
    qs --no-color -p "$test_config_path" >"$output" 2>&1 || status=$?
if [[ "$status" -ne 0 ]] || grep -Fq 'OLLAMA_LIFECYCLE_FAIL' "$output" \
        || ! grep -Fq 'OLLAMA_LIFECYCLE_SEQUENCE_PASS' "$output"; then
    command cat "$output"
    exit 1
fi

python - "$fixture_log" <<'PY'
from collections import Counter
import sys

entries = []
with open(sys.argv[1], encoding="utf-8") as stream:
    for line in stream:
        timestamp, path = line.rstrip().split(" ", 1)
        entries.append((int(timestamp), path))

marker_names = [
    "disabled-end",
    "enable-closed-end",
    "closed-steady-end",
    "open-end",
    "close-end",
    "manual-end",
    "manual-steady-end",
    "delayed-open-start",
    "delayed-close-start",
    "delayed-close-end",
    "manual-pending-open-start",
    "manual-pending-close-start",
    "manual-pending-close-end",
    "done",
]
marker_paths = [f"/test/phase/{name}" for name in marker_names]
positions = []
for marker in marker_paths:
    matches = [index for index, (_, path) in enumerate(entries) if path == marker]
    if len(matches) != 1:
        raise SystemExit(f"expected one {marker} marker, got {len(matches)}")
    positions.append(matches[0])
if positions != sorted(positions):
    raise SystemExit("lifecycle markers are out of order")

api_paths = {"/api/version", "/api/tags", "/api/ps"}


def segment(start, end):
    return Counter(path for _, path in entries[start:end] if path in api_paths)


segments = {
    "disabled": segment(0, positions[0]),
    "enable closed": segment(positions[0] + 1, positions[1]),
    "closed steady": segment(positions[1] + 1, positions[2]),
    "open": segment(positions[2] + 1, positions[3]),
    "close settle": segment(positions[3] + 1, positions[4]),
    "manual refresh": segment(positions[4] + 1, positions[5]),
    "manual steady": segment(positions[5] + 1, positions[6]),
    "delayed open": segment(positions[7] + 1, positions[8]),
    "delayed close": segment(positions[8] + 1, positions[9]),
    "manual pending open": segment(positions[10] + 1, positions[11]),
    "manual pending close": segment(positions[11] + 1, positions[12]),
}

batch = Counter({"/api/version": 1, "/api/tags": 1, "/api/ps": 1})
if segments["disabled"]:
    raise SystemExit(f"disabled issued requests: {segments['disabled']}")
if segments["enable closed"] != batch:
    raise SystemExit(f"enable closed expected one batch, got {segments['enable closed']}")
if segments["closed steady"]:
    raise SystemExit(f"closed steady state polled: {segments['closed steady']}")
if segments["open"]["/api/version"] != 1 or segments["open"]["/api/tags"] != 1:
    raise SystemExit(f"open repeated non-/api/ps endpoints: {segments['open']}")
if segments["open"]["/api/ps"] < 3:
    raise SystemExit(f"open did not repeat /api/ps: {segments['open']}")
if set(segments["close settle"]) - {"/api/ps"} or segments["close settle"]["/api/ps"] > 1:
    raise SystemExit(f"close did not settle: {segments['close settle']}")
if segments["manual refresh"] != batch:
    raise SystemExit(f"manual refresh expected one batch, got {segments['manual refresh']}")
if segments["manual steady"]:
    raise SystemExit(f"manual refresh did not return to silence: {segments['manual steady']}")
if segments["delayed open"] != batch:
    raise SystemExit(f"delayed open expected one in-flight batch, got {segments['delayed open']}")
if segments["delayed close"]:
    raise SystemExit(f"timer queued /api/ps after close: {segments['delayed close']}")
if segments["manual pending open"] != batch:
    raise SystemExit(f"manual pending setup expected one batch, got {segments['manual pending open']}")
if segments["manual pending close"] != batch:
    raise SystemExit(f"manual pending follow-up was lost: {segments['manual pending close']}")

for name, counts in segments.items():
    print(f"{name}: {dict(counts)}")
PY

printf '%s\n' 'ollama lifecycle integration: PASS'
