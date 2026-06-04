import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: wsPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-workspace"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property real reveal: root.workspaceVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.workspaceVisible ? 160 : 120
            easing.type: root.workspaceVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.workspaceVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.workspaceVisible = false }

    Rectangle {
        id: card
        width: 240
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: 6
        y: barBottom + gap
        opacity: wsPanel.reveal
        focus: root.workspaceVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.workspaceVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Workspaces"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: root.sumi; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.workspaceVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: Hyprland.workspaces

                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id
                        width: col.width
                        height: 30; radius: 4
                        color: isActive ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                                        : (ma.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06) : "transparent")
                        border.color: isActive ? root.seal : "transparent"
                        border.width: isActive ? 1 : 0

                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Workspace " + modelData.id
                            color: isActive ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 12
                            font.weight: isActive ? Font.Medium : Font.Normal
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.toplevels && modelData.toplevels.values ? modelData.toplevels.values.length : ""
                            color: root.sumi; font.family: root.mono; font.pixelSize: 10
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Hyprland.dispatch("workspace " + modelData.id)
                                root.workspaceVisible = false
                            }
                        }
                    }
                }
            }
        }
    }
}
