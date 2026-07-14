import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules"
import "ollama"

PanelWindow {
    id: ollamaPanel
    required property var root

    screen: root.activePopupScreen
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-ollama"

    readonly property int barBottom: 35
    readonly property int gap: 8

    function clearDeleteConfirmation() {
        modelsSection.clearDeleteConfirmation()
    }

    function setKeepAlive(value) {
        clearDeleteConfirmation()
        root.ollama.config.setKeepAlive(value)
    }

    function setContext(value) {
        clearDeleteConfirmation()
        root.ollama.config.setNumCtx(value)
    }

    Connections {
        target: root
        function onOllamaVisibleChanged() {
            if (!root.ollamaVisible) ollamaPanel.clearDeleteConfirmation()
        }
    }

    property real reveal: root.ollamaVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.ollamaVisible ? 160 : 120
            easing.type: root.ollamaVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.ollamaVisible
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.ollamaVisible = false
            ollamaPanel.clearDeleteConfirmation()
        }
    }

    Rectangle {
        id: card
        width: Math.min(380, parent.width - 12)
        height: Math.min(contentColumn.implicitHeight + 24,
                         parent.height - 2 * (barBottom + gap))
        radius: reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.ollamaBarX - width / 2,
                                          parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? parent.height - barBottom - gap - height : barBottom + gap
        opacity: ollamaPanel.reveal
        focus: root.ollamaVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (modelsSection.confirmDeleteModel !== "") {
                    ollamaPanel.clearDeleteConfirmation()
                } else {
                    root.ollamaVisible = false
                }
                event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: 12
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contentColumn
                width: scroller.width
                spacing: 8

                OllamaPanelHeader {
                    root: ollamaPanel.root
                    data: root.ollama
                    onRefreshRequested: {
                        ollamaPanel.clearDeleteConfirmation()
                        root.ollama.refreshAll()
                    }
                    onCloseRequested: {
                        root.ollamaVisible = false
                        ollamaPanel.clearDeleteConfirmation()
                    }
                }

                OllamaSummarySection {
                    root: ollamaPanel.root
                    data: root.ollama
                }

                OllamaModelsSection {
                    id: modelsSection
                    root: ollamaPanel.root
                    data: root.ollama.operations
                    onLoadRequested: function(name) {
                        root.ollama.operations.loadModel(name)
                    }
                    onEjectRequested: function(name) {
                        root.ollama.operations.ejectModel(name)
                    }
                    onDeleteRequested: function(name) {
                        root.ollama.operations.deleteModel(name)
                    }
                }

                OllamaPullSection {
                    root: ollamaPanel.root
                    data: root.ollama
                    onPullRequested: function(name) {
                        ollamaPanel.clearDeleteConfirmation()
                        root.ollama.pullModel(name)
                    }
                    onCancelRequested: {
                        ollamaPanel.clearDeleteConfirmation()
                        root.ollama.cancelPull()
                    }
                }

                OllamaConfigSection {
                    root: ollamaPanel.root
                    data: root.ollama.config
                    controlsLocked: root.ollama.controlsLocked
                    onKeepAliveRequested: function(value) {
                        ollamaPanel.setKeepAlive(value)
                    }
                    onContextRequested: function(value) {
                        ollamaPanel.setContext(value)
                    }
                    onOpenRuntimeConfigRequested: {
                        root.ollamaVisible = false
                        root.ollama.config.openEditor()
                    }
                    onApplyRequested: {
                        ollamaPanel.clearDeleteConfirmation()
                        root.ollama.operations.applyRuntimeConfiguration()
                    }
                    onRefreshRequested: {
                        ollamaPanel.clearDeleteConfirmation()
                        root.ollama.refreshAll()
                    }
                }
            }
        }
    }
}
