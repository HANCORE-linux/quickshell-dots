import QtQuick
import Quickshell
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic

Item {
    id: ollama

    property string baseUrl: "http://localhost:11434"
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
    property string pendingLoadModel: ""
    property var modelsToEject: []
    property bool pullBusy: false
    property string pullModelName: ""
    property double pullProgress: 0
    property string pullStatus: ""
    property string pullError: ""

    readonly property double loadedVramBytes: sumLoadedVram(loadedModels)
    readonly property var models: reconcileModels(installedModels, loadedModels)
    readonly property string configPath: "/etc/systemd/system/ollama.service.d/override.conf"
    readonly property bool refreshRunning: versionProc.running || tagsProc.running || loadedProc.running

    function decodeResponse(raw) {
        return OllamaDataLogic.decodeResponse(raw)
    }

    function buildRequest(method, path, payload) {
        return OllamaDataLogic.buildRequest(baseUrl, method, path, payload)
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

    function applyVersion(raw) {
        var state = OllamaDataLogic.versionState(raw, version)
        connected = state.connected
        version = state.version
        lastError = state.lastError
    }

    function applyTags(raw) {
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

    function applyLoaded(raw) {
        var response = decodeResponse(raw)
        if (!successful(response)) {
            lastError = errorMessage(response, "Unable to read loaded Ollama models")
            return
        }
        try {
            loadedModels = parseLoaded(response.body)
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
        if (pendingLoadModel !== "" && ok) {
            if (modelsToEject.length > 0) {
                ejectModel(modelsToEject.pop())
            } else {
                var name = pendingLoadModel
                pendingLoadModel = ""
                modelsToEject = []
                loadModel(name)
            }
        } else if (!ok) {
            pendingLoadModel = ""
            modelsToEject = []
        }
    }

    function refreshAll() {
        refreshVersion()
        refreshTags()
        refreshLoaded()
    }

    function refreshVersion() {
        if (versionProc.running) return
        versionProc.command = buildRequest("GET", "/api/version")
        versionProc.running = true
    }

    function refreshTags() {
        if (tagsProc.running) return
        tagsProc.command = buildRequest("GET", "/api/tags")
        tagsProc.running = true
    }

    function refreshLoaded() {
        if (loadedProc.running) return
        loadedProc.command = buildRequest("GET", "/api/ps")
        loadedProc.running = true
    }

    function refreshGpu() {
        if (gpuProc.running) return
        gpuProc.running = true
    }

    function runModelAction(name, keepAlive, actionName) {
        if (busy || !name) return
        beginActionState(actionName, name)
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

    function loadModel(name) { runModelAction(name, -1, "load") }
    function ejectModel(name) { runModelAction(name, 0, "eject") }
    function deleteModel(name) { runModelAction(name, "delete", "delete") }

    function loadModelSolo(name) {
        if (busy || !name) return
        var loaded = loadedModels.slice()
        if (loaded.length === 0) {
            loadModel(name)
            return
        }
        pendingLoadModel = name
        modelsToEject = loaded.map(function(m) { return m.name })
        ejectModel(modelsToEject.pop())
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
        stdout: StdioCollector { onStreamFinished: ollama.applyVersion(this.text) }
    }

    Process {
        id: tagsProc
        stdout: StdioCollector { onStreamFinished: ollama.applyTags(this.text) }
    }

    Process {
        id: loadedProc
        stdout: StdioCollector { onStreamFinished: ollama.applyLoaded(this.text) }
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
        if (pullBusy || busy || !name) return
        var cleanName = String(name).replace(/^ollama\s+run\s+/i, "").trim()
        if (!cleanName) return
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
