#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_path="$repo_root/tests/fixtures/OllamaDataSmoke.qml"
output="$(mktemp)"
home_root="$(mktemp -d)"
home="$home_root/home space;literal"
test_config_root="$home_root/tests/fixtures"
test_config_path="$test_config_root/OllamaDataSmoke.qml"
launcher_dir="$(mktemp -d)"
mkdir -p "$home/.cache" "$test_config_root/modules"
cp "$config_path" "$test_config_path"
cp "$repo_root/versions/V1/modules/OllamaData.qml" \
    "$repo_root/versions/V1/modules/OllamaDataLogic.js" \
    "$repo_root/versions/V1/modules/OllamaRuntimeConfig.qml" \
    "$repo_root/versions/V1/modules/OllamaPullLogic.js" \
    "$repo_root/versions/V1/modules/OllamaGpuSampler.qml" \
    "$repo_root/versions/V1/modules/OllamaGpuLogic.js" \
    "$test_config_root/modules/"
ln -s "$(type -P true)" "$launcher_dir/omarchy-launch-floating-terminal-with-presentation"
printf '%s\n' '{"keepAlive":"30m","numCtx":null,"dirty":true}' > "$home/.cache/qs-ollama-config.json"
trap 'rm -f "$output"; rm -rf "$home_root" "$launcher_dir"' EXIT

if timeout --kill-after=1s 2s env HOME="$home" EDITOR=editor PATH="$launcher_dir:$PATH" \
    QT_QPA_PLATFORM=offscreen qs --no-color -p "$test_config_path" >"$output" 2>&1; then
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
