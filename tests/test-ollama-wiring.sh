#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
theme="$repo_root/versions/V1/Theme.qml"

assert_contains() {
    local file="$theme"
    if [[ $# -eq 2 ]]; then
        file="$repo_root/$1"
        shift
    fi
    local text="$1"
    grep -Fq "$text" "$file" || {
        printf 'missing %s in %s\n' "$text" "$file" >&2
        exit 1
    }
}

assert_matches() {
    local pattern="$1"
    grep -Eq "$pattern" "$theme" || {
        printf 'missing pattern %s in %s\n' "$pattern" "$theme" >&2
        exit 1
    }
}

assert_contains 'import "modules"'
assert_contains 'OllamaData {'
assert_contains 'id: ollamaData'
assert_contains 'enabled: theme.modOllama'
assert_contains 'property alias ollama: ollamaData'
assert_matches 'property bool modOllama:[[:space:]]+false'
assert_matches 'property bool compactOllama:[[:space:]]+false'
assert_contains 'property bool ollamaVisible: false'
assert_matches 'property real ollamaBarX:[[:space:]]+0'
assert_contains '|| ollamaVisible'
assert_contains 'if (except !== "ollamaVisible") ollamaVisible = false'
assert_contains 'else if (name === "ollama") ollamaBarX = x'
assert_contains 'onOllamaVisibleChanged: {'
assert_contains 'popupOpened("ollamaVisible")'
assert_contains 'if (ollamaVisible) ollama.refreshAll()'
assert_matches 'onModOllamaChanged:[[:space:]]+if \(_widgetsLoaded\) saveWidgets\(\)'
assert_matches 'onCompactOllamaChanged:[[:space:]]+if \(_widgetsLoaded && !_compactResetting\) saveWidgets\(\)'
assert_contains '|| compactOllama'
assert_contains 'compactOllama = false'
assert_matches '\(modOllama[[:space:]]+\? "1" : "0"\)'
assert_matches '\(compactOllama[[:space:]]+\? "1" : "0"\)'
assert_contains 'if (parts.length > wsField + 31) theme.modOllama = parts[wsField + 31] === "1"'
assert_contains 'if (parts.length > wsField + 32) theme.compactOllama = parts[wsField + 32] === "1"'

assert_contains versions/V1/BarSlot.qml 'Component { id: compOllama; OllamaWidget { root: barSlot.root } }'
assert_contains versions/V1/BarSlot.qml '"G16": compOllama'
assert_contains versions/V1/BarSlot.qml 'ollama:       island.groupX("G16", 0.5)'
assert_contains versions/V1/BarSlot.qml 'ListElement { gid: "G16" }'
assert_contains versions/V1/BarSlot.qml 'property var leftSplits:  [false, false, false, false, false, false, false]'
assert_contains versions/V1/modules/OllamaWidget.qml 'visible: !root.compactOllama'
assert_contains versions/V1/modules/OllamaWidget.qml 'source: Qt.resolvedUrl("../assets/ollama.svg")'

assert_contains versions/V1/shell.qml 'target: "ollama"'
assert_contains versions/V1/shell.qml 'OllamaPanel { root: theme }'
assert_contains versions/V1/panels/OllamaPanel.qml 'model: root.ollama.models'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.loadModel(modelData.name)'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.ejectModel(modelData.name)'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.openConfiguration()'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.reloadConfiguration()'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property bool refreshRunning: versionProc.running || tagsProc.running || loadedProc.running'
assert_contains versions/V1/panels/OllamaPanel.qml 'enabled: !root.ollama.refreshRunning'
assert_contains versions/V1/panels/OllamaPanel.qml 'opacity: refreshMa.enabled ? 1 : 0.35'
assert_contains versions/V1/panels/OllamaPanel.qml 'cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: root.ollama.connected && root.ollama.version !== ""'
assert_contains versions/V1/panels/OllamaPanel.qml 'color: root.ollama.connected && root.ollama.version !== "" ? root.seal : root.sumi'

assert_contains versions/V1/panels/ControlPanel.qml 'label: "Ollama";      active: root.modOllama'
assert_contains versions/V1/panels/ControlPanel.qml 'label: "Ollama";     active: root.compactOllama'
assert_contains README.md 'Ollama management'

printf 'ollama theme wiring: ok\n'
