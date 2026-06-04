import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: profilePanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-power-profile"

    readonly property int barBottom: 37
    readonly property int gap: 8

    readonly property var profiles: [
        { key: "power-saver",  icon: "\uF06C",  label: "Power Saver" },
        { key: "balanced",     icon: "\uF24E", label: "Balanced" },
        { key: "performance",  icon: "\uF0E7", label: "Performance" },
    ]

    property real reveal: root.powerProfileVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.powerProfileVisible ? 160 : 120
            easing.type: root.powerProfileVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.powerProfileVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.powerProfileVisible = false
    }

    Rectangle {
        id: card
        width: 220
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: parent.width - width - 6
        y: barBottom + gap
        opacity: profilePanel.reveal
        focus: root.powerProfileVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.powerProfileVisible = false;
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            // ── header ──
            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Power Profile"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: root.sumi
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.powerProfileVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── profile buttons ──
            Repeater {
                model: profilePanel.profiles

                delegate: Item {
                    required property var modelData
                    required property int index

                    width: parent.width
                    height: 32

                    property bool isActive: root.powerProfileCurrent === modelData.key

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: isActive ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.2) : "transparent"
                        border.color: isActive ? root.seal : "transparent"
                        border.width: isActive ? 1 : 0
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: 8
                        anchors.right: parent.right; anchors.rightMargin: 8
                        spacing: 8

                        Text {
                            text: modelData.icon
                            color: isActive ? root.seal : root.ink
                            font.family: root.mono
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.label
                            color: isActive ? root.seal : root.ink
                            font.family: root.mono
                            font.pixelSize: 12
                            font.weight: isActive ? Font.Medium : Font.Normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            setProfileProc.command = ["bash", "-c", "powerprofilesctl set " + modelData.key]
                            setProfileProc.running = false
                            setProfileProc.running = true
                            root.powerProfileCurrent = modelData.key
                            root.powerProfileVisible = false
                        }
                    }
                }
            }
        }
    }

    Process {
        id: setProfileProc
        command: ["bash", "-c", "powerprofilesctl set balanced"]
        running: false
    }
}
