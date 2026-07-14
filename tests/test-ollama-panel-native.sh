#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
output="$fixture_root/output.log"
home="$fixture_root/home"
test_config_root="$fixture_root/tests/fixtures"
test_config_path="$test_config_root/OllamaPanelSectionsSmoke.qml"

mkdir -p "$home/.cache" "$test_config_root/modules" \
    "$test_config_root/panels/ollama"
cp "$repo_root/tests/fixtures/OllamaPanelSectionsSmoke.qml" "$test_config_path"
cp "$repo_root/versions/V1/panels/ollama/OllamaModelsSection.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaModelRow.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaDeleteButton.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaPanelHeader.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaSummarySection.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaDetailRow.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaPullSection.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaConfigSection.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaConfigurationToggle.qml" \
    "$repo_root/versions/V1/panels/ollama/OllamaPanelLayout.js" \
    "$test_config_root/panels/ollama/"
cp "$repo_root/versions/V1/modules/UiText.qml" \
    "$repo_root/versions/V1/modules/IconText.qml" \
    "$repo_root/versions/V1/modules/TooltipMixin.qml" \
    "$test_config_root/modules/"

trap 'rm -rf "$fixture_root"' EXIT

if timeout --kill-after=1s 4s env -u WAYLAND_DISPLAY HOME="$home" \
    QT_QPA_PLATFORM=offscreen \
    qs --no-color -p "$test_config_path" >"$output" 2>&1; then
    status=0
else
    status=$?
fi

if [[ "$status" -ne 0 ]] \
    || grep -Fq "OLLAMA_PANEL_SECTIONS_NATIVE_FAIL" "$output" \
    || grep -Fq "Failed to load configuration" "$output" \
    || ! grep -Fq "OLLAMA_PANEL_SECTIONS_NATIVE_PASS" "$output"; then
    command cat "$output"
    exit 1
fi

command cat "$output"
printf '%s\n' "Ollama panel sections native smoke: PASS"
