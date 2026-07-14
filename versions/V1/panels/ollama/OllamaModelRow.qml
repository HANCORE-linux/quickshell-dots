import QtQuick
import "../../modules"
import "OllamaPanelLayout.js" as PanelLayout

Rectangle {
    id: modelRow

    required property var root
    required property var data
    required property var modelData
    property bool confirmationVisible: false

    signal confirmDeleteRequested(string name)
    signal clearDeleteRequested()
    signal deleteRequested(string name)
    signal loadRequested(string name)
    signal ejectRequested(string name)

    width: parent ? parent.width : 0
    height: confirmationVisible ? 86 : 58
    radius: root.tileRadius
    color: modelData.loaded ? root.fillActive : root.fillIdle
    border.color: modelData.loaded ? root.seal : root.sep
    border.width: 1

    function formatBytes(bytes) {
        var value = Number(bytes) || 0
        var gib = 1024 * 1024 * 1024
        var mib = 1024 * 1024
        if (value >= gib) return (value / gib).toFixed(1) + " GiB"
        return Math.round(value / mib) + " MiB"
    }

    UiText {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: modelDelete.left
        anchors.rightMargin: 8
        anchors.top: parent.top
        anchors.topMargin: 8
        text: modelRow.modelData.name
        color: modelRow.root.ink
        font.family: modelRow.root.mono
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
        text: modelRow.formatBytes(modelRow.modelData.size)
            + (modelRow.modelData.parameterSize
                ? "  \u00B7  " + modelRow.modelData.parameterSize : "")
            + (modelRow.modelData.quantization
                ? "  \u00B7  " + modelRow.modelData.quantization : "")
            + (modelRow.modelData.loaded ? "  \u00B7  LOADED" : "")
        color: modelRow.modelData.loaded ? modelRow.root.seal : modelRow.root.sumiHi
        font.family: modelRow.root.mono
        font.pixelSize: 9
        elide: Text.ElideRight
        visible: !modelRow.confirmationVisible
    }

    OllamaDeleteButton {
        id: modelDelete
        objectName: "modelDeleteControl"
        anchors.right: modelReload.visible ? modelReload.left : modelAction.left
        anchors.rightMargin: 8
        theme: modelRow.root
        controlEnabled: !modelRow.data.controlsLocked
        confirmationVisible: modelRow.confirmationVisible
        onEntered: modelDeleteTip.show()
        onExited: modelDeleteTip.hide()
        onControlEnabledChanged: if (!controlEnabled) modelDeleteTip.hide()
        onClicked: modelRow.confirmDeleteRequested(modelRow.modelData.name)
    }
    TooltipMixin {
        id: modelDeleteTip
        root: modelRow.root
        owner: modelDelete
        placement: "panel"
        text: "Delete model"
    }

    Rectangle {
        id: modelReload
        visible: modelRow.modelData.loaded
        anchors.right: modelAction.left
        anchors.rightMargin: 8
        y: PanelLayout.modelActionY(modelRow.confirmationVisible)
        width: 28
        height: 28
        radius: modelRow.root.tileRadius
        color: !modelReloadMa.enabled ? modelRow.root.fillIdle
            : modelReloadMa.containsMouse ? modelRow.root.fillPrimaryHover
            : modelRow.root.fillIdle
        border.color: modelReloadMa.containsMouse ? modelRow.root.seal : modelRow.root.sep
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        IconText {
            anchors.centerIn: parent
            text: "\uE5D5"
            color: !modelReloadMa.enabled ? modelRow.root.sumi
                : modelReloadMa.containsMouse ? modelRow.root.seal : modelRow.root.ink
            font.pixelSize: 13
        }
        TooltipMixin {
            id: modelReloadTip
            root: modelRow.root
            owner: modelReload
            placement: "panel"
            text: "Renew loaded model"
        }
        MouseArea {
            id: modelReloadMa
            anchors.fill: parent
            enabled: !modelRow.data.controlsLocked
            hoverEnabled: enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: modelReloadTip.show()
            onExited: modelReloadTip.hide()
            onEnabledChanged: if (!enabled) modelReloadTip.hide()
            onClicked: modelRow.loadRequested(modelRow.modelData.name)
        }
    }

    Rectangle {
        id: modelAction
        anchors.right: parent.right
        anchors.rightMargin: 8
        y: PanelLayout.modelActionY(modelRow.confirmationVisible)
        width: 50
        height: 28
        radius: modelRow.root.tileRadius
        color: !modelActionMa.enabled ? modelRow.root.fillIdle
            : modelActionMa.containsMouse ? modelRow.root.fillPrimaryHover
            : modelRow.modelData.loaded ? modelRow.root.fillHover : modelRow.root.seal
        border.color: modelRow.modelData.loaded ? modelRow.root.seal : "transparent"
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }

        UiText {
            anchors.centerIn: parent
            text: modelRow.data.operationInProgress
                    && modelRow.data.pendingModel === modelRow.modelData.name
                ? (modelRow.data.operationState === "loading" ? "Loading" : "Wait")
                : modelRow.modelData.loaded ? "Eject" : "Load"
            color: !modelActionMa.enabled ? modelRow.root.sumi
                : modelRow.modelData.loaded ? modelRow.root.seal : modelRow.root.paper
            font.family: modelRow.root.mono
            font.pixelSize: 10
        }

        MouseArea {
            id: modelActionMa
            anchors.fill: parent
            enabled: !modelRow.data.controlsLocked
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                modelRow.clearDeleteRequested()
                if (modelRow.modelData.loaded)
                    modelRow.ejectRequested(modelRow.modelData.name)
                else
                    modelRow.loadRequested(modelRow.modelData.name)
            }
        }
    }

    Rectangle {
        visible: modelRow.confirmationVisible
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 28
        radius: modelRow.root.tileRadius
        color: modelRow.root.fillIdle
        border.color: modelRow.root.seal
        border.width: 1

        UiText {
            id: deleteConfirmationText
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.right: deleteConfirmationActions.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: "Delete " + modelRow.modelData.name + "?"
            color: modelRow.root.ink
            font.family: modelRow.root.mono
            font.pixelSize: 10
            elide: Text.ElideRight
        }
        Row {
            id: deleteConfirmationActions
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                width: 46
                height: 22
                radius: modelRow.root.tileRadius
                color: cancelDeleteMa.containsMouse
                    ? modelRow.root.fillHover : modelRow.root.fillIdle
                UiText {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: modelRow.root.ink
                    font.family: modelRow.root.mono
                    font.pixelSize: 9
                }
                MouseArea {
                    id: cancelDeleteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelRow.clearDeleteRequested()
                }
            }
            Rectangle {
                width: 76
                height: 22
                radius: modelRow.root.tileRadius
                color: deleteModelMa.containsMouse
                    ? modelRow.root.sealRaw : modelRow.root.seal
                UiText {
                    anchors.centerIn: parent
                    text: "Delete model"
                    color: modelRow.root.paper
                    font.family: modelRow.root.mono
                    font.pixelSize: 9
                }
                MouseArea {
                    id: deleteModelMa
                    anchors.fill: parent
                    enabled: !modelRow.data.controlsLocked
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: modelRow.deleteRequested(modelRow.modelData.name)
                }
            }
        }
    }
}
