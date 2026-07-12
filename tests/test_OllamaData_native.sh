#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(mktemp)"
trap 'rm -f "$output"' EXIT

if timeout --kill-after=1s 2s env QT_QPA_PLATFORM=offscreen \
    qs --no-color -p "$repo_root/versions/V1/OllamaDataSmoke.qml" >"$output" 2>&1; then
    status=0
else
    status=$?
fi

if grep -Fq "OLLAMA_DATA_NATIVE_FAIL" "$output" \
    || grep -Fq "Failed to load configuration" "$output" \
    || ! grep -Fq "OLLAMA_DATA_NATIVE_PASS" "$output"; then
    command cat "$output"
    exit 1
fi

if [[ "$status" -ne 0 ]]; then
    command cat "$output"
    exit "$status"
fi

command cat "$output"
printf '%s\n' "OllamaData native component test: PASS"
