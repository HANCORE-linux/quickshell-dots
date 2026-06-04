import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 28

    property int percent: 0
    property var history: []
    readonly property int maxSamples: 30
    readonly property string tooltipText: percent + "%"

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
            text: "CPU"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        Canvas {
            id: wave
            width: 36
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var h = rootMod.history
                if (h.length < 2) return

                var minV = h[0], maxV = h[0]
                for (var n = 1; n < h.length; n++) {
                    if (h[n] < minV) minV = h[n]
                    if (h[n] > maxV) maxV = h[n]
                }
                var range = maxV - minV
                if (range < 0.04) { minV = Math.max(0, minV - 0.02); maxV = Math.min(1, maxV + 0.02); range = maxV - minV }
                var pad = range * 0.2
                minV = Math.max(0, minV - pad)
                maxV = Math.min(1, maxV + pad)
                range = maxV - minV

                var pts = []
                for (var i = 0; i < h.length; i++) {
                    var x = (i / (maxSamples - 1)) * width
                    var y = height - ((h[i] - minV) / range) * height
                    pts.push({ x: x, y: y })
                }

                // fill
                ctx.beginPath()
                ctx.moveTo(pts[0].x, height)
                ctx.lineTo(pts[0].x, pts[0].y)
                for (var j = 1; j < pts.length; j++) {
                    var cx = (pts[j-1].x + pts[j].x) / 2
                    ctx.bezierCurveTo(cx, pts[j-1].y, cx, pts[j].y, pts[j].x, pts[j].y)
                }
                ctx.lineTo(pts[pts.length-1].x, height)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.12)
                ctx.fill()

                // stroke
                ctx.beginPath()
                ctx.moveTo(pts[0].x, pts[0].y)
                for (var k = 1; k < pts.length; k++) {
                    var mx = (pts[k-1].x + pts[k].x) / 2
                    ctx.bezierCurveTo(mx, pts[k-1].y, mx, pts[k].y, pts[k].x, pts[k].y)
                }
                ctx.strokeStyle = root.seal.toString()
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.stroke()
            }

            Component.onCompleted: requestPaint()
            Connections {
                target: rootMod
                function onHistoryChanged() { wave.requestPaint() }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(Math.min(99, rootMod.percent)).padStart(2, '0') + "%"
            color: root.seal
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    Process {
        id: cpuProc
        command: ["bash", "-c",
            "read _ u1 n1 s1 i1 w1 r1 s s < /proc/stat && " +
            "sleep 0.5 && " +
            "read _ u2 n2 s2 i2 w2 r2 s s < /proc/stat && " +
            "du=$((u2+n2+s2-u1-n1-s1)) && " +
            "di=$((i2-i1)) && dt=$((du+di)) && " +
            "echo $((dt>0?100*du/dt:0))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim())
                if (!isNaN(v)) {
                    rootMod.percent = Math.max(0, Math.min(100, v))
                    var h = rootMod.history.slice()
                    h.push(rootMod.percent / 100)
                    if (h.length > rootMod.maxSamples) h.shift()
                    rootMod.history = h
                }
            }
        }
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { cpuProc.running = false; cpuProc.running = true }
    }

    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tipDelay.restart()
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: { tipDelay.stop(); root.hideTooltip(rootMod); root.cpuVisible = !root.cpuVisible }
    }
}
