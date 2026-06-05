import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property bool   hasBattery: false
    property int    percent:    0
    property string status:     "Unknown"

    readonly property bool charging: status === "Charging"
    readonly property bool full:     status === "Full"
    readonly property bool low:      !charging && !full && percent <= 20

    readonly property string tooltipText: status + " · " + percent + "%"

    implicitWidth:  hasBattery ? (row.implicitWidth + 18) : 0
    implicitHeight: 28
    visible: hasBattery
    clip: true

    Behavior on implicitWidth {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.centerIn: row
        width: row.width + 18
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    readonly property string battIcon:
        charging ? "\uE1A3"          // battery_charging_full
      : (low    ? "\uE19C"           // battery_alert
      :           "\uE1A4")          // battery_full

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BAT"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
            font.family: root.mono
            font.pixelSize: 10
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.battIcon
            color: (rootMod.charging || rootMod.full)
                ? root.indigo
                : (rootMod.low ? root.seal
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7))
            font.family: "Material Symbols Rounded"
            font.pixelSize: 15
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(rootMod.percent).padStart(3) + "%"
            color: {
                if (rootMod.charging || rootMod.full) return root.indigo
                if (rootMod.low) return root.seal
                return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            }
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // detect battery on startup
    Process {
        id: detectProc
        command: ["bash", "-c", "ls /sys/class/power_supply/ 2>/dev/null | grep -c '^BAT'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { rootMod.hasBattery = parseInt(this.text.trim()) > 0 }
        }
    }

    Process {
        id: batProc
        command: ["bash", "-c",
            "BAT=$(ls /sys/class/power_supply/ 2>/dev/null | grep -m1 '^BAT'); " +
            "[ -z \"$BAT\" ] && exit; " +
            "CAP=$(cat /sys/class/power_supply/$BAT/capacity 2>/dev/null || echo 0); " +
            "STA=$(cat /sys/class/power_supply/$BAT/status 2>/dev/null || echo Unknown); " +
            "echo \"$CAP $STA\""
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split(" ")
                if (parts.length >= 2) {
                    rootMod.percent = parseInt(parts[0]) || 0
                    rootMod.status  = parts[1] || "Unknown"
                }
            }
        }
    }

    Timer {
        interval: 30000; running: rootMod.hasBattery; repeat: true; triggeredOnStart: true
        onTriggered: { batProc.running = false; batProc.running = true }
    }

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: { if (rootMod.hasBattery) tipDelay.restart() }
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: { tipDelay.stop(); root.hideTooltip(rootMod); root.batteryVisible = !root.batteryVisible }
    }
}
