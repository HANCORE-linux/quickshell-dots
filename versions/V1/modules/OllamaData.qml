import QtQuick
import Quickshell
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic

Item {
    id: ollama

    property string baseUrl: "http://127.0.0.1:11434"
    enabled: false
    readonly property bool connected: OllamaDataLogic.aggregateConnected(versionConnected, tagsConnected, loadedConnected)
    property string version: ""
    property var installedModels: []
    property var loadedModels: []
    readonly property alias gpuPercent: gpuSampler.percent
    readonly property alias gpuHistory: gpuSampler.history
    readonly property alias gpuProviderKind: gpuSampler.providerKind
    readonly property alias gpuProviderState: gpuSampler.providerState
    readonly property int gpuMaxSamples: gpuSampler.maxSamples
    readonly property alias operations: modelOperations
    property alias busy: modelOperations.busy
    property alias pendingAction: modelOperations.pendingAction
    property alias pendingModel: modelOperations.pendingModel
    property string versionError: ""
    property string tagsError: ""
    property string loadedError: ""
    property alias actionError: modelOperations.actionError
    property bool versionConnected: false
    property bool tagsConnected: false
    property bool loadedConnected: false
    property alias operationError: modelOperations.operationError
    property alias operationInProgress: modelOperations.operationInProgress
    property alias operationState: modelOperations.operationState
    property alias operationMode: modelOperations.operationMode
    property alias operationId: modelOperations.operationId
    property int refreshEpoch: 0
    property bool tagsRefreshPending: false
    property bool loadedRefreshPending: false
    property bool loadedTimerRefreshPending: false
    property alias stopQueue: modelOperations.stopQueue
    property alias verificationAttempts: modelOperations.verificationAttempts
    property alias verificationKind: modelOperations.verificationKind
    property alias failureMessage: modelOperations.failureMessage
    readonly property alias pull: pullController
    property alias pullAttempt: pullController.pullAttempt
    property alias pullState: pullController.pullState
    readonly property alias pullBusy: pullController.pullBusy
    readonly property alias pullCanCancel: pullController.pullCanCancel
    property alias pullModelName: pullController.pullModelName
    property alias pullProgress: pullController.pullProgress
    property alias pullPercent: pullController.pullPercent
    property alias pullStatus: pullController.pullStatus
    property alias pullError: pullController.pullError
    property alias pullDigest: pullController.pullDigest
    property alias pullCompletedBytes: pullController.pullCompletedBytes
    property alias pullTotalBytes: pullController.pullTotalBytes
    property alias pullRate: pullController.pullRate
    property alias pullStableRateSamples: pullController.pullStableRateSamples
    property alias pullStartedAtMs: pullController.pullStartedAtMs
    property alias pullElapsedSeconds: pullController.pullElapsedSeconds
    property bool panelVisible: false
    property int loadedPollIntervalMs: 2000
    readonly property alias config: runtimeConfig
    property alias selectedKeepAlive: runtimeConfig.selectedKeepAlive
    property alias selectedNumCtx: runtimeConfig.selectedNumCtx
    property alias configDirty: runtimeConfig.dirty
    signal runtimeConfigLoaded()
    signal runtimeConfigReloaded()

    readonly property double loadedVramBytes: sumLoadedVram(loadedModels)
    readonly property var models: reconcileModels(installedModels, loadedModels)
    readonly property alias runtimeConfigPath: runtimeConfig.path
    property alias pullLastLine: pullController.pullLastLine
    property alias pullReconcileAttempts: pullController.pullReconcileAttempts
    property alias pullReconcileStartedAtMs: pullController.pullReconcileStartedAtMs
    property alias pullReconcileDeadlineAtMs: pullController.pullReconcileDeadlineAtMs
    property alias reconciliationClock: pullController.reconciliationClock
    readonly property int effectiveContextLength: loadedModels.length === 1
        ? loadedModels[0].contextLength : 0
    readonly property string keepAliveStatus: {
        if (loadedModels.length !== 1) {
            if (selectedKeepAlive === -1) return "\u221E"
            return selectedKeepAlive
        }
        var exp = String(loadedModels[0].expiresAt || "")
        if (exp.length === 0) return "\u221E (indefinite)"
        var ms = Date.parse(exp)
        if (!ms || ms <= Date.now()) return "expired"
        var remaining = Math.round((ms - Date.now()) / 1000)
        if (remaining < 60) return remaining + "s"
        if (remaining < 3600) return Math.round(remaining / 60) + "m"
        if (remaining < 86400) return Math.round(remaining / 3600) + "h"
        return Math.round(remaining / 86400) + "d"
    }
    readonly property bool refreshRunning: versionProc.running || tagsProc.running || loadedProc.running
    readonly property bool controlsLocked: operationInProgress || busy || pullBusy
    readonly property string lastError:
        OllamaDataLogic.aggregateError(actionError, versionError, tagsError, loadedError)
    readonly property string displayError: operationError !== "" ? operationError : lastError
    readonly property alias operationMessage: modelOperations.operationMessage
    readonly property alias pullProgressText: pullController.pullProgressText
    readonly property alias pullResultText: pullController.pullResultText

    function decodeResponse(raw) {
        return OllamaDataLogic.decodeResponse(raw)
    }

    function buildRequest(method, path, payload, maxTime) {
        return OllamaDataLogic.buildRequest(baseUrl, method, path, payload, maxTime)
    }

    function buildLoadPayload(modelName) {
        return OllamaDataLogic.buildLoadPayload(modelName, selectedKeepAlive, selectedNumCtx)
    }

    function parseTags(body) {
        return OllamaDataLogic.parseTags(body)
    }

    function parseLoaded(body) {
        return OllamaDataLogic.parseLoaded(body)
    }

    function sumLoadedVram(entries) {
        return OllamaDataLogic.sumLoadedVram(entries)
    }

    function reconcileModels(installed, loaded) {
        return OllamaDataLogic.reconcileModels(installed, loaded)
    }

    function errorMessage(response, fallback) {
        return OllamaDataLogic.errorMessage(response, fallback)
    }

    function successful(response) {
        return OllamaDataLogic.successful(response)
    }

    function applyVersion(raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        var state = OllamaDataLogic.versionState(raw, version)
        versionConnected = state.connected
        version = state.version
        versionError = state.lastError
    }

    function applyTags(raw, requestEpoch, requestPullAttempt) {
        if (requestEpoch !== refreshEpoch) return
        if (requestPullAttempt !== undefined && requestPullAttempt !== 0
                && (requestPullAttempt !== pullAttempt || pullState !== "reconciling")) return
        var response = decodeResponse(raw)
        if (!successful(response)) {
            tagsConnected = false
            tagsError = errorMessage(response, "Unable to list Ollama models")
            return
        }
        try {
            installedModels = parseTags(response.body)
            tagsConnected = true
            tagsError = ""
        } catch (error) {
            tagsConnected = false
            tagsError = "Invalid Ollama model response"
        }
    }

    function applyLoaded(raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        var response = decodeResponse(raw)
        if (!successful(response)) {
            loadedConnected = false
            loadedError = errorMessage(response, "Unable to read loaded Ollama models")
            return
        }
        try {
            loadedModels = parseLoaded(response.body)
            loadedConnected = true
            loadedError = ""
        } catch (error) {
            loadedConnected = false
            loadedError = "Invalid Ollama loaded-model response"
        }
    }

    function refreshAll() {
        refreshVersion()
        refreshTags()
        refreshLoaded()
        refreshGpu()
    }

    function refreshVersion() {
        if (operationInProgress || versionProc.running) return
        versionProc.refreshEpoch = refreshEpoch
        versionProc.command = buildRequest("GET", "/api/version")
        versionProc.running = true
    }

    function refreshTags() {
        if (operationInProgress) return
        if (tagsProc.running) { tagsRefreshPending = true; return }
        tagsProc.refreshEpoch = refreshEpoch
        tagsProc.command = buildRequest("GET", "/api/tags")
        tagsProc.running = true
    }

    function refreshLoaded(fromTimer) {
        if (operationInProgress) return
        if (loadedProc.running) {
            if (fromTimer === true) loadedTimerRefreshPending = true
            else loadedRefreshPending = true
            return
        }
        loadedProc.refreshEpoch = refreshEpoch
        loadedProc.command = buildRequest("GET", "/api/ps")
        loadedProc.running = true
    }

    function refreshGpu() {
        if (gpuSampler.providerState === "unavailable"
                || gpuSampler.providerState === "undetected") gpuSampler.redetect()
        else gpuSampler.sampleNow()
    }

    function loadModel(name) {
        modelOperations.loadModel(name)
    }

    function applyAction(raw) {
        modelOperations.applyAction(raw)
    }

    function operationModels(raw) {
        return modelOperations.operationModels(raw)
    }

    function finishExclusiveLoad(ok, models) {
        modelOperations.finishExclusiveLoad(ok, models)
    }

    function failExclusiveLoad(message) {
        modelOperations.failExclusiveLoad(message)
    }

    function requestOperationModels(purpose, requestId) {
        modelOperations.requestOperationModels(purpose, requestId)
    }

    function handleOperationModels(purpose, requestId, exitCode, raw) {
        modelOperations.handleOperationModels(purpose, requestId, exitCode, raw)
    }

    function beginVerification(kind) {
        modelOperations.beginVerification(kind)
    }

    function requestVerification() {
        modelOperations.requestVerification()
    }

    function stopNextModel() {
        modelOperations.stopNextModel()
    }

    function handleUnloadExit(requestId, modelName, exitCode, timedOut) {
        modelOperations.handleUnloadExit(requestId, modelName, exitCode, timedOut)
    }

    function beginSelectedModelLoad() {
        modelOperations.beginSelectedModelLoad()
    }

    function handleLoadExit(requestId, exitCode, raw) {
        modelOperations.handleLoadExit(requestId, exitCode, raw)
    }

    function runModelAction(name, keepAlive, actionName) {
        modelOperations.runModelAction(name, keepAlive, actionName)
    }

    function ejectModel(name) { modelOperations.ejectModel(name) }
    function deleteModel(name) { modelOperations.deleteModel(name) }

    function beginActionState(actionName, name) {
        modelOperations.beginActionState(actionName, name)
    }

    function clearActionState() {
        modelOperations.clearActionState()
    }

    function openConfiguration() {}
    function reloadConfiguration() { runtimeConfig.reload() }
    function saveRuntimeConfig() { runtimeConfig.save() }
    function applyRuntimeConfigFile() { runtimeConfig.applyFile() }

    function parseContextInput(raw) {
        return runtimeConfig.parseContextInput(raw)
    }

    function setKeepAlive(value) {
        runtimeConfig.setKeepAlive(value)
    }

    function setNumCtx(value) {
        runtimeConfig.setNumCtx(value)
    }

    function applyRuntimeConfiguration() {
        modelOperations.applyRuntimeConfiguration()
    }

    function startUnloadOperation(mode, name) {
        modelOperations.startUnloadOperation(mode, name)
    }

    onEnabledChanged: {
        if (enabled) {
            gpuSampler.activate()
            refreshAll()
        } else {
            loadedTimerRefreshPending = false
            gpuSampler.deactivate()
        }
    }
    onPanelVisibleChanged: {
        if (!panelVisible) loadedTimerRefreshPending = false
        if (panelVisible) gpuSampler.panelOpened()
        else gpuSampler.panelClosed()
    }
    Component.onCompleted: if (enabled) refreshAll()

    Process {
        id: versionProc
        property int refreshEpoch: -1
        stdout: StdioCollector {
            onStreamFinished: ollama.applyVersion(this.text, versionProc.refreshEpoch)
        }
    }

    Process {
        id: tagsProc
        property int refreshEpoch: -1
        stdout: StdioCollector {
            onStreamFinished: ollama.applyTags(this.text, tagsProc.refreshEpoch)
        }
        onExited: {
            if (ollama.tagsRefreshPending) {
                ollama.tagsRefreshPending = false
                ollama.refreshTags()
            }
        }
    }

    Process {
        id: loadedProc
        property int refreshEpoch: -1
        stdout: StdioCollector {
            onStreamFinished: ollama.applyLoaded(this.text, loadedProc.refreshEpoch)
        }
        onExited: {
            var refreshExplicitly = ollama.loadedRefreshPending
            var refreshFromTimer = ollama.loadedTimerRefreshPending
                && ollama.enabled && ollama.panelVisible
            ollama.loadedRefreshPending = false
            ollama.loadedTimerRefreshPending = false
            if (refreshExplicitly || refreshFromTimer) ollama.refreshLoaded()
        }
    }

    OllamaModelOperations {
        id: modelOperations
        baseUrl: ollama.baseUrl
        blocked: ollama.pullBusy
        selectedKeepAlive: runtimeConfig.selectedKeepAlive
        selectedNumCtx: runtimeConfig.selectedNumCtx
        models: ollama.models
        onLoadedModelsAccepted: function(models) { ollama.loadedModels = models }
        onLoadedConnectionChanged: function(connected) { ollama.loadedConnected = connected }
        onTagsRefreshRequested: ollama.refreshTags()
        onLoadedRefreshRequested: ollama.refreshLoaded()
        onConfigurationSaveRequested: runtimeConfig.save()
        onConfigurationApplied: {
            runtimeConfig.dirty = false
            runtimeConfig.save()
        }
        onRefreshEpochInvalidationRequested: ollama.refreshEpoch += 1
    }

    OllamaGpuSampler {
        id: gpuSampler
    }

    OllamaRuntimeConfig {
        id: runtimeConfig
        onLoaded: ollama.runtimeConfigLoaded()
        onReloaded: ollama.runtimeConfigReloaded()
        onErrorOccurred: function(message) { ollama.actionError = message }
    }

    function openRuntimeConfig() { runtimeConfig.openEditor() }

    function pullModel(name) {
        pullController.pullModel(name)
    }

    function applyPullProgress(attempt, raw) {
        pullController.applyPullProgress(attempt, raw)
    }

    function cancelPull() {
        pullController.cancelPull()
    }

    function failPullReconciliation() {
        pullController.failPullReconciliation()
    }

    function schedulePullReconciliation(attempt) {
        pullController.schedulePullReconciliation(attempt)
    }

    function finishPull(attempt, exitCode) {
        pullController.finishPull(attempt, exitCode)
    }

    function requestPullReconciliation(attempt) {
        pullController.requestPullReconciliation(attempt)
    }

    function handlePullTags(attempt, raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        pullController.handlePullTags(attempt, raw)
    }

    OllamaPullController {
        id: pullController
        baseUrl: ollama.baseUrl
        blocked: modelOperations.busy || modelOperations.operationInProgress
        onInstalledModelsAccepted: function(models) {
            ollama.installedModels = models
            ollama.tagsConnected = true
            ollama.tagsError = ""
        }
        onLoadedRefreshRequested: ollama.refreshLoaded()
        onRefreshEpochInvalidationRequested: ollama.refreshEpoch += 1
        onTagsRefreshResetRequested: ollama.tagsRefreshPending = false
        onOperationErrorClearRequested: modelOperations.operationError = ""
    }

    Timer {
        interval: ollama.loadedPollIntervalMs
        running: ollama.enabled && ollama.panelVisible
        repeat: true
        triggeredOnStart: false
        onTriggered: ollama.refreshLoaded(true)
    }

}
