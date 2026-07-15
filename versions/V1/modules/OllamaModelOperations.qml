import QtQuick
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic

Item {
    id: operations

    property string baseUrl: "http://127.0.0.1:11434"
    property bool blocked: false
    property var selectedKeepAlive: "5m"
    property var selectedNumCtx: null
    property var models: []
    property bool busy: false
    property string pendingAction: ""
    property string pendingModel: ""
    property string actionError: ""
    property string operationError: ""
    property bool operationInProgress: false
    property string operationState: "idle"
    property string operationMode: ""
    property int operationId: 0
    property var stopQueue: []
    property int verificationAttempts: 0
    property string verificationKind: ""
    property string failureMessage: ""

    readonly property bool controlsLocked: blocked || busy || operationInProgress
    readonly property string operationMessage:
        OllamaDataLogic.operationMessage(operationState, pendingModel)

    signal loadedModelsAccepted(var models)
    signal tagsRefreshRequested()
    signal loadedRefreshRequested()
    signal configurationApplied()
    signal configurationSaveRequested()
    signal refreshEpochInvalidationRequested()
    signal loadedConnectionChanged(bool connected)

    function decodeResponse(raw) {
        return OllamaDataLogic.decodeResponse(raw)
    }

    function buildRequest(method, path, payload, maxTime) {
        return OllamaDataLogic.buildRequest(baseUrl, method, path, payload, maxTime)
    }

    function successful(response) {
        return OllamaDataLogic.successful(response)
    }

    function errorMessage(response, fallback) {
        return OllamaDataLogic.errorMessage(response, fallback)
    }

    function buildLoadPayload(modelName) {
        return OllamaDataLogic.buildLoadPayload(modelName, selectedKeepAlive, selectedNumCtx)
    }

    function loadModel(name) {
        var selected = String(name || "")
        if (!selected || controlsLocked) return
        refreshEpochInvalidationRequested()
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
        return OllamaDataLogic.parseLoaded(response.body)
    }

    function finishExclusiveLoad(ok, acceptedModels) {
        var appliedConfig = ok && operationMode === "apply"
        if (acceptedModels !== undefined && acceptedModels !== null)
            loadedModelsAccepted(acceptedModels)
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
        if (appliedConfig) configurationApplied()
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
        var acceptedModels
        try {
            if (exitCode !== 0) {
                loadedConnectionChanged(false)
                throw new Error("Unable to reach Ollama")
            }
            acceptedModels = operationModels(raw)
            loadedConnectionChanged(true)
        } catch (error) {
            loadedConnectionChanged(false)
            if (purpose === "failureRefresh") finishExclusiveLoad(false, null)
            else failExclusiveLoad(String(error.message || error))
            return
        }

        loadedModelsAccepted(acceptedModels)
        if (purpose === "failureRefresh") {
            finishExclusiveLoad(false, acceptedModels)
            return
        }
        if (purpose === "initial") {
            if (operationMode === "apply") {
                if (acceptedModels.length > 0) {
                    pendingModel = acceptedModels[0].name
                    stopQueue = acceptedModels.map(function(model) { return model.name })
                } else {
                    operationInProgress = false
                    busy = false
                    operationMode = ""
                    operationState = "idle"
                    pendingAction = ""
                    pendingModel = ""
                    configurationApplied()
                    return
                }
            } else if (operationMode === "eject") {
                stopQueue = OllamaDataLogic.ejectQueue(acceptedModels, pendingModel)
                if (stopQueue.length > 0) {
                    stopNextModel()
                    return
                }
                finishExclusiveLoad(true, acceptedModels)
                return
            }
            stopQueue = OllamaDataLogic.conflictingModelNames(acceptedModels, pendingModel)
            if (stopQueue.length > 0) stopNextModel()
            else beginSelectedModelLoad()
            return
        }
        if (purpose === "unloadVerify") {
            if (operationMode === "eject") {
                finishExclusiveLoad(true, acceptedModels)
                return
            }
            var conflicts = OllamaDataLogic.conflictingModelNames(acceptedModels, pendingModel)
            if (conflicts.length === 0) beginSelectedModelLoad()
            else if (verificationAttempts < 10) verificationRetryTimer.restart()
            else failExclusiveLoad("Unable to unload previous Ollama model")
            return
        }
        if (purpose === "loadVerify") {
            var expectedContext = operationMode === "apply" ? selectedNumCtx : null
            var state = OllamaDataLogic.loadVerificationState(
                acceptedModels, pendingModel, expectedContext)
            if (state.valid) finishExclusiveLoad(true, acceptedModels)
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
        if (timedOut) failExclusiveLoad("Timed out unloading Ollama model: " + modelName)
        else if (exitCode !== 0) failExclusiveLoad("Unable to unload Ollama model: " + modelName)
        else stopNextModel()
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
        var state = OllamaDataLogic.generateResponseState(response.body)
        if (!state.valid) {
            failExclusiveLoad(state.error)
            return
        }
        beginVerification("load")
    }

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

    function applyAction(raw) {
        var response = decodeResponse(raw)
        var ok = successful(response)
        if (ok) actionError = ""
        else actionError = errorMessage(response, "Unable to delete Ollama model")
        clearActionState()
        loadedRefreshRequested()
        if (ok) tagsRefreshRequested()
    }

    function runModelAction(name, keepAlive, actionName) {
        if (controlsLocked || !name || actionName !== "delete") return
        beginActionState(actionName, name)
        operationError = ""
        actionError = ""
        refreshEpochInvalidationRequested()
        actionProc.command = buildRequest("DELETE", "/api/delete", { model: name }, "30")
        actionProc.running = true
    }

    function ejectModel(name) { startUnloadOperation("eject", name) }
    function deleteModel(name) { runModelAction(name, "delete", "delete") }

    function applyRuntimeConfiguration() {
        if (controlsLocked) return
        startUnloadOperation("apply", "")
    }

    function startUnloadOperation(mode, name) {
        refreshEpochInvalidationRequested()
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
        if (mode === "apply") configurationSaveRequested()
        requestOperationModels("initial", operationId)
    }

    Process {
        id: actionProc
        property bool streamFinished: false
        stdout: StdioCollector {
            onStreamFinished: {
                operations.applyAction(this.text)
                actionProc.streamFinished = true
            }
        }
        onRunningChanged: {
            if (running) { streamFinished = false; return }
            if (streamFinished) { streamFinished = false; return }
            if (!operations.busy) return
            operations.actionError = "Unable to delete Ollama model"
            operations.clearActionState()
            operations.loadedRefreshRequested()
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
            operations.handleOperationModels(purpose, requestId, resultCode, responseText)
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
            operations.handleUnloadExit(requestId, modelName, code, timedOut)
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
            operations.handleLoadExit(requestId, resultCode, responseText)
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
        onTriggered: operations.requestVerification()
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
}
