import Quickshell.Hyprland
import QtQuick

Item {
    id: wsWidget
    required property var root

    implicitWidth: wsRow.implicitWidth
    implicitHeight: 28

    Rectangle {
        anchors.centerIn: wsRow
        width: wsRow.width + 8
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    // right-click anywhere opens the workspace panel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.workspaceVisible = !root.workspaceVisible
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: 10

            delegate: Item {
                required property int modelData
                readonly property int wsId: modelData + 1

                readonly property bool isFocused: Hyprland.focusedWorkspace !== null
                                               && Hyprland.focusedWorkspace.id === wsId

                readonly property bool isOccupied: {
                    var ws = Hyprland.workspaces.values
                    for (var i = 0; i < ws.length; i++)
                        if (ws[i].id === wsId) return !isFocused
                    return false
                }

                readonly property bool isEmpty: !isFocused && !isOccupied

                implicitWidth: isFocused ? 32 : 16
                implicitHeight: 28

                Behavior on implicitWidth {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // glow — alle states, nur opacity variiert
                Rectangle {
                    anchors.centerIn: parent
                    width:  isFocused ? 34 : 16
                    height: isFocused ? 16 : 16
                    radius: isFocused ?  8 :  8
                    color: isFocused
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.20)
                        : isOccupied
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                        : Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.06)

                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // pill / kreis
                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    width:  isFocused  ? 26 : 8
                    height: 8
                    radius: 4
                    color:  isFocused
                        ? root.seal
                        : isOccupied
                        ? root.seal
                        : Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.25)

                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: Hyprland.dispatch("workspace " + wsId)
                    onEntered: dot.scale = 1.2
                    onExited:  dot.scale = 1.0
                }
            }
        }
    }
}
