import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    visible: implicitWidth > 0.5
    implicitWidth: root.modMemory ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    clip: true
    opacity: root.modMemory ? 1 : 0

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    property int percent: 0
    property real usedGiB: 0.0
    property real totalGiB: 0.0
    readonly property string tooltipText: usedGiB.toFixed(1) + "/" + totalGiB.toFixed(0) + " GB"

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
            text: "MEM"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        Canvas {
            id: ring
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter

            property color tint: root.seal
            onTintChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cx = width / 2
                var cy = height / 2
                var r = (width / 2) - 1.5
                var ratio = rootMod.totalGiB > 0 ? rootMod.usedGiB / rootMod.totalGiB : 0
                var start = -Math.PI / 2
                var end = start + (2 * Math.PI * ratio)

                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                ctx.strokeStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.18)
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                ctx.stroke()

                if (ratio > 0) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, start, end)
                    ctx.strokeStyle = tint
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
            }

            Component.onCompleted: requestPaint()
            Connections {
                target: rootMod
                function onUsedGiBChanged() { ring.requestPaint() }
            }
        }

        Row {
            spacing: 0
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: String(Math.round(rootMod.usedGiB)).padStart(2, '0') + "G"
                color: root.seal
                font.family: root.mono
                font.pixelSize: 12
            }
        }
    }

    Process {
        id: memProc
        command: ["bash", "-c", "awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} END{printf \"%.0f %.0f\\n\", t, a}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split(/\s+/)
                if (parts.length < 2) return
                var totalKB = parseFloat(parts[0])
                var availKB = parseFloat(parts[1])
                if (isNaN(totalKB) || isNaN(availKB) || totalKB <= 0) return
                var usedKB = Math.max(0, totalKB - availKB)
                rootMod.totalGiB = totalKB / (1024 * 1024)
                rootMod.usedGiB  = usedKB  / (1024 * 1024)
                rootMod.percent  = Math.max(0, Math.min(100, Math.round(usedKB / totalKB * 100)))
            }
        }
    }

    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { memProc.running = false; memProc.running = true }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: { tip.hide() }
        onClicked: { tip.hide(); root.memVisible = !root.memVisible }
    }
}
