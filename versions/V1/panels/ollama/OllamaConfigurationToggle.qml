import QtQuick 2.15

Rectangle {
    id: control

    required property var theme
    property bool controlEnabled: true
    property bool open: false
    property bool hovered: false

    signal clicked()

    height: 28
    radius: theme.tileRadius
    color: !controlEnabled ? theme.fillIdle
        : hovered ? theme.fillHover : theme.fillIdle
    border.color: !controlEnabled ? theme.sep
        : hovered ? theme.seal : theme.sep
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: headingGroup
        objectName: "configurationHeadingGroup"
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: headingLabel
            objectName: "configurationHeadingLabel"
            text: "Configuration"
            color: !control.controlEnabled ? control.theme.sumi
                : control.hovered ? control.theme.seal : control.theme.ink
            renderType: Text.NativeRendering
            font.family: control.theme.mono
            font.pixelSize: 11
        }

        Text {
            objectName: "configurationDisclosureIndicator"
            width: 12
            height: headingLabel.height
            text: control.open ? "\u25BE" : "\u25B8"
            color: !control.controlEnabled ? control.theme.sumi
                : control.hovered ? control.theme.seal : control.theme.ink
            renderType: Text.NativeRendering
            font.family: control.theme.mono
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    MouseArea {
        id: toggleMouseArea
        anchors.fill: parent
        enabled: control.controlEnabled
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: control.hovered = true
        onExited: control.hovered = false
        onEnabledChanged: if (!enabled) control.hovered = false
        onClicked: control.clicked()
    }
}
