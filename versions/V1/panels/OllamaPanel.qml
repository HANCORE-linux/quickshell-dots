import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules"

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
    property string confirmDeleteModel: ""

    function formatBytes(bytes) {
        var value = Number(bytes) || 0
        var gib = 1024 * 1024 * 1024
        var mib = 1024 * 1024
        if (value >= gib) return (value / gib).toFixed(1) + " GiB"
        return Math.round(value / mib) + " MiB"
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
            ollamaPanel.confirmDeleteModel = ""
        }
    }

    component DetailRow: Row {
        property string k: ""
        property string v: ""
        width: parent ? parent.width : 0

        UiText {
            width: parent.width * 0.45
            text: k
            color: ollamaPanel.root.sumiHi
            font.family: ollamaPanel.root.mono
            font.pixelSize: 11
        }
        UiText {
            width: parent.width * 0.55
            text: v
            color: ollamaPanel.root.ink
            font.family: ollamaPanel.root.mono
            font.pixelSize: 11
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
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
                if (ollamaPanel.confirmDeleteModel !== "") {
                    ollamaPanel.confirmDeleteModel = ""
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

                Item {
                    width: parent.width
                    height: 24

                    UiText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "OLLAMA"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 13
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                    }

                    UiText {
                        anchors.right: refreshButton.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.ollama.connected && root.ollama.version !== ""
                            ? "v" + root.ollama.version : "OFFLINE"
                        color: root.ollama.connected && root.ollama.version !== "" ? root.seal : root.sumi
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }

                    Item {
                        id: refreshButton
                        anchors.right: closeButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24
                        opacity: refreshMa.enabled ? 1 : 0.35

                        IconText {
                            anchors.centerIn: parent
                            text: "\uE5D5"
                            color: refreshMa.containsMouse ? root.seal : root.sumi
                            font.pixelSize: 14
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: refreshMa
                            anchors.fill: parent
                            enabled: !root.ollama.refreshRunning && !root.ollama.controlsLocked
                            hoverEnabled: enabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.ollama.refreshAll()
                        }
                    }

                    Item {
                        id: closeButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24

                        UiText {
                            anchors.centerIn: parent
                            text: "\u2715"
                            color: closeMa.containsMouse ? root.seal : root.sumi
                            font.pixelSize: 12
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.ollamaVisible = false
                                ollamaPanel.confirmDeleteModel = ""
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                DetailRow {
                    k: "GPU"
                    v: root.ollama.gpuPercent >= 0 ? root.ollama.gpuPercent + "%" : "N/A"
                }
                DetailRow {
                    k: "Ollama VRAM"
                    v: ollamaPanel.formatBytes(root.ollama.loadedVramBytes)
                }
                DetailRow {
                    k: "Loaded models"
                    v: String(root.ollama.loadedModels.length)
                }

                DetailRow {
                    k: "Context"
                    v: root.ollama.loadedModels.length === 1
                        ? String(root.ollama.effectiveContextLength)
                        : (root.ollama.selectedNumCtx === null ? "auto" : String(root.ollama.selectedNumCtx))
                }

                Row {
                    width: parent.width
                    height: 24
                    spacing: 6

                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        text: "Keep Alive"
                        color: root.sumiHi
                        font.family: root.mono
                        font.pixelSize: 11
                    }

                    Repeater {
                        model: [
                            { label: "5m", value: "5m" },
                            { label: "30m", value: "30m" },
                            { label: "∞", value: -1 }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 36
                            height: 22
                            radius: root.tileRadius
                            color: root.ollama.selectedKeepAlive === modelData.value ? root.seal : root.fillIdle
                            border.color: root.sep
                            border.width: 1

                            UiText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: root.ollama.selectedKeepAlive === modelData.value ? root.paper : root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.ollama.controlsLocked
                                onClicked: root.ollama.setKeepAlive(modelData.value)
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 28
                    spacing: 6

                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        text: "Context"
                        color: root.sumiHi
                        font.family: root.mono
                        font.pixelSize: 11
                    }

                    Repeater {
                        model: [
                            { label: "auto", value: null },
                            { label: "8k", value: 8192 },
                            { label: "16k", value: 16384 },
                            { label: "32k", value: 32768 },
                            { label: "Custom", value: "custom" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            property bool isCustom: modelData.value === "custom"
                            property bool selected: isCustom
                                ? root.ollama.selectedNumCtx !== null && ![8192,16384,32768].includes(root.ollama.selectedNumCtx)
                                : root.ollama.selectedNumCtx === modelData.value
                            width: isCustom ? Math.max(52, customInput.contentWidth + 20) : 40
                            height: 22
                            radius: root.tileRadius
                            color: selected ? root.seal : root.fillIdle
                            border.color: root.sep
                            border.width: 1

                            UiText {
                                visible: !isCustom
                                anchors.centerIn: parent
                                text: modelData.label
                                color: selected ? root.paper : root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                            }

                            TextInput {
                                id: customInput
                                visible: isCustom
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                font.family: root.mono
                                font.pixelSize: 10
                                enabled: !root.ollama.controlsLocked && isCustom
                                color: enabled ? root.ink : root.sumi
                                clip: true
                                selectByMouse: true
                                text: isCustom && selected ? String(root.ollama.selectedNumCtx) : ""
                                onEditingFinished: {
                                    var raw = String(text).trim().toUpperCase()
                                    var multiplier = 1
                                    if (raw.endsWith("K")) {
                                        multiplier = 1000
                                        raw = raw.slice(0, -1)
                                    }
                                    var n = parseInt(raw)
                                    if (!isNaN(n) && n > 0) root.ollama.setNumCtx(n * multiplier)
                                }
                            }

                            UiText {
                                visible: isCustom && (!selected || customInput.text === "")
                                    && !customInput.activeFocus
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                text: "Custom"
                                color: selected ? root.paper : root.ink
                                font.family: root.mono
                                font.pixelSize: 10
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.ollama.controlsLocked
                                onClicked: {
                                    if (isCustom) customInput.forceActiveFocus()
                                    else root.ollama.setNumCtx(modelData.value)
                                }
                            }
                        }
                    }
                }

                UiText {
                    width: parent.width
                    visible: root.ollama.configDirty
                    text: "Configuration pending — press Apply to reload model"
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                UiText {
                    width: parent.width
                    visible: root.ollama.operationInProgress
                    text: root.ollama.operationMessage
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                UiText {
                    width: parent.width
                    visible: root.ollama.busy && !root.ollama.operationInProgress
                    text: "Working on " + root.ollama.pendingModel + "..."
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }

                UiText {
                    width: parent.width
                    visible: root.ollama.connected
                        && !root.ollama.operationInProgress
                        && root.ollama.loadedModels.length === 0
                        && root.ollama.models.length > 0
                        && root.ollama.displayError === ""
                    text: "No model loaded"
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }

                UiText {
                    width: parent.width
                    visible: !root.ollama.connected
                    text: "Ollama is disconnected"
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }

                UiText {
                    width: parent.width
                    visible: root.ollama.displayError !== ""
                    text: root.ollama.displayError
                    color: root.sealRaw
                    font.family: root.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                UiText {
                    width: parent.width
                    visible: root.ollama.connected
                        && root.ollama.models.length === 0
                        && root.ollama.displayError === ""
                    text: "No models installed"
                    color: root.sumiHi
                    font.family: root.mono
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: root.ollama.models

                    delegate: Rectangle {
                        required property var modelData
                        width: contentColumn.width
                        height: 58
                        radius: root.tileRadius
                        color: modelData.loaded ? root.fillActive : root.fillIdle
                        border.color: modelData.loaded ? root.seal : root.sep
                        border.width: 1

                        UiText {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: modelDelete.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            text: modelData.name
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        UiText {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: modelDelete.left
                            anchors.rightMargin: 8
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: ollamaPanel.formatBytes(modelData.size)
                                + (modelData.parameterSize ? "  \u00B7  " + modelData.parameterSize : "")
                                + (modelData.quantization ? "  \u00B7  " + modelData.quantization : "")
                                + (modelData.loaded ? "  \u00B7  LOADED" : "")
                            color: modelData.loaded ? root.seal : root.sumiHi
                            font.family: root.mono
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: modelDelete
                            anchors.right: modelReload.visible ? modelReload.left : modelAction.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: root.tileRadius
                            color: !delMa.enabled ? root.fillIdle
                                : ollamaPanel.confirmDeleteModel === modelData.name ? root.seal
                                : delMa.containsMouse ? root.fillPrimaryHover : root.fillIdle
                            border.color: ollamaPanel.confirmDeleteModel === modelData.name
                                ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            IconText {
                                anchors.centerIn: parent
                                text: "\uE872"
                                color: !delMa.enabled ? root.sumi
                                    : ollamaPanel.confirmDeleteModel === modelData.name ? root.paper
                                    : delMa.containsMouse ? root.seal : root.sumi
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                enabled: !root.ollama.controlsLocked
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (ollamaPanel.confirmDeleteModel === modelData.name) {
                                        ollamaPanel.confirmDeleteModel = ""
                                        root.ollama.deleteModel(modelData.name)
                                    } else {
                                        ollamaPanel.confirmDeleteModel = modelData.name
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: modelReload
                            visible: modelData.loaded
                            anchors.right: modelAction.left
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            radius: root.tileRadius
                            color: !modelReloadMa.enabled ? root.fillIdle
                                : modelReloadMa.containsMouse ? root.fillPrimaryHover : root.fillIdle
                            border.color: modelReloadMa.containsMouse ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            IconText {
                                anchors.centerIn: parent
                                text: "\uE5D5"
                                color: !modelReloadMa.enabled ? root.sumi
                                    : modelReloadMa.containsMouse ? root.seal : root.ink
                                font.pixelSize: 13
                            }
                            TooltipMixin {
                                id: modelReloadTip
                                root: ollamaPanel.root
                                owner: modelReload
                                text: "Renew loaded model"
                            }
                            MouseArea {
                                id: modelReloadMa
                                anchors.fill: parent
                                enabled: !root.ollama.controlsLocked
                                hoverEnabled: enabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onEntered: modelReloadTip.show()
                                onExited: modelReloadTip.hide()
                                onClicked: root.ollama.loadModel(modelData.name)
                            }
                        }

                        Rectangle {
                            id: modelAction
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 50
                            height: 28
                            radius: root.tileRadius
                            color: !modelActionMa.enabled ? root.fillIdle
                                : modelActionMa.containsMouse ? root.fillPrimaryHover
                                : modelData.loaded ? root.fillHover : root.seal
                            border.color: modelData.loaded ? root.seal : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            UiText {
                                anchors.centerIn: parent
                                text: root.ollama.operationInProgress && root.ollama.pendingModel === modelData.name
                                    ? (root.ollama.operationState === "loading" ? "Loading" : "Wait")
                                    : modelData.loaded ? "Eject" : "Load"
                                color: !modelActionMa.enabled ? root.sumi
                                    : modelData.loaded ? root.seal : root.paper
                                font.family: root.mono
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: modelActionMa
                                anchors.fill: parent
                                enabled: !root.ollama.controlsLocked
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (modelData.loaded) root.ollama.ejectModel(modelData.name)
                                    else root.ollama.loadModel(modelData.name)
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                Column {
                    width: parent.width
                    spacing: 6

                    Row {
                        width: parent.width
                        height: 32
                        spacing: 6
                        visible: !root.ollama.pullBusy

                        Rectangle {
                            width: parent.width - pullButton.width - parent.spacing
                            height: 32
                            radius: root.tileRadius
                            color: root.fillIdle
                            border.color: root.sep
                            border.width: 1

                            TextInput {
                                id: pullInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: Text.AlignVCenter
                                font.family: root.mono
                                font.pixelSize: 11
                                color: root.ink
                                clip: true
                                selectByMouse: true
                            }

                            UiText {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                text: "Model name or URL..."
                                color: root.sumiHi
                                font.family: root.mono
                                font.pixelSize: 11
                                visible: !pullInput.text && !pullInput.activeFocus
                            }
                        }

                        Rectangle {
                            id: pullButton
                            width: 64
                            height: 32
                            radius: root.tileRadius
                            color: !pullMa.enabled ? root.fillIdle
                                : pullMa.containsMouse ? root.fillPrimaryHover : root.seal
                            border.color: !pullMa.enabled ? root.sep : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            UiText {
                                anchors.centerIn: parent
                                text: "Pull"
                                color: !pullMa.enabled ? root.sumi : root.paper
                                font.family: root.mono
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: pullMa
                                anchors.fill: parent
                                enabled: !root.ollama.controlsLocked
                                    && String(pullInput.text).trim() !== ""
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    root.ollama.pullModel(pullInput.text)
                                    pullInput.text = ""
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 4
                        visible: root.ollama.pullBusy

                        UiText {
                            width: parent.width
                            text: root.ollama.pullStatus || "Starting..."
                            color: root.seal
                            font.family: root.mono
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: root.fillIdle
                            border.color: root.sep
                            border.width: 1

                            Rectangle {
                                width: Math.min(parent.width - 2,
                                    Math.max(6, (parent.width - 2) * root.ollama.pullProgress))
                                height: parent.height - 2
                                anchors.left: parent.left
                                anchors.leftMargin: 1
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 2
                                color: root.seal
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    UiText {
                        width: parent.width
                        visible: root.ollama.pullError !== ""
                        text: root.ollama.pullError
                        color: root.sealRaw
                        font.family: root.mono
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                Row {
                    width: parent.width
                    height: 28
                    spacing: 8

                    Rectangle {
                        width: parent.width - refreshTile.width - parent.spacing
                        height: parent.height
                        radius: root.tileRadius
                        color: applyMa.enabled
                            ? (applyMa.containsMouse ? root.fillPrimaryHover : root.seal)
                            : root.fillIdle
                        Behavior on color { ColorAnimation { duration: 120 } }

                        UiText {
                            anchors.centerIn: parent
                            text: "Apply configuration"
                            color: applyMa.enabled ? root.paper : root.sumi
                            font.family: root.mono
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: applyMa
                            anchors.fill: parent
                            enabled: !root.ollama.controlsLocked && root.ollama.configDirty
                            hoverEnabled: enabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.ollama.applyRuntimeConfiguration()
                        }
                    }

                    Rectangle {
                        id: refreshTile
                        width: 28
                        height: 28
                        radius: root.tileRadius
                        color: refreshBottomMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: refreshBottomMa.containsMouse ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        IconText {
                            anchors.centerIn: parent
                            text: "\uE5D5"
                            color: refreshBottomMa.containsMouse ? root.seal : root.ink
                            font.pixelSize: 14
                        }
                        TooltipMixin {
                            id: refreshBottomTip
                            root: ollamaPanel.root
                            owner: refreshTile
                            text: "Refresh Ollama state"
                        }
                        MouseArea {
                            id: refreshBottomMa
                            anchors.fill: parent
                            enabled: !root.ollama.controlsLocked
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onEntered: refreshBottomTip.show()
                            onExited: refreshBottomTip.hide()
                            onClicked: {
                                refreshBottomTip.hide()
                                root.ollama.refreshAll()
                            }
                        }
                    }
                }
            }
        }
    }
}
