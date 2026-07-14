#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
theme="$repo_root/versions/V1/Theme.qml"

for fixture in \
    "$repo_root"/versions/V1/*Smoke*.qml \
    "$repo_root"/versions/V1/*FixtureRunner*.qml \
    "$repo_root"/versions/V1/.fixture-runner.*.qml; do
    [[ ! -e "$fixture" ]] || {
        printf 'test fixture shipped in production payload: %s\n' "${fixture##*/}" >&2
        exit 1
    }
done

shopt -s dotglob globstar nullglob
for qml in "$repo_root"/versions/V1/**/*.qml; do
    [[ "$qml" == "$repo_root/versions/V1/shell.qml" ]] && continue
    ! grep -Pzq '(?m)^[\t ]*ShellRoot\s*\{' "$qml" || {
        printf 'unexpected ShellRoot in production payload: %s\n' "${qml#"$repo_root/"}" >&2
        exit 1
    }
done
shopt -u dotglob globstar nullglob

for runner in tests/test_OllamaData_native.sh tests/test-ollama-pull-integration.sh; do
    ! grep -Eq "versions/V1/[^[:space:]\"']*(FixtureRunner|fixture-runner|Smoke)[^[:space:]\"']*\\.qml" "$repo_root/$runner" || {
        printf 'test runner creates fixture root in production payload: %s\n' "$runner" >&2
        exit 1
    }
    ! grep -Pzq 'ShellRoot\s*\{' "$repo_root/$runner" || {
        printf 'test runner embeds ShellRoot: %s\n' "$runner" >&2
        exit 1
    }
done

for fixture in tests/fixtures/OllamaDataSmoke.qml tests/fixtures/OllamaPullIntegrationSmoke.qml; do
    grep -Fxq 'import "modules"' "$repo_root/$fixture" || {
        printf 'test fixture must use local modules: %s\n' "$fixture" >&2
        exit 1
    }
done

