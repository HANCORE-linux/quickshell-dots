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
    property int gpuPercent: -1
    property var gpuHistory: []
    readonly property int gpuMaxSamples: 30
    property bool busy: false
    property string pendingAction: ""
    property string pendingModel: ""
    property string versionError: ""
    property string tagsError: ""
    property string loadedError: ""
    property string actionError: ""
    property bool versionConnected: false
    property bool tagsConnected: false
    property bool loadedConnected: false
    property string operationError: ""
    property bool operationInProgress: false
    property string operationState: "idle"
    property string operationMode: ""
    property int operationId: 0
    property int refreshEpoch: 0
    property bool tagsRefreshPending: false
    property bool loadedRefreshPending: false
    property var stopQueue: []
    property int verificationAttempts: 0
    property string verificationKind: ""
    property string failureMessage: ""
    property bool pullBusy: false
    property string pullModelName: ""
    property double pullProgress: 0
    property int pullPercent: 0
    property string pullStatus: ""
    property string pullError: ""
    property bool panelVisible: false
    property var selectedKeepAlive: "5m"
    property var selectedNumCtx: null
    property bool configDirty: false

    readonly property double loadedVramBytes: sumLoadedVram(loadedModels)
    readonly property var models: reconcileModels(installedModels, loadedModels)
    readonly property string runtimeConfigPath:
        Quickshell.env("HOME") + "/.cache/qs-ollama-config.json"
    property string pullLastLine: ""
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
    readonly property string operationMessage:
        OllamaDataLogic.operationMessage(operationState, pendingModel)

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

    function applyTags(raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        var response = decodeResponse(raw)
        if (!successful(response)) {
            tagsError = errorMessage(response, "Unable to list Ollama models")
            return
        }
        try {
            installedModels = parseTags(response.body)
            tagsConnected = true
            tagsError = ""
        } catch (error) {
            tagsError = "Invalid Ollama model response"
        }
    }

    function applyLoaded(raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        var response = decodeResponse(raw)
        if (!successful(response)) {
            loadedError = errorMessage(response, "Unable to read loaded Ollama models")
            return
        }
        try {
            loadedModels = parseLoaded(response.body)
            loadedConnected = true
            loadedError = ""
        } catch (error) {
            loadedError = "Invalid Ollama loaded-model response"
        }
    }

    function applyAction(raw) {
        var response = decodeResponse(raw)
        var ok = successful(response)
        if (ok) {
            actionError = ""
        } else {
            var verb = pendingAction === "delete" ? "delete" : "update"
            actionError = errorMessage(response, "Unable to " + verb + " Ollama model")
        }
        clearActionState()
        refreshLoaded()
        if (ok) refreshTags()
    }

    function refreshAll() {
        refreshVersion()
        refreshTags()
        refreshLoaded()
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

    function refreshLoaded() {
        if (operationInProgress) return
        if (loadedProc.running) { loadedRefreshPending = true; return }
        loadedProc.refreshEpoch = refreshEpoch
        loadedProc.command = buildRequest("GET", "/api/ps")
        loadedProc.running = true
    }

    function refreshGpu() {
        if (gpuProc.running) return
        gpuProc.running = true
    }

    function loadModel(name) {
        var selected = String(name || "")
        if (!selected || controlsLocked) return
        refreshEpoch += 1
        operationId += 1
        operationInProgress = true
        busy = true
        operationMode = ""
        operationState = "checking"
        pendingAction = "load"
        pendingModel = selected
        stopQueue = []
        verificationAttempts = 0
        failureMessage = ""
        operationError = ""
        actionError = ""
        requestOperationModels("initial", operationId)
    }

    function operationModels(raw) {
        var response = decodeResponse(raw)
        if (!successful(response))
            throw new Error(errorMessage(response, "Unable to read loaded Ollama models"))
        return parseLoaded(response.body)
    }

    function finishExclusiveLoad(ok, models) {
        var appliedConfig = ok && operationMode === "apply"
        if (models !== undefined && models !== null) loadedModels = models
        operationInProgress = false
        busy = false
        pendingAction = ""
        pendingModel = ""
        operationMode = ""
        stopQueue = []
        verificationAttempts = 0
        verificationKind = ""
        failureMessage = ""
        operationState = ok ? "idle" : "error"
        if (ok) operationError = ""
        if (ok) actionError = ""
        if (appliedConfig) {
            configDirty = false
            saveRuntimeConfig()
        }
    }

    function failExclusiveLoad(message) {
        failureMessage = String(message || "Unable to change Ollama model")
        operationError = failureMessage
        operationState = "error"
        Qt.callLater(function() {
            if (operationInProgress) requestOperationModels("failureRefresh", operationId)
        })
    }

    function requestOperationModels(purpose, requestId) {
        if (!operationInProgress || requestId !== operationId || operationPsProc.running) return
        operationPsProc.purpose = purpose
        operationPsProc.requestId = requestId
        operationPsProc.command = buildRequest("GET", "/api/ps")
        operationPsProc.running = true
    }

    function handleOperationModels(purpose, requestId, exitCode, raw) {
        if (!operationInProgress || requestId !== operationId) return
        var models
        try {
            if (exitCode !== 0) {
                loadedConnected = false
                throw new Error("Unable to reach Ollama")
            }
            models = operationModels(raw)
            loadedConnected = true
        } catch (error) {
            if (purpose === "failureRefresh") {
                finishExclusiveLoad(false, null)
            } else {
                failExclusiveLoad(String(error.message || error))
            }
            return
        }

        loadedModels = models
        if (purpose === "failureRefresh") {
            finishExclusiveLoad(false, models)
            return
        }
        if (purpose === "initial") {
            if (operationMode === "apply") {
                if (models.length > 0) {
                    pendingModel = models[0].name
                    stopQueue = models.map(function(m) { return m.name })
                } else {
                    operationInProgress = false
                    busy = false
                    operationMode = ""
                    operationState = "idle"
                    pendingAction = ""
                    pendingModel = ""
                    configDirty = false
                    saveRuntimeConfig()
                    return
                }
            } else if (operationMode === "eject") {
                stopQueue = models.map(function(m) { return m.name })
                if (stopQueue.length > 0) {
                    stopNextModel()
                    return
                }
                finishExclusiveLoad(true, models)
                return
            }
            stopQueue = OllamaDataLogic.conflictingModelNames(models, pendingModel)
            if (stopQueue.length > 0) stopNextModel()
            else beginSelectedModelLoad()
            return
        }
        if (purpose === "unloadVerify") {
            if (operationMode === "eject") {
                finishExclusiveLoad(true, models)
                return
            }
            var conflicts = OllamaDataLogic.conflictingModelNames(models, pendingModel)
            if (conflicts.length === 0) beginSelectedModelLoad()
            else if (verificationAttempts < 10) verificationRetryTimer.restart()
            else failExclusiveLoad("Unable to unload previous Ollama model")
            return
        }
        if (purpose === "loadVerify") {
            var expectedContext = operationMode === "apply" ? selectedNumCtx : null
            var state = OllamaDataLogic.loadVerificationState(models, pendingModel, expectedContext)
            if (state.valid) finishExclusiveLoad(true, models)
            else if (state.retry && verificationAttempts < 10) verificationRetryTimer.restart()
            else failExclusiveLoad(state.error)
        }
    }

    function beginVerification(kind) {
        verificationKind = kind
        verificationAttempts = 0
        requestVerification()
    }

    function requestVerification() {
        if (!operationInProgress) return
        verificationAttempts += 1
        operationState = verificationKind === "unload" ? "verifyingUnload" : "verifyingLoad"
        requestOperationModels(verificationKind === "unload" ? "unloadVerify" : "loadVerify",
                               operationId)
    }

    function stopNextModel() {
        if (!operationInProgress) return
        if (stopQueue.length === 0) {
            beginVerification("unload")
            return
        }
        var queue = stopQueue.slice()
        var modelName = queue.shift()
        stopQueue = queue
        operationState = "unloading"
        unloadProc.requestId = operationId
        unloadProc.modelName = modelName
        unloadProc.timedOut = false
        unloadProc.command = buildRequest("POST", "/api/generate",
            OllamaDataLogic.buildLoadPayload(modelName, 0, null), "10")
        unloadProc.running = true
        unloadTimeoutTimer.restart()
    }

    function handleUnloadExit(requestId, modelName, exitCode, timedOut) {
        unloadTimeoutTimer.stop()
        if (!operationInProgress || requestId !== operationId) return
        if (timedOut) {
            failExclusiveLoad("Timed out unloading Ollama model: " + modelName)
        } else if (exitCode !== 0) {
            failExclusiveLoad("Unable to unload Ollama model: " + modelName)
        } else {
            stopNextModel()
        }
    }

    function beginSelectedModelLoad() {
        if (!operationInProgress) return
        operationState = "loading"
        loadProc.requestId = operationId
        loadProc.command = buildRequest("POST", "/api/generate", buildLoadPayload(pendingModel), "120")
        loadProc.running = true
    }

    function handleLoadExit(requestId, exitCode, raw) {
        if (!operationInProgress || requestId !== operationId) return
        var response = decodeResponse(raw)
        if (exitCode !== 0 || !successful(response)) {
            failExclusiveLoad(errorMessage(response, "Unable to load selected Ollama model"))
            return
        }
        var generateState = OllamaDataLogic.generateResponseState(response.body)
        if (!generateState.valid) {
            failExclusiveLoad(generateState.error)
            return
        }
        beginVerification("load")
    }

    function runModelAction(name, keepAlive, actionName) {
        if (controlsLocked || !name || actionName !== "delete") return
        beginActionState(actionName, name)
        operationError = ""
        actionError = ""
        refreshEpoch += 1
        actionProc.command = buildRequest("DELETE", "/api/delete", { model: name }, "30")
        actionProc.running = true
    }

    function ejectModel(name) { startUnloadOperation("eject", name) }
    function deleteModel(name) { runModelAction(name, "delete", "delete") }

    function beginActionState(actionName, name) {
        var state = OllamaDataLogic.beginActionState(actionName, name)
        busy = state.busy
        pendingAction = state.pendingAction
        pendingModel = state.pendingModel
    }

    function clearActionState() {
        var state = OllamaDataLogic.clearActionState()
        busy = state.busy
        pendingAction = state.pendingAction
        pendingModel = state.pendingModel
    }

    function openConfiguration() {}
    function reloadConfiguration() {}

    function applyRuntimeConfigFile() {
        var text = String(runtimeConfigFile.text() || "").trim()
        if (!text) return
        var state = OllamaDataLogic.runtimeConfigState(text)
        if (!state.valid) return
        selectedKeepAlive = state.keepAlive
        selectedNumCtx = state.numCtx
        configDirty = state.dirty
    }

    function saveRuntimeConfig() {
        var cfg = { keepAlive: selectedKeepAlive, numCtx: selectedNumCtx, dirty: configDirty }
        runtimeConfigFile.setText(JSON.stringify(cfg, null, 2))
    }

    function parseContextInput(raw) {
        return OllamaDataLogic.parseContextInput(raw)
    }

    function setKeepAlive(value) {
        if (value !== "5m" && value !== "30m" && value !== -1) return
        selectedKeepAlive = value
        configDirty = true
        saveRuntimeConfig()
    }

    function setNumCtx(value) {
        if (value !== null && !(typeof value === "number" && value > 0)) return
        selectedNumCtx = value
        configDirty = true
        saveRuntimeConfig()
    }

    function applyRuntimeConfiguration() {
        if (controlsLocked) return
        startUnloadOperation("apply", "")
    }

    function startUnloadOperation(mode, name) {
        refreshEpoch += 1
        operationId += 1
        operationInProgress = true
        busy = true
        operationMode = mode
        operationState = "checking"
        pendingAction = mode
        pendingModel = String(name || "")
        stopQueue = []
        verificationAttempts = 0
        failureMessage = ""
        operationError = ""
        actionError = ""
        if (mode === "apply") {
            saveRuntimeConfig()
        }
        requestOperationModels("initial", operationId)
    }

    onEnabledChanged: if (enabled) refreshAll()
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
            if (ollama.loadedRefreshPending) {
                ollama.loadedRefreshPending = false
                ollama.refreshLoaded()
            }
        }
    }

    Process {
        id: actionProc
        property bool _streamFinished: false
        stdout: StdioCollector {
            onStreamFinished: {
                ollama.applyAction(this.text)
                actionProc._streamFinished = true
            }
        }
        onRunningChanged: {
            if (running) { _streamFinished = false; return }
            if (_streamFinished) { _streamFinished = false; return }
            if (!ollama.busy) return
            ollama.actionError = ollama.pendingAction === "delete"
                ? "Unable to delete Ollama model" : "Unable to update Ollama model"
            ollama.clearActionState()
            ollama.refreshLoaded()
        }
    }

    Process {
        id: operationPsProc
        property int requestId: 0
        property string purpose: ""
        property bool exitSeen: false
        property bool streamDone: false
        property int resultCode: -1
        property string responseText: ""
        function completeIfReady() {
            if (!exitSeen || !streamDone) return
            ollama.handleOperationModels(purpose, requestId, resultCode, responseText)
        }
        onStarted: {
            exitSeen = false
            streamDone = false
            resultCode = -1
            responseText = ""
        }
        stdout: StdioCollector {
            onStreamFinished: {
                operationPsProc.responseText = this.text
                operationPsProc.streamDone = true
                operationPsProc.completeIfReady()
            }
        }
        onExited: function(code) {
            resultCode = code
            exitSeen = true
            completeIfReady()
        }
    }

    Process {
        id: unloadProc
        property int requestId: 0
        property string modelName: ""
        property bool timedOut: false
        onExited: function(code) {
            ollama.handleUnloadExit(requestId, modelName, code, timedOut)
        }
    }

    Process {
        id: loadProc
        property int requestId: 0
        property bool exitSeen: false
        property bool streamDone: false
        property int resultCode: -1
        property string responseText: ""
        function completeIfReady() {
            if (!exitSeen || !streamDone) return
            ollama.handleLoadExit(requestId, resultCode, responseText)
        }
        onStarted: {
            exitSeen = false
            streamDone = false
            resultCode = -1
            responseText = ""
        }
        stdout: StdioCollector {
            onStreamFinished: {
                loadProc.responseText = this.text
                loadProc.streamDone = true
                loadProc.completeIfReady()
            }
        }
        onExited: function(code) {
            resultCode = code
            exitSeen = true
            completeIfReady()
        }
    }

    Timer {
        id: verificationRetryTimer
        interval: 500
        repeat: false
        onTriggered: ollama.requestVerification()
    }

    Timer {
        id: unloadTimeoutTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (!unloadProc.running) return
            unloadProc.timedOut = true
            unloadProc.running = false
        }
    }

    Process {
        id: gpuProc
        command: [
            "bash", "-c",
            "{ command -v nvidia-smi &>/dev/null && "
            + "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null; } ; "
            + "for card in /sys/class/drm/card[0-9]*/device/gpu_busy_percent; do "
            + "[ -r \"$card\" ] && cat \"$card\"; "
            + "done; "
            + "for hwmon in /sys/class/hwmon/hwmon[0-9]*/device/gpu_busy_percent; do "
            + "[ -r \"$hwmon\" ] && cat \"$hwmon\"; "
            + "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var value = OllamaDataLogic.maxGpuPercent(this.text)
                ollama.gpuPercent = value
                var h = ollama.gpuHistory.slice()
                h.push(value < 0 ? 0 : value / 100)
                if (h.length > ollama.gpuMaxSamples) h.shift()
                ollama.gpuHistory = h
            }
        }
    }

    FileView {
        id: runtimeConfigFile
        path: runtimeConfigPath
        onLoaded: ollama.applyRuntimeConfigFile()
    }

    function openRuntimeConfig() {
        var editor = Quickshell.env("EDITOR") || "nvim"
        runtimeConfigEditProc.command = [
            "omarchy-launch-floating-terminal-with-presentation",
            editor + " " + shellQuote(runtimeConfigPath)
        ]
        runtimeConfigEditProc.running = true
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    Process { id: runtimeConfigEditProc }

    function pullModel(name) {
        if (controlsLocked || !name) return
        var cleanName = String(name).replace(/^ollama\s+run\s+/i, "").trim()
        if (!cleanName) return
        operationError = ""
        pullBusy = true
        pullModelName = cleanName
        pullProgress = 0
        pullPercent = 0
        pullStatus = "Connecting..."
        pullError = ""
        pullLastLine = ""
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

    function applyPullProgress(raw) {
        var text = String(raw || "").trim()
        if (!text) return
        try {
            var data = JSON.parse(text)
            if (data.total > 0 && data.completed !== undefined) {
                pullProgress = Math.min(1, data.completed / data.total)
                pullPercent = Math.round(pullProgress * 100)
            }
            if (data.status) pullStatus = data.status
        } catch (e) {}
    }

    function finishPull(exitCode) {
        var state = OllamaDataLogic.pullResultState(exitCode, pullLastLine)
        if (state.valid) {
            pullProgress = 1
            pullStatus = "Done"
            refreshTags()
            refreshLoaded()
        } else {
            pullError = state.error
            pullStatus = "Failed"
        }
        pullBusy = false
    }

    Process {
        id: pullProc
        property int _exitCode: -1
        property bool _exited: false
        stdout: SplitParser {
            onRead: function(line) {
                var text = String(line || "").trim()
                if (!text) return
                ollama.pullLastLine = text
                ollama.applyPullProgress(text)
            }
        }
        onExited: function(code) {
            _exitCode = code
            _exited = true
            if (ollama.pullBusy) ollama.finishPull(code)
        }
        onRunningChanged: {
            if (running) { _exited = false; _exitCode = -1; return }
            if (!_exited && ollama.pullBusy) {
                ollama.pullError = "Download failed"
                ollama.pullBusy = false
            }
        }
    }

    Timer {
        interval: 15000
        running: ollama.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: ollama.refreshVersion()
    }

    Timer {
        interval: ollama.panelVisible ? 2000 : 15000
        running: ollama.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: ollama.refreshLoaded()
    }

    Timer {
        interval: ollama.panelVisible ? 2000 : 15000
        running: ollama.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: ollama.refreshGpu()
    }
}
