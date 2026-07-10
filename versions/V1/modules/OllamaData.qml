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
    property bool busy: false
    property string pendingAction: ""
    property string pendingModel: ""
    property string lastError: ""

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
        if (successful(response)) {
            lastError = ""
        } else {
            lastError = errorMessage(response, "Unable to update Ollama model")
        }
        clearActionState()
        refreshLoaded()
        if (successful(response)) refreshTags()
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
        actionProc.command = buildRequest("POST", "/api/generate", {
            model: name,
            stream: false,
            keep_alive: keepAlive
        }, "120")
        actionProc.running = true
    }

    function loadModel(name) { runModelAction(name, -1, "load") }
    function ejectModel(name) { runModelAction(name, 0, "eject") }

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
            ollama.lastError = "Unable to update Ollama model"
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
            }
        }
    }

    Process { id: configProc }
    Process { id: reloadProc }

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
}
