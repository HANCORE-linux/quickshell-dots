#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$(mktemp)"
home_root="$(mktemp -d)"
home="$home_root/home space;literal"
launcher_dir="$(mktemp -d)"
mkdir -p "$home/.cache"
ln -s "$(type -P true)" "$launcher_dir/omarchy-launch-floating-terminal-with-presentation"
printf '%s\n' '{"keepAlive":"30m","numCtx":null,"dirty":true}' > "$home/.cache/qs-ollama-config.json"
trap 'rm -f "$output"; rm -rf "$home_root" "$launcher_dir"' EXIT

if timeout --kill-after=1s 2s env HOME="$home" EDITOR=editor PATH="$launcher_dir:$PATH" QT_QPA_PLATFORM=offscreen \
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
