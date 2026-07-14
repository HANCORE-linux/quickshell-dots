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

grep -Fxq 'import "panels/ollama"' \
    "$repo_root/tests/fixtures/OllamaPanelSectionsSmoke.qml" || {
    printf 'native Ollama panel fixture must use local panel components\n' >&2
    exit 1
}

shopt -s dotglob globstar nullglob
for qml in "$repo_root"/versions/V1/**/*.qml; do
    [[ "$qml" == "$repo_root/versions/V1/shell.qml" ]] && continue
    ! grep -Pzq '(?m)^[\t ]*ShellRoot\s*\{' "$qml" || {
        printf 'unexpected ShellRoot in production payload: %s\n' "${qml#"$repo_root/"}" >&2
        exit 1
    }
done
shopt -u dotglob globstar nullglob

for runner in \
    tests/test_OllamaData_native.sh \
    tests/test-ollama-panel-native.sh \
    tests/test-ollama-pull-integration.sh \
    tests/test-ollama-lifecycle-integration.sh \
    tests/test-ollama-gpu-integration.sh; do
    ! grep -Eq "versions/V1/[^[:space:]\"']*(FixtureRunner|fixture-runner|Smoke)[^[:space:]\"']*\\.qml" "$repo_root/$runner" || {
        printf 'test runner creates fixture root in production payload: %s\n' "$runner" >&2
        exit 1
    }
    ! grep -Pzq 'ShellRoot\s*\{' "$repo_root/$runner" || {
        printf 'test runner embeds ShellRoot: %s\n' "$runner" >&2
        exit 1
    }
done

for fixture in \
    tests/fixtures/OllamaDataSmoke.qml \
    tests/fixtures/OllamaPanelSectionsSmoke.qml \
    tests/fixtures/OllamaPullIntegrationSmoke.qml \
    tests/fixtures/OllamaLifecycleSmoke.qml \
    tests/fixtures/OllamaGpuSmoke.qml; do
    grep -Fxq 'import "modules"' "$repo_root/$fixture" || {
        printf 'test fixture must use local modules: %s\n' "$fixture" >&2
        exit 1
    }
done

assert_native_panel_dependency() {
    local dependency="$1"
    grep -Fq "versions/V1/$dependency" \
        "$repo_root/tests/test-ollama-panel-native.sh" || {
        printf 'native Ollama panel fixture omits production dependency: %s\n' \
            "$dependency" >&2
        exit 1
    }
}

for dependency in \
    panels/ollama/OllamaModelsSection.qml \
    panels/ollama/OllamaModelRow.qml \
    panels/ollama/OllamaDeleteButton.qml \
    panels/ollama/OllamaPanelHeader.qml \
    panels/ollama/OllamaSummarySection.qml \
    panels/ollama/OllamaDetailRow.qml \
    panels/ollama/OllamaPullSection.qml \
    panels/ollama/OllamaConfigSection.qml \
    panels/ollama/OllamaConfigurationToggle.qml \
    panels/ollama/OllamaPanelLayout.js \
    modules/UiText.qml \
    modules/IconText.qml \
    modules/TooltipMixin.qml; do
    assert_native_panel_dependency "$dependency"
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

assert_file_order() {
    local file="$repo_root/$1"
    shift
    local previous=0
    local text line
    for text in "$@"; do
        line="$(grep -nFm1 -- "$text" "$file" | cut -d: -f1 || true)"
        if [[ -z "$line" || "$line" -le "$previous" ]]; then
            printf 'expected ordered %s in %s\n' "$text" "$file" >&2
            exit 1
        fi
        previous="$line"
    done
}

while IFS= read -r static_import; do
    imported_file="${static_import##*/}"
    grep -Fq "versions/V1/modules/$imported_file" \
        "$repo_root/tests/test_OllamaData_native.sh" || {
        printf 'native OllamaData fixture omits static JS import: %s\n' "$static_import" >&2
        exit 1
    }