assert_contains() {
    local file="$theme"
    if [[ $# -eq 2 ]]; then
        file="$repo_root/$1"
        shift
    fi
    local text="$1"
    grep -Fq -- "$text" "$file" || {
        printf 'missing %s in %s\n' "$text" "$file" >&2
        exit 1
    }
}

assert_not_contains() {
    local file="$repo_root/$1"
    local text="$2"
    ! grep -Fq -- "$text" "$file" || {
        printf 'unexpected %s in %s\n' "$text" "$file" >&2
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

assert_file_matches() {
    local file="$repo_root/$1"
    local pattern="$2"
    grep -Pzq -- "$pattern" "$file" || {
        printf 'missing pattern %s in %s\n' "$pattern" "$file" >&2
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
assert_contains 'if (parts.length > wsField + 31) theme.archBadgeShell    = parts[wsField + 31] !== "0"'
assert_contains 'if (parts.length > wsField + 32) theme.modOllama = parts[wsField + 32] === "1"'
assert_contains 'if (parts.length > wsField + 33) theme.compactOllama = parts[wsField + 33] === "1"'

assert_contains versions/V1/BarSlot.qml 'Component { id: compOllama; OllamaWidget { root: barSlot.root } }'
assert_contains versions/V1/BarSlot.qml '"G16": compOllama'
assert_contains versions/V1/BarSlot.qml 'ollama:       island.groupX("G16", 0.5)'
assert_contains versions/V1/BarSlot.qml 'ListElement { gid: "G16" }'
assert_contains versions/V1/BarSlot.qml 'property var leftSplits:  [false, false, false, false, false, false, false]'
assert_contains versions/V1/modules/OllamaWidget.qml 'visible: !root.compactOllama'
assert_contains versions/V1/modules/OllamaWidget.qml 'source: Qt.resolvedUrl("../assets/ollama.svg")'

assert_contains versions/V1/shell.qml 'target: "ollama"'
assert_contains versions/V1/shell.qml 'OllamaPanel { root: theme }'
assert_contains versions/V1/modules/OllamaData.qml 'property bool operationInProgress: false'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property bool controlsLocked:'
assert_contains versions/V1/modules/OllamaData.qml 'property var selectedKeepAlive: "5m"'
assert_contains versions/V1/modules/OllamaData.qml 'property var selectedNumCtx: null'
assert_contains versions/V1/modules/OllamaData.qml 'property bool configDirty: false'
assert_contains versions/V1/modules/OllamaData.qml 'dirty: configDirty'
assert_contains versions/V1/modules/OllamaData.qml 'function buildLoadPayload(modelName)'
assert_contains versions/V1/modules/OllamaData.qml 'function applyRuntimeConfiguration()'
assert_contains versions/V1/modules/OllamaData.qml 'id: runtimeConfigFile'
assert_contains versions/V1/modules/OllamaData.qml 'path: runtimeConfigPath'
assert_contains versions/V1/modules/OllamaData.qml 'OllamaDataLogic.buildLoadPayload(modelName, 0, null)'
assert_contains versions/V1/modules/OllamaData.qml 'buildLoadPayload(pendingModel)'
assert_contains versions/V1/modules/OllamaData.qml 'loadedRefreshPending = true; return'
assert_contains versions/V1/modules/OllamaData.qml 'property int refreshEpoch: 0'
assert_contains versions/V1/modules/OllamaData.qml 'property string operationError: ""'
assert_contains versions/V1/modules/OllamaData.qml 'property string actionError: ""'
assert_contains versions/V1/modules/OllamaData.qml 'property string versionError: ""'
assert_contains versions/V1/modules/OllamaData.qml 'property string tagsError: ""'
assert_contains versions/V1/modules/OllamaData.qml 'property string loadedError: ""'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property bool connected:'
assert_contains versions/V1/modules/OllamaData.qml 'aggregateConnected'
assert_contains versions/V1/modules/OllamaData.qml 'aggregateError'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property string displayError: operationError !== "" ? operationError : lastError'
assert_contains versions/V1/modules/OllamaData.qml 'refreshEpoch += 1'
assert_contains versions/V1/modules/OllamaData.qml 'if (operationInProgress || versionProc.running) return'
assert_contains versions/V1/modules/OllamaData.qml 'tagsRefreshPending = true; return'
assert_contains versions/V1/modules/OllamaData.qml 'versionProc.refreshEpoch = refreshEpoch'
assert_contains versions/V1/modules/OllamaData.qml 'tagsProc.refreshEpoch = refreshEpoch'
assert_contains versions/V1/modules/OllamaData.qml 'loadedProc.refreshEpoch = refreshEpoch'
assert_contains versions/V1/modules/OllamaData.qml 'if (requestEpoch !== refreshEpoch) return'
assert_contains versions/V1/modules/OllamaData.qml 'OllamaDataLogic.generateResponseState(response.body)'
assert_contains versions/V1/modules/OllamaData.qml 'operationError = failureMessage'
assert_contains versions/V1/modules/OllamaData.qml 'if (ok) operationError = ""'
assert_contains versions/V1/modules/OllamaData.qml 'function loadModel(name) {'
assert_contains versions/V1/modules/OllamaData.qml 'function runModelAction(name, keepAlive, actionName) {'
assert_contains versions/V1/modules/OllamaData.qml 'function pullModel(name) {'
assert_contains versions/V1/modules/OllamaData.qml 'property string pullLastLine: ""'
assert_contains versions/V1/modules/OllamaData.qml '--fail-with-body'
assert_contains versions/V1/modules/OllamaData.qml 'stdout: SplitParser {'
assert_contains versions/V1/modules/OllamaData.qml 'ollama.applyPullProgress(text)'

if grep -Fq 'pullOutputPath\|pullProgressTimer\|progressReaderProc' "$repo_root/versions/V1/modules/OllamaData.qml"; then
    printf 'pull must not use file polling or pullProgressTimer\n' >&2
    exit 1
fi

if grep -Fq '/tmp/ollama_pull_output' "$repo_root/versions/V1/modules/OllamaData.qml"; then
    printf 'pull progress must not use a shared predictable /tmp file\n' >&2
    exit 1
fi

if grep -Fq 'ollama rm' "$repo_root/versions/V1/modules/OllamaData.qml"; then
    printf 'exclusive loading must not use ollama rm\n' >&2
    exit 1
fi

assert_contains versions/V1/panels/OllamaPanel.qml 'model: root.ollama.models'
assert_contains versions/V1/panels/OllamaPanel.qml 'visible: root.ollama.operationInProgress'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: root.ollama.operationMessage'
assert_contains versions/V1/panels/OllamaPanel.qml 'enabled: !root.ollama.controlsLocked'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.loadModel(modelData.name)'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.ejectModel(modelData.name)'
assert_contains versions/V1/panels/OllamaPanel.qml 'id: modelReload'
assert_contains versions/V1/panels/OllamaPanel.qml 'visible: modelData.loaded'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Renew loaded model"'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "No model loaded"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.displayError === ""'
assert_contains versions/V1/panels/OllamaPanel.qml 'visible: root.ollama.displayError !== ""'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: root.ollama.displayError'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Keep Alive"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.keepAliveStatus'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Context"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.setKeepAlive'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.setNumCtx'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.parseContextInput(raw)'
assert_contains versions/V1/panels/OllamaPanel.qml 'function setKeepAlive(value)'
assert_contains versions/V1/panels/OllamaPanel.qml 'function setContext(value)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'function setKeepAlive\(value\)\s*\{\s*clearDeleteConfirmation\(\)\s*root\.ollama\.setKeepAlive\(value\)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'function setContext\(value\)\s*\{\s*clearDeleteConfirmation\(\)\s*root\.ollama\.setNumCtx\(value\)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: pullMa\s*anchors\.fill: parent\s*enabled: !root\.ollama\.controlsLocked\s*&& String\(pullInput\.text\)\.trim\(\) !== ""\s*hoverEnabled: enabled'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.applyRuntimeConfiguration()'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Apply configuration"'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Refresh Ollama state"'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Open Ollama config file"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.openRuntimeConfig()'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property bool refreshRunning: versionProc.running || tagsProc.running || loadedProc.running'
assert_contains versions/V1/modules/OllamaData.qml 'OllamaDataLogic.maxGpuPercent'
assert_contains versions/V1/modules/OllamaWidget.qml 'text: "GPU max"'
assert_contains versions/V1/panels/OllamaPanel.qml 'enabled: !root.ollama.refreshRunning'
assert_contains versions/V1/panels/OllamaPanel.qml 'opacity: refreshMa.enabled ? 1 : 0.35'
assert_contains versions/V1/panels/OllamaPanel.qml 'cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: root.ollama.connected && root.ollama.version !== ""'
assert_contains versions/V1/panels/OllamaPanel.qml 'color: root.ollama.connected && root.ollama.version !== "" ? root.seal : root.sumi'
assert_contains versions/V1/panels/OllamaPanel.qml 'id: deleteConfirmationTimer'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Delete " + ollamaPanel.confirmDeleteModel + "?"'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Cancel"'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Delete model"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.deleteModel(ollamaPanel.confirmDeleteModel)'
assert_not_contains versions/V1/panels/OllamaPanel.qml 'function onModelsChanged() { ollamaPanel.clearDeleteConfirmation() }'
assert_contains versions/V1/panels/OllamaPanel.qml 'function clearDeleteConfirmation()'
assert_contains versions/V1/panels/OllamaPanel.qml 'function confirmDelete(name)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: modelDelete[\s\S]*?anchors\.rightMargin: 8[\s\S]*?y: ollamaPanel\.confirmDeleteModel === modelData\.name \? 8\s*: Math\.round\(\(parent\.height - height\) / 2\)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: modelReload[\s\S]*?anchors\.rightMargin: 8[\s\S]*?y: ollamaPanel\.confirmDeleteModel === modelData\.name \? 8\s*: Math\.round\(\(parent\.height - height\) / 2\)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: modelAction[\s\S]*?anchors\.rightMargin: 8[\s\S]*?y: ollamaPanel\.confirmDeleteModel === modelData\.name \? 8\s*: Math\.round\(\(parent\.height - height\) / 2\)'
assert_contains versions/V1/panels/OllamaPanel.qml 'owner: refreshButton'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Refresh Ollama state"'
assert_contains versions/V1/panels/OllamaPanel.qml 'owner: closeButton'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Close Ollama panel"'
assert_contains versions/V1/panels/OllamaPanel.qml 'owner: modelDelete'
assert_contains versions/V1/panels/OllamaPanel.qml 'text: "Delete model"'
assert_contains versions/V1/panels/OllamaPanel.qml 'owner: configTile'
assert_contains versions/V1/panels/OllamaPanel.qml 'owner: refreshTile'
assert_contains versions/V1/panels/OllamaPanel.qml 'hoverEnabled: enabled'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: configToggleMa[\s\S]*?hoverEnabled: enabled[\s\S]*?cursorShape: enabled \? Qt\.PointingHandCursor : Qt\.ArrowCursor'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'height: 28[\s\S]*?text: ollamaPanel\.configOpen \? "Configuration'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'property bool selected: root\.ollama\.selectedKeepAlive === modelData\.value[\s\S]*?property bool chipEnabled: !root\.ollama\.controlsLocked[\s\S]*?hoverEnabled: enabled[\s\S]*?cursorShape: enabled \? Qt\.PointingHandCursor : Qt\.ArrowCursor'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'property bool isCustom: modelData\.value === "custom"[\s\S]*?property bool chipEnabled: !root\.ollama\.controlsLocked[\s\S]*?width: isCustom \? 52 : 40[\s\S]*?horizontalAlignment: Text\.AlignHCenter'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'text: modelData\.label[\s\S]*?font\.pixelSize: modelData\.value === -1 \? 14 : 10[\s\S]*?text: modelData\.value === -1 \? "Keep model loaded indefinitely" : ""'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: configTile[\s\S]*?width: 28[\s\S]*?height: 28[\s\S]*?font\.pixelSize: 14'
assert_contains versions/V1/modules/TooltipMixin.qml 'property string placement: "bar"'
assert_contains versions/V1/panels/OllamaPanel.qml 'placement: "panel"'
assert_contains versions/V1/panels/TooltipOverlay.qml 'TooltipPosition.barY'
assert_contains versions/V1/panels/TooltipOverlay.qml 'TooltipPosition.panelPoint'
tooltip_mixin_count="$(grep -c 'TooltipMixin {' "$repo_root/versions/V1/panels/OllamaPanel.qml")"
panel_placement_count="$(grep -c 'placement: "panel"' "$repo_root/versions/V1/panels/OllamaPanel.qml")"
if [[ "$tooltip_mixin_count" -ne "$panel_placement_count" ]]; then
    printf 'every Ollama panel TooltipMixin must use panel placement\n' >&2
    exit 1
fi
assert_contains versions/V1/panels/TooltipOverlay.qml 'width: Math.min(parent.width - 8, tipLabel.implicitWidth + padH * 2)'
assert_contains versions/V1/panels/TooltipOverlay.qml 'wrapMode: Text.Wrap'

assert_contains versions/V1/panels/ControlPanel.qml 'label: "Ollama";      active: root.modOllama'
assert_contains versions/V1/panels/ControlPanel.qml 'label: "Ollama";     active: root.compactOllama'
assert_contains README.md 'Ollama management'

if grep -Eq 'sudo|pkexec|systemctl|ollama stop|ollama rm|ollama serve' "$repo_root/versions/V1/modules/OllamaData.qml" "$repo_root/versions/V1/panels/OllamaPanel.qml"; then
    printf 'Ollama widget must not use sudo/systemctl/ollama CLI commands\n' >&2
    exit 1
fi

printf 'ollama theme wiring: ok\n'
