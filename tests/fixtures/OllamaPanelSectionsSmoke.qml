import QtQuick
import QtQuick.Window
import Quickshell
import "modules"
import "panels/ollama"

ShellRoot {
    id: testRoot

    property var failures: []
    property var modelRow: null
    property int loadSignals: 0
    property int ejectSignals: 0
    property int deleteSignals: 0
    property bool finished: false

    function check(condition, message) {
        if (!condition) failures.push(message)
    }

    function findModelRow(section) {
        for (var i = 0; i < section.children.length; i++) {
            var child = section.children[i]
            if (child.hasOwnProperty("confirmationVisible")
                    && typeof child.confirmDeleteRequested === "function")
                return child
        }
        return null
    }

    function findObject(parent, name) {
        if (parent.objectName === name) return parent
        if (!parent.children) return null
        for (var i = 0; i < parent.children.length; i++) {
            var match = findObject(parent.children[i], name)
            if (match !== null) return match
        }
        return null
    }

    function activateMouseArea(name) {
        var mouseArea = findObject(modelRow, name)
        check(mouseArea !== null, "missing production control " + name)
        if (mouseArea !== null) mouseArea.clicked(null)
    }

    function checkConfirmedState() {
        modelsSection.forceLayout()
        sectionColumn.forceLayout()
        check(modelsSection.implicitHeight === 95, "confirmed section implicit height "
              + modelsSection.implicitHeight)
        check(sectionColumn.implicitHeight === 427, "confirmed section column height")
        check(sectionColumn.implicitHeight + 24 === 451, "confirmed card content height")

        modelsSection.clearDeleteConfirmation()
        check(modelsSection.confirmDeleteModel === "", "clear API state")
        check(!modelRow.confirmationVisible && modelRow.height === 58,
              "clear API row state")

        activateMouseArea("ollamaModelDeleteMouseArea")
        activateMouseArea("ollamaModelCancelDeleteMouseArea")
        check(modelsSection.confirmDeleteModel === "", "cancel signal forwarded")

        activateMouseArea("ollamaModelDeleteMouseArea")
        activateMouseArea("ollamaModelConfirmDeleteMouseArea")
        check(deleteSignals === 1, "delete signal forwarded")
        check(modelsSection.confirmDeleteModel === "", "delete clears confirmation")

        activateMouseArea("ollamaModelReloadMouseArea")
        activateMouseArea("ollamaModelDeleteMouseArea")
        activateMouseArea("ollamaModelActionMouseArea")
        check(loadSignals === 1, "load action signal forwarded")
        check(ejectSignals === 1, "eject action signal forwarded")
        check(modelsSection.confirmDeleteModel === "", "model action clears confirmation")
        check(fakeData.loadCalls === 0 && fakeData.ejectCalls === 0
              && fakeData.deleteCalls === 0, "row or section mutated fake data")

        activateMouseArea("ollamaModelDeleteMouseArea")
        shortTimeoutCheck.start()
    }

    function finish() {
        if (finished) return
        finished = true
        if (failures.length > 0)
            console.error("OLLAMA_PANEL_SECTIONS_NATIVE_FAIL: " + failures.join(", "))
        else
            console.log("OLLAMA_PANEL_SECTIONS_NATIVE_PASS")
        Qt.callLater(Qt.quit)
    }

    QtObject {
        id: theme

        property color paper: "#181616"
        property color ink: "#c5c9c5"
        property color sumi: "#8a8a82"
        property color sumiHi: "#aaaaaa"
        property color seal: "#c4746e"
        property color sealRaw: "#ff0000"
        property color sep: "#555555"
        property color fillHover: "#393939"
        property color fillIdle: "#222222"
        property color fillActive: "#302727"
        property color fillPrimaryHover: "#dc817a"
        property int tileRadius: 6
        property string mono: "monospace"
        property var tooltipOwner: null
        property string tooltipText: ""

        function hideTooltip(owner) {}
        function showTooltip(text, x, y, owner, placement, width, height) {}
    }

    QtObject {
        id: fakeOperations

        property bool operationInProgress: false
        property string operationMessage: ""
        property bool busy: false
        property string pendingModel: ""
    }

    QtObject {
        id: fakeConfig

        property var selectedNumCtx: null
    }

    QtObject {
        id: fakeData

        property var models: [{
            name: "qwen3:8b",
            size: 8589934592,
            parameterSize: "8B",
            quantization: "Q4_K_M",
            loaded: true
        }]
        property bool controlsLocked: false
        property bool operationInProgress: false
        property string pendingModel: ""
        property string operationState: "idle"
        property bool connected: true
        property string version: "0.11.0"
        property bool refreshRunning: false
        property int gpuPercent: 42
        property double loadedVramBytes: 4294967296
        property var loadedModels: [{ name: "qwen3:8b" }]
        property int effectiveContextLength: 8192
        property var selectedNumCtx: null
        property string keepAliveStatus: "5m"
        property string operationMessage: ""
        property bool busy: false
        property string displayError: ""
        property var operations: fakeOperations
        property var config: fakeConfig
        property bool pullBusy: false
        property string pullStatus: ""
        property string pullProgressText: ""
        property real pullProgress: 0
        property bool pullCanCancel: false
        property string pullResultText: ""
        property string pullState: "idle"
        property string selectedKeepAlive: "5m"
        property bool configDirty: false
        property bool dirty: false
        property int loadCalls: 0
        property int ejectCalls: 0
        property int deleteCalls: 0

        function loadModel(name) { loadCalls += 1 }
        function ejectModel(name) { ejectCalls += 1 }
        function deleteModel(name) { deleteCalls += 1 }
        function parseContextInput(value) { return Number(value) }
    }

    Window {
        width: 380
        height: 800
        visible: false

        Column {
            id: sectionColumn
            width: 356
            spacing: 8

            OllamaPanelHeader {
                id: panelHeader
                root: theme
                data: fakeData
            }

            OllamaSummarySection {
                id: summarySection
                root: theme
                data: fakeData
            }

            OllamaModelsSection {
                id: modelsSection
                root: theme
                data: fakeData

                onLoadRequested: function(name) {
                    testRoot.loadSignals += 1
                    testRoot.check(name === "qwen3:8b", "load signal model")
                }
                onEjectRequested: function(name) {
                    testRoot.ejectSignals += 1
                    testRoot.check(name === "qwen3:8b", "eject signal model")
                }
                onDeleteRequested: function(name) {
                    testRoot.deleteSignals += 1
                    testRoot.check(name === "qwen3:8b", "delete signal model")
                }
            }

            OllamaPullSection {
                id: pullSection
                root: theme
                data: fakeData
            }

            OllamaConfigSection {
                id: configSection
                root: theme
                data: fakeData
                controlsLocked: fakeData.controlsLocked
            }
        }
    }

    Timer {
        id: shortTimeoutCheck
        interval: 150
        running: false
        onTriggered: {
            testRoot.check(modelsSection.confirmDeleteModel === "", "short timeout clears state")
            testRoot.check(testRoot.modelRow.height === 58, "short timeout restores row height")
            testRoot.check(fakeData.loadCalls === 0, "section called data.loadModel directly")
            testRoot.check(fakeData.ejectCalls === 0, "section called data.ejectModel directly")
            testRoot.check(fakeData.deleteCalls === 0, "section called data.deleteModel directly")
            testRoot.finish()
        }
    }

    Timer {
        interval: 2000
        running: !testRoot.finished
        onTriggered: {
            testRoot.failures.push("native smoke timed out")
            testRoot.finish()
        }
    }

    Component.onCompleted: Qt.callLater(function() {
        modelRow = findModelRow(modelsSection)
        check(modelsSection.confirmationTimeoutMs === 8000,
              "default confirmation timeout")
        modelsSection.confirmationTimeoutMs = 50
        sectionColumn.forceLayout()
        check(panelHeader.y < summarySection.y
              && summarySection.y < modelsSection.y
              && modelsSection.y < pullSection.y
              && pullSection.y < configSection.y, "production section order")
        check(panelHeader.width === 356 && panelHeader.height === 24,
              "header dimensions")
        check(summarySection.width === 356 && summarySection.height === 116
              && summarySection.implicitHeight === 116,
              "summary dimensions")
        check(modelsSection.width === 356 && modelsSection.height === 67
              && modelsSection.implicitHeight === 67,
              "models dimensions")
        check(pullSection.width === 356 && pullSection.height === 87
              && pullSection.implicitHeight === 87,
              "pull dimensions")
        check(configSection.width === 356 && configSection.height === 73
              && configSection.implicitHeight === 73,
              "config dimensions")
        check(sectionColumn.width === 356 && sectionColumn.height === 399
              && sectionColumn.implicitHeight === 399,
              "section column dimensions")
        check(sectionColumn.width + 24 === 380
              && sectionColumn.implicitHeight + 24 === 423,
              "card content dimensions")
        check(modelRow !== null, "production model row delegate")
        if (modelRow === null) {
            finish()
            return
        }

        check(modelRow.height === 58, "initial row height")
        check(modelsSection.implicitHeight === 67, "initial section implicit height")

        activateMouseArea("ollamaModelDeleteMouseArea")
        check(modelsSection.confirmDeleteModel === "qwen3:8b",
              "confirmation signal forwarded")
        check(modelRow.confirmationVisible, "row confirmation state")
        check(modelRow.height === 86, "confirmed row height")
        Qt.callLater(testRoot.checkConfirmedState)
    })
}
