import QtQuick

// Stateful on/off tile for the control panel toggle grids.
// The parent sets the width; styling follows the active / hover state.
Rectangle {
    id: tile
    required property var root
    property string label
    property bool active: false
    property color accent: root.seal
    signal toggled()

    readonly property bool hovered: ma.containsMouse

    height: 25
    radius: 4
    color: active  ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
         : hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
                   : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
    border.color: (active || hovered) ? accent : root.sep
    border.width: 1
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: tile.label
        color: (tile.active || tile.hovered) ? tile.accent : tile.root.ink
        font.family: tile.root.mono
        font.pixelSize: 11
        font.weight: tile.active ? Font.Medium : Font.Normal
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
    }
}
