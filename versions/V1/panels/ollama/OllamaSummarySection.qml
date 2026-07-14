import QtQuick
import "../../modules"

Column {
    id: summarySection

    required property var root
    required property var data

    width: parent ? parent.width : 0
    spacing: 8

    function formatBytes(bytes) {
        var value = Number(bytes) || 0
        var gib = 1024 * 1024 * 1024
        var mib = 1024 * 1024
        if (value >= gib) return (value / gib).toFixed(1) + " GiB"
        return Math.round(value / mib) + " MiB"
    }

    Rectangle { width: parent.width; height: 1; color: summarySection.root.sep }

    OllamaDetailRow {
        root: summarySection.root
        k: "GPU"
        v: summarySection.data.gpuPercent >= 0
            ? summarySection.data.gpuPercent + "%" : "N/A"
    }
    OllamaDetailRow {
        root: summarySection.root
        k: "Ollama VRAM"
        v: summarySection.formatBytes(summarySection.data.loadedVramBytes)
    }
    OllamaDetailRow {
        root: summarySection.root
        k: "Loaded models"
        v: String(summarySection.data.loadedModels.length)
    }
    OllamaDetailRow {
        root: summarySection.root
        k: "Context"
        v: {
            if (summarySection.data.loadedModels.length === 1
                    && summarySection.data.effectiveContextLength > 0)
                return String(summarySection.data.effectiveContextLength)
            return summarySection.data.selectedNumCtx === null ? "auto"
                : String(summarySection.data.selectedNumCtx)
        }
    }
    OllamaDetailRow {
        root: summarySection.root
        k: "Keep Alive"
        v: summarySection.data.keepAliveStatus
    }

    UiText {
        width: parent.width
        visible: summarySection.data.operationInProgress
        text: summarySection.data.operationMessage
        color: summarySection.root.seal
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    UiText {
        width: parent.width
        visible: summarySection.data.busy
            && !summarySection.data.operationInProgress
        text: "Working on " + summarySection.data.pendingModel + "..."
        color: summarySection.root.seal
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }

    UiText {
        width: parent.width
        visible: summarySection.data.connected
            && !summarySection.data.operationInProgress
            && summarySection.data.loadedModels.length === 0
            && summarySection.data.models.length > 0
            && summarySection.data.displayError === ""
        text: "No model loaded"
        color: summarySection.root.sumiHi
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }

    UiText {
        width: parent.width
        visible: !summarySection.data.connected
        text: "Ollama is disconnected"
        color: summarySection.root.sumiHi
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }

    UiText {
        width: parent.width
        visible: summarySection.data.displayError !== ""
        text: summarySection.data.displayError
        color: summarySection.root.sealRaw
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    UiText {
        width: parent.width
        visible: summarySection.data.connected
            && summarySection.data.models.length === 0
            && summarySection.data.displayError === ""
        text: "No models installed"
        color: summarySection.root.sumiHi
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }
}
