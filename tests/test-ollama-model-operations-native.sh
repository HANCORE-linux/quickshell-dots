#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
output="$fixture_root/output.log"
test_config_root="$fixture_root/tests/fixtures"
test_config_path="$test_config_root/OllamaModelOperationsSmoke.qml"

mkdir -p "$test_config_root/modules"
cp "$repo_root/tests/fixtures/OllamaModelOperationsSmoke.qml" "$test_config_path"
cp "$repo_root/versions/V1/modules/OllamaModelOperations.qml" \
    "$repo_root/versions/V1/modules/OllamaDataLogic.js" \
    "$test_config_root/modules/"

trap 'rm -rf "$fixture_root"' EXIT

if timeout --kill-after=1s 4s env -u WAYLAND_DISPLAY \
    QT_QPA_PLATFORM=offscreen \
    qs --no-color -p "$test_config_path" >"$output" 2>&1; then
    status=0
else
    status=$?
fi

if [[ "$status" -ne 0 ]] \
    || grep -Fq "OLLAMA_MODEL_OPERATIONS_NATIVE_FAIL" "$output" \
    || grep -Fq "Failed to load configuration" "$output" \
    || ! grep -Fq "OLLAMA_MODEL_OPERATIONS_NATIVE_PASS" "$output"; then
    command cat "$output"
    exit 1
fi

command cat "$output"
printf '%s\n' "Ollama model operations native smoke: PASS"
