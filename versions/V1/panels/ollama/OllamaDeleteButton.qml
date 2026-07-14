import QtQuick 2.15
import "OllamaPanelLayout.js" as PanelLayout

Rectangle {
    id: control

    required property var theme
    property bool controlEnabled: true
    property bool confirmationVisible: false
    property bool hovered: false

    signal entered()
    signal exited()
    signal clicked()

    y: PanelLayout.modelActionY(confirmationVisible)
    width: 28
    height: 28
    radius: theme.tileRadius
    color: !controlEnabled ? theme.fillIdle
        : hovered ? theme.fillPrimaryHover : theme.fillIdle
    border.color: hovered && controlEnabled ? theme.seal : theme.sep
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        objectName: "modelDeleteGlyph"
        anchors.centerIn: parent
        width: 18
        height: 18
        text: "\uE872"
        color: !control.controlEnabled ? control.theme.sumi
            : control.hovered ? control.theme.paper : control.theme.ink
        renderType: Text.QtRendering
        font.family: "Material Symbols Rounded"
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: deleteMouseArea
        objectName: "ollamaModelDeleteMouseArea"
        anchors.fill: parent
        enabled: control.controlEnabled
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: {
            control.hovered = true
            control.entered()
        }
        onExited: {
            control.hovered = false
            control.exited()
        }
        onEnabledChanged: if (!enabled) control.hovered = false
        onClicked: control.clicked()
    }
}
