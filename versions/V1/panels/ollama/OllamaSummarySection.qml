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

    Rectangle {
        parent: summarySection
        width: parent.width
        height: 1
        color: summarySection.root.sep
    }

    OllamaDetailRow {
        parent: summarySection
        root: summarySection.root
        k: "GPU"
        v: summarySection.data.gpuPercent >= 0
            ? summarySection.data.gpuPercent + "%" : "N/A"
    }
    OllamaDetailRow {
        parent: summarySection
        root: summarySection.root
        k: "Ollama VRAM"
        v: summarySection.formatBytes(summarySection.data.loadedVramBytes)
    }
    OllamaDetailRow {
        parent: summarySection
        root: summarySection.root
        k: "Loaded models"
        v: String(summarySection.data.loadedModels.length)
    }
    OllamaDetailRow {
        parent: summarySection
        root: summarySection.root
        k: "Context"
        v: {
            if (summarySection.data.loadedModels.length === 1
                    && summarySection.data.effectiveContextLength > 0)
                return String(summarySection.data.effectiveContextLength)
            return summarySection.data.config.selectedNumCtx === null ? "auto"
                : String(summarySection.data.config.selectedNumCtx)
        }
    }
    OllamaDetailRow {
        parent: summarySection
        root: summarySection.root
        k: "Keep Alive"
        v: summarySection.data.keepAliveStatus
    }

    UiText {
        parent: summarySection
        width: parent.width
        visible: summarySection.data.operations.operationInProgress
        text: summarySection.data.operations.operationMessage
        color: summarySection.root.seal
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    UiText {
        parent: summarySection
        width: parent.width
        visible: summarySection.data.operations.busy
            && !summarySection.data.operations.operationInProgress
        text: "Working on " + summarySection.data.operations.pendingModel + "..."
        color: summarySection.root.seal
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }

    UiText {
        parent: summarySection
        width: parent.width
        visible: summarySection.data.connected
            && !summarySection.data.operations.operationInProgress
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
        parent: summarySection
        width: parent.width
        visible: !summarySection.data.connected
        text: "Ollama is disconnected"
        color: summarySection.root.sumiHi
        font.family: summarySection.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignHCenter
    }

    UiText {
        parent: summarySection
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
        parent: summarySection
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
