import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: btPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-bluetooth"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property bool btOn: false
    property var devices: []   // [{name, mac}]

    property real reveal: root.bluetoothVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.bluetoothVisible ? 160 : 120
            easing.type: root.bluetoothVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.bluetoothVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.bluetoothVisible = false }

    Rectangle {
        id: card
        width: 300
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: parent.width - width - 6
        y: barBottom + gap
        opacity: btPanel.reveal
        focus: root.bluetoothVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.bluetoothVisible = false; event.accepted = true }
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
                    text: "Bluetooth"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: root.sumi; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bluetoothVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Row {
                width: parent.width
                Text { text: "Status"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                Text {
                    text: btPanel.btOn ? "On" : "Off"
                    color: btPanel.btOn ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
            }

            Text {
                text: "CONNECTED"
                color: root.sumi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                visible: btPanel.devices.length > 0
            }

            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: btPanel.devices
                    delegate: Rectangle {
                        required property var modelData
                        width: col.width
                        height: 28; radius: 4
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.color: root.sep; border.width: 1
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: root.ink; font.family: root.mono; font.pixelSize: 11
                            width: parent.width - 16; elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    visible: btPanel.btOn && btPanel.devices.length === 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "No devices connected"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                    font.family: root.mono; font.pixelSize: 11
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Rectangle {
                width: parent.width
                height: 28; radius: 4; color: root.seal
                Text { anchors.centerIn: parent; text: "Bluetooth settings"; color: root.paper; font.family: root.mono; font.pixelSize: 11 }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { root.bluetoothVisible = false; btRunner.running = false; btRunner.running = true }
                }
            }
        }
    }

    Process {
        id: btData
        command: ["bash", "-c",
            "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then " +
            "  echo 'ON'; " +
            "  bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [0-9A-F:]* //'; " +
            "else echo 'OFF'; fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                if (lines[0] === "ON") {
                    btPanel.btOn = true
                    var devs = []
                    for (var i = 1; i < lines.length; i++) {
                        var n = lines[i].trim()
                        if (n) devs.push({ name: n })
                    }
                    btPanel.devices = devs
                } else {
                    btPanel.btOn = false; btPanel.devices = []
                }
            }
        }
    }

    Process { id: btRunner; command: ["bash", "-c", "omarchy-launch-bluetooth"] }

    onVisibleChanged: { if (visible) { btData.running = false; btData.running = true } }
}
