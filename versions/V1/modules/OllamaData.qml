import QtQuick
import Quickshell
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic
import "OllamaPullLogic.js" as OllamaPullLogic

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
    property int pullAttempt: 0
    property string pullState: "idle"
    readonly property bool pullBusy: pullState === "streaming" || pullState === "cancelling"
        || pullState === "reconciling"
    readonly property bool pullCanCancel: pullState === "streaming" || pullState === "cancelling"
    property string pullModelName: ""
    property double pullProgress: 0
    property int pullPercent: 0
    property string pullStatus: ""
    property string pullError: ""
    property string pullDigest: ""
    property double pullCompletedBytes: 0
    property double pullTotalBytes: 0
    property var pullRate: ({ digest: "", completed: 0, total: 0, sampledAtMs: 0,
                              rateBytesPerSecond: 0, etaSeconds: 0 })
    property int pullStableRateSamples: 0
    property double pullStartedAtMs: 0
    property double pullElapsedSeconds: 0
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
    property string pullLastLine: ""
    property int pullReconcileAttempts: 0
    property double pullReconcileStartedAtMs: 0
    property double pullReconcileDeadlineAtMs: 0
    property var reconciliationClock: systemReconciliationClock
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
    readonly property string pullProgressText: OllamaPullLogic.currentLayerText({
        completed: pullCompletedBytes,
        total: pullTotalBytes,
        rateBytesPerSecond: pullRate.rateBytesPerSecond,
        etaSeconds: pullRate.etaSeconds,
        stableSamples: pullStableRateSamples
    })
    readonly property string pullResultText: OllamaDataLogic.pullResultText(
        pullState, pullError, pullElapsedSeconds)

    QtObject {
        id: systemReconciliationClock
        function nowMs() { return Date.now() }
        function timerIntervalMs(logicalMs) { return logicalMs }
        function delayElapsed(logicalMs) {}
    }

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
        tagsProc.pullAttempt = 0
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
        property int pullAttempt: 0
        property bool streamDone: false
        onStarted: streamDone = false
        stdout: StdioCollector {
            onStreamFinished: {
                tagsProc.streamDone = true
                ollama.handlePullTags(tagsProc.pullAttempt, this.text, tagsProc.refreshEpoch)
                ollama.applyTags(this.text, tagsProc.refreshEpoch, tagsProc.pullAttempt)
            }
        }
        onExited: {
            if (!streamDone && pullAttempt === ollama.pullAttempt
                    && ollama.pullState === "reconciling") {
                ollama.handlePullTags(pullAttempt, "", refreshEpoch)
            }
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
        if (controlsLocked || !name) return
        var input = OllamaDataLogic.normalizePullInput(name)
        if (!input.valid) {
            pullError = input.error
            pullState = "failed"
            pullStatus = "Failed"
            return
        }
        var cleanName = input.model
        operationError = ""
        pullAttempt += 1
        pullState = "streaming"
        pullModelName = cleanName
        pullProgress = 0
        pullPercent = 0
        pullStatus = "Connecting..."
        pullError = ""
        pullDigest = ""
        pullCompletedBytes = 0
        pullTotalBytes = 0
        pullRate = { digest: "", completed: 0, total: 0, sampledAtMs: 0,
            rateBytesPerSecond: 0, etaSeconds: 0 }
        pullStableRateSamples = 0
        pullStartedAtMs = Date.now()
        pullElapsedSeconds = 0
        pullLastLine = ""
        pullReconcileAttempts = 0
        pullReconcileStartedAtMs = 0
        pullReconcileDeadlineAtMs = 0
        pullReconcileTimer.stop()
        pullResultTimer.stop()
        pullProc.attempt = pullAttempt
        pullProc.command = [
            "curl", "-sS", "--fail-with-body", "--no-buffer",
            "--connect-timeout", "3", "--max-time", "3600",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-H", "Accept: application/json",
            "--data-binary", JSON.stringify({ model: cleanName, stream: true }),
            baseUrl + "/api/pull"
        ]
        pullProc.running = true
    }

    function applyPullProgress(attempt, raw) {
        if (raw === undefined) {
            raw = attempt
            attempt = pullProc.attempt
        }
        if (attempt !== pullAttempt || pullState !== "streaming") return
        var text = String(raw || "").trim()
        if (!text) return
        try {
            var event = OllamaDataLogic.pullEventState(text, {
                digest: pullDigest, completed: pullCompletedBytes, total: pullTotalBytes
            })
            pullStatus = event.status
            var layer = OllamaPullLogic.nextLayerProgress({
                digest: pullDigest,
                completed: pullCompletedBytes,
                total: pullTotalBytes,
                sampledAtMs: pullRate.sampledAtMs,
                rateBytesPerSecond: pullRate.rateBytesPerSecond,
                etaSeconds: pullRate.etaSeconds,
                stableSamples: pullStableRateSamples
            }, text, Date.now())
            pullDigest = layer.digest
            pullCompletedBytes = layer.completed
            pullTotalBytes = layer.total
            pullRate = {
                digest: layer.digest,
                completed: layer.completed,
                total: layer.total,
                sampledAtMs: layer.sampledAtMs,
                rateBytesPerSecond: layer.rateBytesPerSecond,
                etaSeconds: layer.etaSeconds
            }
            pullStableRateSamples = layer.stableSamples
            if (layer.total > 0) {
                pullProgress = Math.min(1, layer.completed / layer.total)
                pullPercent = Math.round(pullProgress * 100)
            } else {
                pullProgress = 0
                pullPercent = 0
            }
        } catch (e) {}
    }

    function cancelPull() {
        if (pullState === "streaming") {
            pullState = "cancelling"
            pullStatus = "Cancelling locally..."
            pullReconcileTimer.stop()
            pullProc.running = false
        }
    }

    function failPullReconciliation() {
        pullReconcileTimer.stop()
        pullState = "failed"
        pullStatus = "Failed"
        pullError = "Pull finalization timed out: model was not listed"
        pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
    }

    function schedulePullReconciliation(attempt) {
        if (attempt !== pullAttempt || pullState !== "reconciling") return
        var nowMs = reconciliationClock.nowMs()
        if (nowMs >= pullReconcileDeadlineAtMs) {
            failPullReconciliation()
            return
        }
        var logicalDelayMs = OllamaPullLogic.nextReconcileDelayMs(
            pullReconcileAttempts, nowMs, pullReconcileDeadlineAtMs)
        pullReconcileTimer.attempt = attempt
        pullReconcileTimer.logicalDelayMs = logicalDelayMs
        pullReconcileTimer.interval = Math.max(1,
            reconciliationClock.timerIntervalMs(logicalDelayMs))
        pullReconcileTimer.restart()
    }

    function finishPull(attempt, exitCode) {
        if (attempt !== pullAttempt) return
        if (pullState === "cancelling") {
            pullReconcileTimer.stop()
            pullState = "cancelled"
            pullStatus = "Cancelled locally"
            pullError = ""
            pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
            return
        }
        if (pullState !== "streaming") return
        var state = OllamaDataLogic.pullResultState(exitCode, pullLastLine)
        if (state.valid) {
            pullProgress = 1
            pullState = "reconciling"
            pullStatus = "Finalizing..."
            pullReconcileStartedAtMs = reconciliationClock.nowMs()
            pullReconcileDeadlineAtMs = pullReconcileStartedAtMs + 180000
            refreshEpoch += 1
            tagsRefreshPending = false
            pullReconcileAttempts = 0
            schedulePullReconciliation(attempt)
            refreshLoaded()
        } else {
            pullError = state.error
            pullStatus = "Failed"
            pullState = "failed"
            pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
        }
    }

    function requestPullReconciliation(attempt) {
        if (attempt !== pullAttempt || pullState !== "reconciling") return
        if (reconciliationClock.nowMs() >= pullReconcileDeadlineAtMs) {
            failPullReconciliation()
            return
        }
        if (tagsProc.running) {
            schedulePullReconciliation(attempt)
            return
        }
        pullReconcileAttempts += 1
        tagsProc.pullAttempt = attempt
        tagsProc.refreshEpoch = refreshEpoch
        tagsProc.command = buildRequest("GET", "/api/tags")
        tagsProc.running = true
    }

    function handlePullTags(attempt, raw, requestEpoch) {
        if (attempt !== pullAttempt || pullState !== "reconciling") return
        if (requestEpoch !== refreshEpoch) return
        if (reconciliationClock.nowMs() >= pullReconcileDeadlineAtMs) {
            failPullReconciliation()
            return
        }
        var visible = false
        var models = null
        try {
            var response = decodeResponse(raw)
            if (successful(response)) {
                models = parseTags(response.body)
                for (var i = 0; i < models.length; i++) {
                    if (models[i].name === pullModelName) {
                        visible = true
                        break
                    }
                }
            }
        } catch (error) {}
        if (visible) {
            installedModels = models
            tagsConnected = true
            tagsError = ""
            pullState = "success"
            pullStatus = "Done"
            pullError = ""
            pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
            pullResultTimer.restart()
        } else {
            schedulePullReconciliation(attempt)
        }
    }

    Process {
        id: pullProc
        property int attempt: 0
        property bool _exited: false
        stdout: SplitParser {
            onRead: function(line) {
                var text = String(line || "").trim()
                if (!text) return
                if (pullProc.attempt !== ollama.pullAttempt) return
                ollama.pullLastLine = text
                ollama.applyPullProgress(text)
            }
        }
        onExited: function(code) {
            _exited = true
            ollama.finishPull(attempt, code)
        }
        onRunningChanged: {
            if (running) { _exited = false; return }
            if (!_exited && attempt === ollama.pullAttempt && ollama.pullState === "streaming") {
                ollama.pullError = "Download failed"
                ollama.pullStatus = "Failed"
                ollama.pullState = "failed"
                ollama.pullElapsedSeconds = Math.max(0,
                    (Date.now() - ollama.pullStartedAtMs) / 1000)
            }
        }
    }

    Timer {
        id: pullReconcileTimer
        property int attempt: 0
        property double logicalDelayMs: 0
        interval: 1000
        repeat: false
        onTriggered: {
            if (attempt !== ollama.pullAttempt || ollama.pullState !== "reconciling") return
            ollama.reconciliationClock.delayElapsed(logicalDelayMs)
            ollama.requestPullReconciliation(attempt)
        }
    }

    Timer {
        id: pullResultTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (ollama.pullState !== "success") return
            ollama.pullState = "idle"
            ollama.pullStatus = ""
            ollama.pullElapsedSeconds = 0
        }
    }

    Timer {
        interval: ollama.loadedPollIntervalMs
        running: ollama.enabled && ollama.panelVisible
        repeat: true
        triggeredOnStart: false
        onTriggered: ollama.refreshLoaded(true)
    }

}
