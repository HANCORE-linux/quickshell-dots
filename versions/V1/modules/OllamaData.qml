import QtQuick
import Quickshell
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic

Item {
    id: ollama

    property string baseUrl: "http://127.0.0.1:11434"
    enabled: false
    property bool connected: false
    property string version: ""
    property var installedModels: []
    property var loadedModels: []
    property int gpuPercent: -1
    property var gpuHistory: []
    readonly property int gpuMaxSamples: 30
    property bool busy: false
    property string pendingAction: ""
    property string pendingModel: ""
    property string lastError: ""
    property string operationError: ""
    property bool operationInProgress: false
    property string operationState: "idle"
    property int operationId: 0
    property int refreshEpoch: 0
    property var stopQueue: []
    property int verificationAttempts: 0
    property string verificationKind: ""
    property string failureMessage: ""
    property bool pullBusy: false
    property string pullModelName: ""
    property double pullProgress: 0
    property string pullStatus: ""
    property string pullError: ""

    readonly property double loadedVramBytes: sumLoadedVram(loadedModels)
    readonly property var models: reconcileModels(installedModels, loadedModels)
    readonly property string configPath: "/etc/systemd/system/ollama.service.d/override.conf"
    readonly property bool refreshRunning: versionProc.running || tagsProc.running || loadedProc.running
    readonly property bool controlsLocked: operationInProgress || busy || pullBusy
    readonly property string displayError: operationError !== "" ? operationError : lastError
    readonly property string operationMessage:
        OllamaDataLogic.operationMessage(operationState, pendingModel)

    function decodeResponse(raw) {
        return OllamaDataLogic.decodeResponse(raw)
    }

    function buildRequest(method, path, payload, maxTime) {
        return OllamaDataLogic.buildRequest(baseUrl, method, path, payload, maxTime)
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
        connected = state.connected
        version = state.version
        lastError = state.lastError
    }

    function applyTags(raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        var response = decodeResponse(raw)
        if (!successful(response)) {
            lastError = errorMessage(response, "Unable to list Ollama models")
            return
        }
        try {
            installedModels = parseTags(response.body)
            lastError = ""
        } catch (error) {
            lastError = "Invalid Ollama model response"
        }
    }

    function applyLoaded(raw, requestEpoch) {
        if (requestEpoch !== refreshEpoch) return
        var response = decodeResponse(raw)
        if (!successful(response)) {
            lastError = errorMessage(response, "Unable to read loaded Ollama models")
            return
        }
        try {
            loadedModels = parseLoaded(response.body)
            connected = true
            lastError = ""
        } catch (error) {
            lastError = "Invalid Ollama loaded-model response"
        }
    }

    function applyAction(raw) {
        var response = decodeResponse(raw)
        var ok = successful(response)
        if (ok) {
            lastError = ""
        } else {
            var verb = pendingAction === "delete" ? "delete" : "update"
            lastError = errorMessage(response, "Unable to " + verb + " Ollama model")
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
        if (operationInProgress || tagsProc.running) return
        tagsProc.refreshEpoch = refreshEpoch
        tagsProc.command = buildRequest("GET", "/api/tags")
        tagsProc.running = true
    }

    function refreshLoaded() {
        if (operationInProgress || loadedProc.running) return
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
        operationState = "checking"
        pendingAction = "load"
        pendingModel = selected
        stopQueue = []
        verificationAttempts = 0
        failureMessage = ""
        operationError = ""
        lastError = ""
        requestOperationModels("initial", operationId)
    }

    function operationModels(raw) {
        var response = decodeResponse(raw)
        if (!successful(response))
            throw new Error(errorMessage(response, "Unable to read loaded Ollama models"))
        return parseLoaded(response.body)
    }

    function finishExclusiveLoad(ok, models) {
        if (models !== undefined && models !== null) loadedModels = models
        operationInProgress = false
        busy = false
        pendingAction = ""
        pendingModel = ""
        stopQueue = []
        verificationAttempts = 0
        verificationKind = ""
        operationState = ok ? "idle" : "error"
        if (ok) operationError = ""
        if (ok) lastError = ""
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
                connected = false
                throw new Error("Unable to reach Ollama")
            }
            models = operationModels(raw)
            connected = true
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
            stopQueue = OllamaDataLogic.conflictingModelNames(models, pendingModel)
            if (stopQueue.length > 0) stopNextModel()
            else beginSelectedModelLoad()
            return
        }
        if (purpose === "unloadVerify") {
            var conflicts = OllamaDataLogic.conflictingModelNames(models, pendingModel)
            if (conflicts.length === 0) beginSelectedModelLoad()
            else if (verificationAttempts < 10) verificationRetryTimer.restart()
            else failExclusiveLoad("Unable to unload previous Ollama model")
            return
        }
        if (purpose === "loadVerify") {
            var state = OllamaDataLogic.exclusiveLoadState(models, pendingModel)
            if (state.valid) finishExclusiveLoad(true, models)
            else if (verificationAttempts < 10) verificationRetryTimer.restart()
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
        stopProc.requestId = operationId
        stopProc.modelName = modelName
        stopProc.timedOut = false
        stopProc.command = ["env", "OLLAMA_HOST=" + baseUrl, "ollama", "stop", modelName]
        stopProc.running = true
        stopTimeoutTimer.restart()
    }

    function handleStopExit(requestId, modelName, exitCode, timedOut) {
        stopTimeoutTimer.stop()
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
        loadProc.command = buildRequest("POST", "/api/generate", {
            model: pendingModel,
            keep_alive: -1,
            stream: false
        }, "120")
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
        if (controlsLocked || !name) return
        beginActionState(actionName, name)
        operationError = ""
        lastError = ""
        if (actionName === "delete") {
            actionProc.command = buildRequest("DELETE", "/api/delete", { model: name }, "30")
        } else {
            actionProc.command = buildRequest("POST", "/api/generate", {
                model: name,
                stream: false,
                keep_alive: keepAlive
            }, "120")
        }
        actionProc.running = true
    }

    function ejectModel(name) { runModelAction(name, 0, "eject") }
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

    function openConfiguration() {
        configProc.command = [
            "omarchy-launch-floating-terminal-with-presentation",
            "SUDO_EDITOR=\"${EDITOR:-nvim}\" sudoedit " + configPath
        ]
        configProc.running = true
    }

    function reloadConfiguration() {
        reloadProc.command = [
            "omarchy-launch-floating-terminal-with-presentation",
            "sudo systemctl daemon-reload && sudo systemctl restart ollama && qs -c bar ipc call ollama refresh"
        ]
        reloadProc.running = true
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
    }

    Process {
        id: loadedProc
        property int refreshEpoch: -1
        stdout: StdioCollector {
            onStreamFinished: ollama.applyLoaded(this.text, loadedProc.refreshEpoch)
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
            ollama.lastError = ollama.pendingAction === "delete"
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
        id: stopProc
        property int requestId: 0
        property string modelName: ""
        property bool timedOut: false
        onExited: function(code) {
            ollama.handleStopExit(requestId, modelName, code, timedOut)
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
        id: stopTimeoutTimer
        interval: 30000
        repeat: false
        onTriggered: {
            if (!stopProc.running) return
            stopProc.timedOut = true
            stopProc.running = false
        }
    }

    Process {
        id: gpuProc
        command: [
            "bash", "-c",
            "if command -v nvidia-smi &>/dev/null; then "
            + "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1; "
            + "else "
            + "for card in /sys/class/drm/card[0-9]*/device/gpu_busy_percent; do "
            + "[ -f \"$card\" ] && { cat \"$card\"; exit 0; }; "
            + "done; "
            + "for hwmon in /sys/class/hwmon/hwmon[0-9]*/device/gpu_busy_percent; do "
            + "[ -f \"$hwmon\" ] && { cat \"$hwmon\"; exit 0; }; "
            + "done; "
            + "echo -1; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var value = parseInt(this.text.trim())
                ollama.gpuPercent = isNaN(value) ? -1 : value
                var h = ollama.gpuHistory.slice()
                h.push(isNaN(value) ? 0 : value / 100)
                if (h.length > ollama.gpuMaxSamples) h.shift()
                ollama.gpuHistory = h
            }
        }
    }

    Process { id: configProc }
    Process { id: reloadProc }

    function pullModel(name) {
        if (controlsLocked || !name) return
        var cleanName = String(name).replace(/^ollama\s+run\s+/i, "").trim()
        if (!cleanName) return
        operationError = ""
        pullBusy = true
        pullModelName = cleanName
        pullProgress = 0
        pullStatus = "Connecting..."
        pullError = ""
        pullProc.command = [
            "bash", "-c",
            "rm -f /tmp/ollama_pull_output && " +
            "curl -sS --no-buffer -X POST " +
            "-H 'Content-Type: application/json' -H 'Accept: application/json' " +
            '-d "$1" ' + baseUrl + "/api/pull " +
            "-o /tmp/ollama_pull_output " +
            "--max-time 3600 --connect-timeout 3; echo $?",
            "bash",
            JSON.stringify({model: cleanName, stream: true})
        ]
        pullProc.running = true
        pullProgressTimer.running = true
    }

    function applyPullProgress(raw) {
        var text = String(raw || "").trim()
        if (!text) return
        try {
            var data = JSON.parse(text)
            if (data.total > 0 && data.completed !== undefined) {
                pullProgress = Math.min(1, data.completed / data.total)
            }
            if (data.status) pullStatus = data.status
        } catch (e) {}
    }

    function finishPull(raw) {
        pullProgressTimer.running = false
        var text = String(raw || "").trim()
        var exitCode = parseInt(text)
        if (exitCode === 0) {
            pullProgress = 1
            pullStatus = "Done"
            refreshTags()
            refreshLoaded()
        } else {
            pullError = "Download failed"
            pullStatus = "Failed"
        }
        pullBusy = false
    }

    Process {
        id: pullProc
        property bool _streamFinished: false
        stdout: StdioCollector {
            onStreamFinished: {
                ollama.finishPull(this.text)
                pullProc._streamFinished = true
            }
        }
        onRunningChanged: {
            if (running) {
                _streamFinished = false
                pullProgressTimer.running = true
                return
            }
            if (_streamFinished) { _streamFinished = false; return }
            if (!ollama.pullBusy) return
            ollama.pullError = "Download failed"
            ollama.pullBusy = false
            pullProgressTimer.running = false
        }
    }

    Process {
        id: progressReaderProc
        stdout: StdioCollector {
            onStreamFinished: ollama.applyPullProgress(this.text)
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
        interval: 2000
        running: ollama.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: ollama.refreshLoaded()
    }

    Timer {
        interval: 2000
        running: ollama.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: ollama.refreshGpu()
    }

    Timer {
        id: pullProgressTimer
        interval: 500
        running: false
        repeat: true
        onTriggered: {
            if (!progressReaderProc.running) {
                progressReaderProc.command = ["bash", "-c", "tail -1 /tmp/ollama_pull_output 2>/dev/null || echo ''"]
                progressReaderProc.running = true
            }
        }
    }
}
