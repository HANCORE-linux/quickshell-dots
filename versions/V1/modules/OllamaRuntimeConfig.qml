import QtQuick
import Quickshell
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic

Item {
    id: config

    property string path: Quickshell.env("HOME") + "/.cache/qs-ollama-config.json"
    property var selectedKeepAlive: "5m"
    property var selectedNumCtx: null
    property bool dirty: false
    property bool _editorExited: false

    signal loaded()
    signal reloaded()
    signal errorOccurred(string message)

    function applyFile() {
        var text = String(runtimeConfigFile.text() || "").trim()
        if (!text) return
        var state = OllamaDataLogic.runtimeConfigState(text)
        if (!state.valid) return
        selectedKeepAlive = state.keepAlive
        selectedNumCtx = state.numCtx
        dirty = state.dirty
    }

    function parseContextInput(raw) {
        return OllamaDataLogic.parseContextInput(raw)
    }

    function setKeepAlive(value) {
        if (value !== "5m" && value !== "30m" && value !== -1) return
        selectedKeepAlive = value
        dirty = true
        save()
    }

    function setNumCtx(value) {
        if (value !== null && !(typeof value === "number" && value > 0)) return
        selectedNumCtx = value
        dirty = true
        save()
    }

    function save() {
        var state = { keepAlive: selectedKeepAlive, numCtx: selectedNumCtx, dirty: dirty }
        runtimeConfigFile.setText(JSON.stringify(state, null, 2))
    }

    function reload() {
        runtimeConfigFile.reload()
    }

    function openEditor() {
        var parsed = OllamaDataLogic.parseEditorCommand(Quickshell.env("EDITOR") || "nvim")
        if (!parsed.valid) {
            errorOccurred(parsed.error)
            return
        }
        runtimeConfigEditProc.command = [
            "omarchy-launch-floating-terminal-with-presentation",
            OllamaDataLogic.buildEditorShellCommand(parsed.argv, path)
        ]
        runtimeConfigEditProc.running = true
    }

    FileView {
        id: runtimeConfigFile
        path: config.path
        watchChanges: true
        printErrors: false
        onFileChanged: runtimeConfigFile.reload()
        onLoaded: {
            config.applyFile()
            config.loaded()
            if (config._editorExited) {
                config._editorExited = false
                config.reloaded()
            }
        }
    }

    Process {
        id: runtimeConfigEditProc
        onExited: {
            config._editorExited = true
            config.reload()
        }
    }
}
