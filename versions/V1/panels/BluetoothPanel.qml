import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../IconMap.js" as IconMap

PanelWindow {
    id: btPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-bluetooth"

    readonly property int barBottom: 35
    readonly property int gap: 8

    property bool btOn: false
    property bool scanning: false
    property var devices: []   // [{name, mac, connected, paired}]
    readonly property var shownDevices: devices.slice(0, 8)
    readonly property int numConnected: {
        var n = 0
        for (var i = 0; i < devices.length; i++) if (devices[i].connected) n++
        return n
    }
    property string connCmd: ""

    function refresh() { btData.running = false; btData.running = true }

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

            // ── header + power toggle ──
            Item {
                width: parent.width
                height: 24
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        color: root.ink; font.family: root.mono; font.pixelSize: 13
                        font.letterSpacing: 2; font.weight: Font.Medium
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: btPanel.btOn && btPanel.numConnected > 0
                        spacing: 3
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: IconMap.icon("bluetooth_connected")
                            color: root.seal
                            font.family: "Material Symbols Rounded"; font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(btPanel.numConnected)
                            color: root.seal
                            font.family: root.mono; font.pixelSize: 11
                        }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    // power toggle pill
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 20; radius: 10
                        color: btPanel.btOn ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.20)
                                            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                        border.color: btPanel.btOn ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            anchors.verticalCenter: parent.verticalCenter
                            x: btPanel.btOn ? parent.width - width - 3 : 3
                            color: btPanel.btOn ? root.seal : root.sumi
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { powerProc.running = false; powerProc.running = true }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"; color: root.sumi; font.pixelSize: 12
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.bluetoothVisible = false }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── off state ──
            Text {
                visible: !btPanel.btOn
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Bluetooth is off"
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
                font.family: root.mono; font.pixelSize: 11
                topPadding: 4; bottomPadding: 4
            }

            // ── scan control (only when on) ──
            Rectangle {
                visible: btPanel.btOn
                width: parent.width
                height: 28; radius: 4
                readonly property bool hovered: scanMa.containsMouse
                color: btPanel.scanning ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                       : hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
                       : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                border.color: (btPanel.scanning || hovered) ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: btPanel.scanning ? "Scanning…" : "Scan for devices"
                    color: btPanel.scanning ? root.seal : root.ink
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: scanMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !btPanel.scanning
                    onClicked: { scanProc.running = false; scanProc.running = true }
                }
            }

            // ── device list ──
            Column {
                width: parent.width
                spacing: 4
                visible: btPanel.btOn
                Repeater {
                    model: btPanel.shownDevices
                    delegate: Rectangle {
                        id: devTile
                        required property var modelData
                        readonly property bool hovered: devMa.containsMouse
                        width: col.width
                        height: 30; radius: 4
                        color: modelData.connected ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                               : hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
                               : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.color: modelData.connected ? root.seal
                                      : hovered ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - tag.width - 24
                            text: devTile.modelData.name
                            color: root.ink; font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Text {
                            id: tag
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: devTile.modelData.connected ? "Connected"
                                  : devTile.modelData.paired ? "Paired" : "Connect"
                            color: devTile.modelData.connected ? root.seal
                                   : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
                            font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 0.5
                        }
                        MouseArea {
                            id: devMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var m = devTile.modelData
                                if (m.connected) {
                                    btPanel.connCmd = "bluetoothctl disconnect " + m.mac
                                } else if (m.paired) {
                                    btPanel.connCmd = "bluetoothctl connect " + m.mac
                                } else {
                                    btPanel.connCmd = "bluetoothctl trust " + m.mac
                                        + " && bluetoothctl pair " + m.mac
                                        + " && bluetoothctl connect " + m.mac
                                }
                                connProc.running = false; connProc.running = true
                            }
                        }
                    }
                }
                Text {
                    visible: btPanel.btOn && btPanel.devices.length === 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: btPanel.scanning ? "Searching…" : "No devices — tap Scan"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                    font.family: root.mono; font.pixelSize: 11
                    topPadding: 2; bottomPadding: 2
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

    // ── data: power state + device list with connected/paired flags ──
    Process {
        id: btData
        command: ["bash", "-c",
            "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then " +
            "  echo ON; " +
            "  conn=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}'); " +
            "  paired=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'); " +
            "  bluetoothctl devices 2>/dev/null | while read -r _ mac rest; do " +
            "    c=0; p=0; " +
            "    printf '%s\\n' \"$conn\"   | grep -qx \"$mac\" && c=1; " +
            "    printf '%s\\n' \"$paired\" | grep -qx \"$mac\" && p=1; " +
            "    echo \"$c|$p|$mac|$rest\"; " +
            "  done; " +
            "else echo OFF; fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                if (lines[0] !== "ON") { btPanel.btOn = false; btPanel.devices = []; return }
                btPanel.btOn = true
                var devs = []
                for (var i = 1; i < lines.length; i++) {
                    var parts = lines[i].split("|")
                    if (parts.length < 4) continue
                    var name = parts.slice(3).join("|").trim()
                    if (!name || name === parts[2]) name = parts[2]   // fall back to mac
                    devs.push({
                        connected: parts[0] === "1",
                        paired:    parts[1] === "1",
                        mac:       parts[2],
                        name:      name
                    })
                }
                // connected first, then paired, then the rest
                devs.sort(function(a, b) {
                    var ra = a.connected ? 0 : a.paired ? 1 : 2
                    var rb = b.connected ? 0 : b.paired ? 1 : 2
                    return ra - rb
                })
                btPanel.devices = devs
            }
        }
    }

    // ── power on/off ──
    Process {
        id: powerProc
        command: ["bash", "-c", "bluetoothctl power " + (btPanel.btOn ? "off" : "on")]
        running: false
        onExited: btPanel.refresh()
    }

    // ── timed discovery scan ──
    Process {
        id: scanProc
        command: ["bash", "-c", "bluetoothctl --timeout 10 scan on >/dev/null 2>&1"]
        running: false
        onRunningChanged: { btPanel.scanning = running; if (!running) btPanel.refresh() }
    }
    Timer {
        interval: 1500; repeat: true
        running: btPanel.scanning && btPanel.visible
        onTriggered: btPanel.refresh()
    }

    // ── connect / disconnect / pair ──
    Process {
        id: connProc
        command: ["bash", "-c", btPanel.connCmd]
        running: false
        onExited: btPanel.refresh()
    }

    Process { id: btRunner; command: ["bash", "-c", "omarchy-launch-bluetooth"] }

    onVisibleChanged: { if (visible) btPanel.refresh() }
}
