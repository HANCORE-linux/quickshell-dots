import QtQuick
import Quickshell
import Quickshell.Io
import "../IconMap.js" as IconMap

Item {
    id: rootMod
    required property var root

    property bool btOn:       false
    property bool connected:  false
    property int  numConnected: 0

    readonly property string iconN: !btOn
        ? "bluetooth_disabled"
        : (connected ? "bluetooth_connected" : "bluetooth")

    readonly property string tooltipText: connected
        ? "Bluetooth · " + numConnected + " connected"
        : (btOn ? "Bluetooth on" : "Bluetooth off")

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 28

    Rectangle {
        anchors.centerIn: row
        width: row.width + 18
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BT"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: IconMap.icon(rootMod.iconN)
            color: rootMod.connected
                ? root.seal
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, rootMod.btOn ? 0.7 : 0.3)
            font.family: "Material Symbols Rounded"
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.connected
            text: String(rootMod.numConnected)
            color: root.seal
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    Process {
        id: btProc
        command: ["bash", "-c",
            "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then " +
            "  COUNT=$(bluetoothctl devices Connected 2>/dev/null | wc -l); " +
            "  printf 'ON\\t%s\\n' \"$COUNT\"; " +
            "else echo OFF; fi"
        ]
        running: false
        stdout: SplitParser {
            onRead: function(line) { btProc.result = line.trim() }
        }
        onExited: {
            var r = btProc.result
            if (r === "OFF" || r === "") {
                rootMod.btOn = false; rootMod.connected = false; rootMod.numConnected = 0
            } else if (r.startsWith("ON\t")) {
                rootMod.btOn = true
                var count = parseInt(r.split("\t")[1]) || 0
                rootMod.numConnected = count
                rootMod.connected = count > 0
            }
            btProc.result = ""
        }
        property string result: ""
    }

    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { btProc.result = ""; btProc.running = false; btProc.running = true }
    }

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            if (!rootMod.tooltipText) return
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    Process { id: clickRunner; command: ["bash", "-c", "omarchy-launch-bluetooth"] }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tipDelay.restart()
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: (e) => {
            tipDelay.stop(); root.hideTooltip(rootMod)
            if (e.button === Qt.RightButton) { clickRunner.running = false; clickRunner.running = true }
            else root.bluetoothVisible = !root.bluetoothVisible
        }
    }
}