done < <(grep -oP '^import "\K[^"]+\.js(?=")' \
    "$repo_root/versions/V1/modules/OllamaData.qml")

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
assert_contains 'if (ollamaVisible && ollama.enabled) ollama.refreshAll()'
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
assert_contains versions/V1/shell.qml 'function open(): void { if (theme.ollama.enabled) theme.ollamaVisible = true }'
assert_contains versions/V1/shell.qml 'function close(): void { theme.ollamaVisible = false }'
assert_contains versions/V1/shell.qml 'function refresh(): void { if (theme.ollama.enabled) theme.ollama.refreshAll() }'
assert_not_contains versions/V1/shell.qml 'function open(): void { theme.modOllama'
assert_not_contains versions/V1/shell.qml 'function close(): void { theme.modOllama'
assert_not_contains versions/V1/shell.qml 'function open(): void { theme.ollamaVisible = true }'
assert_not_contains versions/V1/shell.qml 'function refresh(): void { theme.ollama.refreshAll() }'
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
assert_contains versions/V1/modules/OllamaData.qml 'else loadedRefreshPending = true'
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
assert_contains versions/V1/modules/OllamaData.qml 'readonly property bool pullCanCancel:'
assert_contains versions/V1/modules/OllamaData.qml 'property var reconciliationClock:'
assert_contains versions/V1/modules/OllamaData.qml 'OllamaPullLogic.nextReconcileDelayMs('
assert_contains versions/V1/modules/OllamaData.qml '--fail-with-body'
assert_contains versions/V1/modules/OllamaData.qml 'stdout: SplitParser {'
assert_contains versions/V1/modules/OllamaData.qml 'ollama.applyPullProgress(text)'
assert_contains versions/V1/modules/OllamaData.qml 'property int loadedPollIntervalMs: 2000'
assert_contains versions/V1/modules/OllamaData.qml 'property bool loadedTimerRefreshPending: false'
assert_contains versions/V1/modules/OllamaData.qml 'if (!panelVisible) loadedTimerRefreshPending = false'
assert_contains versions/V1/modules/OllamaData.qml 'if (fromTimer === true) loadedTimerRefreshPending = true'
assert_contains versions/V1/modules/OllamaData.qml 'var refreshExplicitly = ollama.loadedRefreshPending'
assert_contains versions/V1/modules/OllamaData.qml 'if (refreshExplicitly || refreshFromTimer) ollama.refreshLoaded()'
assert_contains versions/V1/modules/OllamaData.qml 'interval: ollama.loadedPollIntervalMs'
assert_contains versions/V1/modules/OllamaData.qml 'running: ollama.enabled && ollama.panelVisible'
assert_contains versions/V1/modules/OllamaData.qml 'triggeredOnStart: false'
assert_not_contains versions/V1/modules/OllamaData.qml 'onTriggered: ollama.refreshVersion()'
assert_file_matches versions/V1/modules/OllamaData.qml 'interval: ollama\.loadedPollIntervalMs\s*running: ollama\.enabled && ollama\.panelVisible\s*repeat: true\s*triggeredOnStart: false\s*onTriggered: ollama\.refreshLoaded\(true\)'
assert_file_matches versions/V1/Theme.qml 'onOllamaVisibleChanged:\s*\{\s*popupOpened\("ollamaVisible"\)\s*if \(ollamaVisible && ollama\.enabled\) ollama\.refreshAll\(\)'

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

assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'required property var root'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'required property var data'
assert_not_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'ollamaVisible ='
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'signal refreshRequested()'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'signal closeRequested()'
assert_contains versions/V1/panels/OllamaPanel.qml 'OllamaPanelHeader {'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'required property var root'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'required property var data'
assert_not_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'ollamaVisible ='
assert_contains versions/V1/panels/ollama/OllamaDetailRow.qml 'property string k: ""'
assert_contains versions/V1/panels/OllamaPanel.qml 'OllamaSummarySection {'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'required property var root'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'required property var data'
assert_not_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'ollamaVisible ='
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'function clearDeleteConfirmation()'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'property int confirmationTimeoutMs: 8000'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'interval: modelsSection.confirmationTimeoutMs'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'signal loadRequested(string name)'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'signal ejectRequested(string name)'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'signal deleteRequested(string name)'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'required property var modelData'
assert_not_contains versions/V1/panels/ollama/OllamaModelRow.qml '.loadModel('
assert_not_contains versions/V1/panels/ollama/OllamaModelRow.qml '.ejectModel('
assert_not_contains versions/V1/panels/ollama/OllamaModelRow.qml '.deleteModel('
assert_contains versions/V1/panels/OllamaPanel.qml 'OllamaModelsSection {'
assert_contains versions/V1/panels/ollama/OllamaPullSection.qml 'required property var root'
assert_contains versions/V1/panels/ollama/OllamaPullSection.qml 'required property var data'
assert_not_contains versions/V1/panels/ollama/OllamaPullSection.qml 'ollamaVisible ='
assert_contains versions/V1/panels/ollama/OllamaPullSection.qml 'signal pullRequested(string name)'
assert_contains versions/V1/panels/ollama/OllamaPullSection.qml 'signal cancelRequested()'
assert_not_contains versions/V1/panels/ollama/OllamaPullSection.qml '.pullModel('
assert_not_contains versions/V1/panels/ollama/OllamaPullSection.qml '.cancelPull('
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'required property var root'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'required property var data'
assert_not_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'ollamaVisible ='
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'signal openRuntimeConfigRequested()'
assert_not_contains versions/V1/panels/ollama/OllamaConfigSection.qml '.openRuntimeConfig('
assert_not_contains versions/V1/panels/ollama/OllamaConfigSection.qml '.applyRuntimeConfiguration('
assert_not_contains versions/V1/panels/ollama/OllamaConfigSection.qml '.refreshAll('

assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'model: modelsSection.data.models'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'height: Math\.min\(contentColumn\.implicitHeight \+ 24,\s*parent\.height - 2 \* \(barBottom \+ gap\)\)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'id: scroller\s*anchors\.fill: parent\s*anchors\.margins: 12\s*contentWidth: width\s*contentHeight: contentColumn\.implicitHeight\s*clip: true\s*interactive: contentHeight > height\s*boundsBehavior: Flickable\.StopAtBounds'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'Keys\.onPressed: function\(event\) \{\s*if \(event\.key === Qt\.Key_Escape\) \{\s*if \(modelsSection\.confirmDeleteModel !== ""\) \{\s*ollamaPanel\.clearDeleteConfirmation\(\)\s*\} else \{\s*root\.ollamaVisible = false'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'MouseArea \{\s*anchors\.fill: parent\s*onClicked: \{\s*root\.ollamaVisible = false\s*ollamaPanel\.clearDeleteConfirmation\(\)'
assert_contains versions/V1/panels/OllamaPanel.qml 'focus: root.ollamaVisible'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'WlrLayershell\.keyboardFocus: root\.ollamaVisible\s*\? WlrKeyboardFocus\.Exclusive : WlrKeyboardFocus\.None'
assert_file_matches versions/V1/panels/ollama/OllamaModelRow.qml 'height: confirmationVisible \? 86 : 58'
assert_file_order versions/V1/panels/OllamaPanel.qml \
    'OllamaPanelHeader {' \
    'OllamaSummarySection {' \
    'OllamaModelsSection {' \
    'OllamaPullSection {' \
    'OllamaConfigSection {'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'visible: summarySection.data.operationInProgress'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'text: summarySection.data.operationMessage'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'enabled: !modelRow.data.controlsLocked'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.loadModel(name)'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.ejectModel(name)'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'id: modelReload'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'visible: modelRow.modelData.loaded'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'text: "Renew loaded model"'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'text: "No model loaded"'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'summarySection.data.displayError === ""'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'visible: summarySection.data.displayError !== ""'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'text: summarySection.data.displayError'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'k: "Keep Alive"'
assert_contains versions/V1/panels/ollama/OllamaSummarySection.qml 'v: summarySection.data.keepAliveStatus'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'text: "Context"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.setKeepAlive'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.setNumCtx'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'configSection.data.parseContextInput(raw)'
assert_contains versions/V1/panels/OllamaPanel.qml 'function setKeepAlive(value)'
assert_contains versions/V1/panels/OllamaPanel.qml 'function setContext(value)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'function setKeepAlive\(value\)\s*\{\s*clearDeleteConfirmation\(\)\s*root\.ollama\.setKeepAlive\(value\)'
assert_file_matches versions/V1/panels/OllamaPanel.qml 'function setContext\(value\)\s*\{\s*clearDeleteConfirmation\(\)\s*root\.ollama\.setNumCtx\(value\)'
assert_file_matches versions/V1/panels/ollama/OllamaPullSection.qml 'id: pullMa\s*anchors\.fill: parent\s*enabled: !pullSection\.data\.controlsLocked\s*&& String\(pullInput\.text\)\.trim\(\) !== ""\s*hoverEnabled: enabled'
assert_file_matches versions/V1/panels/ollama/OllamaPullSection.qml 'id: cancelPullButton[\s\S]*?visible: pullSection\.data\.pullCanCancel'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.applyRuntimeConfiguration()'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'text: "Apply configuration"'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'text: "Refresh Ollama state"'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'text: "Open Ollama config file"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.openRuntimeConfig()'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property bool refreshRunning: versionProc.running || tagsProc.running || loadedProc.running'
assert_contains versions/V1/modules/OllamaData.qml 'OllamaGpuSampler {'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property alias gpuProviderKind: gpuSampler.providerKind'
assert_contains versions/V1/modules/OllamaData.qml 'readonly property alias gpuProviderState: gpuSampler.providerState'
assert_contains versions/V1/modules/OllamaData.qml 'gpuSampler.sampleNow()'
assert_not_contains versions/V1/modules/OllamaData.qml 'id: gpuProc'
assert_not_contains versions/V1/modules/OllamaData.qml 'command -v nvidia-smi'
assert_not_contains versions/V1/modules/OllamaData.qml 'cat "$card"'
assert_contains versions/V1/modules/OllamaGpuSampler.qml 'FileView {'
assert_contains versions/V1/modules/OllamaGpuSampler.qml 'nvidiaSmiExecutable,'
assert_contains versions/V1/modules/OllamaGpuSampler.qml '"--query-gpu=index,utilization.gpu"'
assert_contains versions/V1/modules/OllamaGpuSampler.qml '"--format=csv,noheader,nounits"'
assert_contains versions/V1/modules/OllamaGpuSampler.qml '"--loop-ms=" + cadence'
assert_not_contains versions/V1/modules/OllamaGpuSampler.qml '"bash"'
assert_not_contains versions/V1/modules/OllamaGpuSampler.qml '"cat"'
assert_contains versions/V1/modules/OllamaWidget.qml 'text: "GPU max"'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'enabled: !header.data.refreshRunning && !header.data.controlsLocked'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'opacity: refreshMa.enabled ? 1 : 0.35'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'text: header.data.connected && header.data.version !== ""'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml '? header.root.seal : header.root.sumi'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'id: deleteConfirmationTimer'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'text: "Delete " + modelRow.modelData.name + "?"'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'text: "Cancel"'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'text: "Delete model"'
assert_contains versions/V1/panels/OllamaPanel.qml 'root.ollama.deleteModel(name)'
assert_not_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'function onModelsChanged()'
assert_contains versions/V1/panels/OllamaPanel.qml 'function clearDeleteConfirmation()'
assert_contains versions/V1/panels/ollama/OllamaModelsSection.qml 'function confirmDelete(name)'
assert_contains versions/V1/panels/OllamaPanel.qml 'import "ollama"'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'import "OllamaPanelLayout.js" as PanelLayout'
assert_file_matches versions/V1/panels/ollama/OllamaModelRow.qml 'OllamaDeleteButton\s*\{[\s\S]*?id: modelDelete[\s\S]*?confirmationVisible: modelRow\.confirmationVisible'
assert_file_matches versions/V1/panels/ollama/OllamaModelRow.qml 'id: modelReload[\s\S]*?y: PanelLayout\.modelActionY\(modelRow\.confirmationVisible\)'
assert_file_matches versions/V1/panels/ollama/OllamaModelRow.qml 'id: modelAction[\s\S]*?y: PanelLayout\.modelActionY\(modelRow\.confirmationVisible\)'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'owner: refreshButton'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'text: "Refresh Ollama state"'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'owner: closeButton'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'text: "Close Ollama panel"'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'owner: modelDelete'
assert_contains versions/V1/panels/ollama/OllamaModelRow.qml 'text: "Delete model"'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'owner: configTile'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'owner: refreshTile'
assert_contains versions/V1/panels/ollama/OllamaConfigSection.qml 'hoverEnabled: enabled'
assert_file_matches versions/V1/panels/ollama/OllamaConfigurationToggle.qml 'id: toggleMouseArea[\s\S]*?hoverEnabled: enabled[\s\S]*?cursorShape: enabled \? Qt\.PointingHandCursor : Qt\.ArrowCursor'
assert_file_matches versions/V1/panels/ollama/OllamaConfigSection.qml 'OllamaConfigurationToggle\s*\{[\s\S]*?open: configSection\.configOpen[\s\S]*?onClicked: configSection\.configOpen = !configSection\.configOpen'
assert_not_contains versions/V1/panels/ollama/OllamaModelRow.qml 'id: modelDeleteGlyph'
assert_not_contains versions/V1/panels/ollama/OllamaConfigurationToggle.qml 'id: configurationHeadingGroup'
assert_file_matches versions/V1/panels/ollama/OllamaConfigSection.qml 'property bool selected: configSection\.data\.selectedKeepAlive\s*=== modelData\.value[\s\S]*?property bool chipEnabled: !configSection\.data\.controlsLocked[\s\S]*?hoverEnabled: enabled[\s\S]*?cursorShape: enabled \? Qt\.PointingHandCursor : Qt\.ArrowCursor'
assert_file_matches versions/V1/panels/ollama/OllamaConfigSection.qml 'property bool isCustom: modelData\.value === "custom"[\s\S]*?property bool chipEnabled: !configSection\.data\.controlsLocked[\s\S]*?width: isCustom \? 52 : 40[\s\S]*?horizontalAlignment: Text\.AlignHCenter'
assert_file_matches versions/V1/panels/ollama/OllamaConfigSection.qml 'text: modelData\.label[\s\S]*?font\.pixelSize: modelData\.value === -1 \? 14 : 10[\s\S]*?text: modelData\.value === -1\s*\? "Keep model loaded indefinitely" : ""'
assert_file_matches versions/V1/panels/ollama/OllamaConfigSection.qml 'id: configTile[\s\S]*?width: 28[\s\S]*?height: 28[\s\S]*?font\.pixelSize: 14'
assert_contains versions/V1/modules/TooltipMixin.qml 'property string placement: "bar"'
assert_contains versions/V1/panels/ollama/OllamaPanelHeader.qml 'placement: "panel"'
assert_contains versions/V1/panels/TooltipOverlay.qml 'TooltipPosition.barY'
assert_contains versions/V1/panels/TooltipOverlay.qml 'TooltipPosition.panelPoint'
tooltip_mixin_count="$(grep -h 'TooltipMixin {' "$repo_root"/versions/V1/panels/ollama/*.qml | wc -l)"
panel_placement_count="$(grep -h 'placement: "panel"' "$repo_root"/versions/V1/panels/ollama/*.qml | wc -l)"
if [[ "$tooltip_mixin_count" -ne "$panel_placement_count" ]]; then
    printf 'every Ollama panel TooltipMixin must use panel placement\n' >&2
    exit 1
fi
assert_contains versions/V1/panels/TooltipOverlay.qml 'width: Math.min(parent.width - 8, tipLabel.implicitWidth + padH * 2)'
assert_contains versions/V1/panels/TooltipOverlay.qml 'wrapMode: Text.Wrap'

assert_contains versions/V1/panels/ControlPanel.qml 'label: "Ollama";      active: root.modOllama'
assert_contains versions/V1/panels/ControlPanel.qml 'label: "Ollama";     active: root.compactOllama'
assert_contains README.md 'Ollama management'

if grep -Eq 'sudo|pkexec|systemctl|ollama stop|ollama rm|ollama serve' \
    "$repo_root/versions/V1/modules/OllamaData.qml" \
    "$repo_root/versions/V1/panels/OllamaPanel.qml" \
    "$repo_root"/versions/V1/panels/ollama/*.qml; then
    printf 'Ollama widget must not use sudo/systemctl/ollama CLI commands\n' >&2
    exit 1
fi

printf 'ollama theme wiring: ok\n'
