import QtQuick
import Quickshell
import Quickshell.Io
import "../IconMap.js" as IconMap

Item {
    id: rootMod
    required property var root

    property string mode:   "none"  // "wifi" | "ethernet" | "none"
    property string ssid:   ""
    property int    signal: 0
    property string iface:  ""

    // ── speed tracking ──
    property real prevRx:  -1
    property real prevTx:  -1
    property real prevMs:   0
    property real dlRate:   0
    property real ulRate:   0
    property var  dlHistory: []
    property var  ulHistory: []
    readonly property int maxSamples: 30

    function formatSpeed(bps) {
        var mb = bps / 1048576
        var s = mb < 10 ? mb.toFixed(2) : mb.toFixed(1)
        return s.padStart(5) + "M"  // always 6 chars: " 0.00M" … "100.0M"
    }

    function updateSpeeds(rx, tx, now) {
        if (prevRx >= 0 && prevMs > 0) {
            var dt = (now - prevMs) / 1000
            if (dt > 0) {
                dlRate = Math.max(0, (rx - prevRx) / dt)
                ulRate = Math.max(0, (tx - prevTx) / dt)
                var dh = dlHistory.slice(); dh.push(dlRate); if (dh.length > maxSamples) dh.shift(); dlHistory = dh
                var uh = ulHistory.slice(); uh.push(ulRate); if (uh.length > maxSamples) uh.shift(); ulHistory = uh
            }
        }
        prevRx = rx; prevTx = tx; prevMs = now
    }

    readonly property var wifiIcons: [
        "signal_wifi_0_bar", "network_wifi_1_bar", "network_wifi_2_bar",
        "network_wifi_3_bar", "signal_wifi_4_bar"
    ]
    readonly property string wifiIconName: signal > 0
        ? wifiIcons[Math.min(4, Math.floor(signal / 22))]
        : "signal_wifi_off"

    readonly property string tooltipText: {
        if (mode === "wifi")     return ssid + " · " + signal + "%"
        if (mode === "ethernet") return "↓ " + formatSpeed(dlRate) + "/s  ↑ " + formatSpeed(ulRate) + "/s"
        return "Offline"
    }

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 28

    Rectangle {
        anchors.centerIn: row
        width: row.implicitWidth + 18
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

        // ── label ──
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "NET"
            color: mode === "none"
                ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.7)
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        // ── ethernet: dual sparkline ──
        Canvas {
            id: netGraph
            visible: rootMod.mode === "ethernet"
            width: 36; height: 14
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var dl = rootMod.dlHistory
                var ul = rootMod.ulHistory
                if (dl.length < 2 && ul.length < 2) return

                // shared scale so both lines are visually comparable
                var maxV = 1
                for (var n = 0; n < dl.length; n++) if (dl[n] > maxV) maxV = dl[n]
                for (var n = 0; n < ul.length; n++) if (ul[n] > maxV) maxV = ul[n]
                maxV *= 1.15

                function drawLine(history, color, fillAlpha, strokeW) {
                    if (history.length < 2) return
                    var pts = []
                    for (var i = 0; i < history.length; i++) {
                        pts.push({
                            x: (i / (rootMod.maxSamples - 1)) * width,
                            y: height - (history[i] / maxV) * height
                        })
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
                    ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, fillAlpha)
                    ctx.fill()
                    // stroke
                    ctx.beginPath()
                    ctx.moveTo(pts[0].x, pts[0].y)
                    for (var k = 1; k < pts.length; k++) {
                        var mx = (pts[k-1].x + pts[k].x) / 2
                        ctx.bezierCurveTo(mx, pts[k-1].y, mx, pts[k].y, pts[k].x, pts[k].y)
                    }
                    ctx.strokeStyle = color.toString()
                    ctx.lineWidth = strokeW
                    ctx.lineCap = "round"; ctx.lineJoin = "round"
                    ctx.stroke()
                }

                drawLine(dl, root.seal,   0.12, 1.5)   // download — seal
                drawLine(ul, root.indigo, 0.10, 1.0)   // upload   — indigo
            }

            Connections {
                target: rootMod
                function onDlHistoryChanged() { netGraph.requestPaint() }
                function onUlHistoryChanged() { netGraph.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }

        // ── ethernet: down/up speed, stacked to save width ──
        Column {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.mode === "ethernet"
            spacing: 0
            Text {
                width: 48
                horizontalAlignment: Text.AlignRight
                text: "↓" + rootMod.formatSpeed(rootMod.dlRate)
                color: root.seal
                font.family: root.mono
                font.pixelSize: 9
            }
            Text {
                width: 48
                horizontalAlignment: Text.AlignRight
                text: "↑" + rootMod.formatSpeed(rootMod.ulRate)
                color: root.indigo
                font.family: root.mono
                font.pixelSize: 9
            }
        }

        // ── wifi: icon ──
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.mode === "wifi"
            text: IconMap.icon(rootMod.wifiIconName)
            color: root.ink
            font.family: "Material Symbols Rounded"
            font.pixelSize: 14
        }

        // ── wifi: ssid ──
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: rootMod.mode === "wifi"
            text: rootMod.ssid
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 1
        }
    }

    Process {
        id: netProc
        command: ["bash", "-c",
            "IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}'); " +
            "if [ -z \"$IFACE\" ]; then echo NONE; exit; fi; " +
            "RX=$(awk -v i=\"$IFACE:\" '$1==i{print $2}' /proc/net/dev 2>/dev/null); " +
            "TX=$(awk -v i=\"$IFACE:\" '$1==i{print $10}' /proc/net/dev 2>/dev/null); " +
            "if [ -d \"/sys/class/net/$IFACE/wireless\" ]; then " +
            "  LINK=$(iw dev \"$IFACE\" link 2>/dev/null); " +
            "  SSID=$(printf '%s\\n' \"$LINK\" | sed -n 's/^\\s*SSID: //p' | head -1); " +
            "  SIG=$(printf '%s\\n' \"$LINK\" | awk '/signal:/ {print int($2); exit}'); " +
            "  QUAL=$(awk -v s=\"$SIG\" 'BEGIN{q=int((s+110)*100/70);if(q<0)q=0;if(q>100)q=100;print q}'); " +
            "  printf 'WIFI\\t%s\\t%s\\t%s\\t%s\\n' \"$SSID\" \"$QUAL\" \"$RX\" \"$TX\"; " +
            "else " +
            "  printf 'ETHERNET\\t%s\\t%s\\t%s\\n' \"$IFACE\" \"$RX\" \"$TX\"; " +
            "fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var line  = this.text.trim()
                var parts = line.split("\t")
                var now   = Date.now()

                if (parts[0] === "WIFI" && parts.length >= 5) {
                    rootMod.mode   = "wifi"
                    rootMod.ssid   = parts[1] || ""
                    rootMod.signal = parseInt(parts[2]) || 0
                    rootMod.updateSpeeds(parseFloat(parts[3]) || 0, parseFloat(parts[4]) || 0, now)
                } else if (parts[0] === "ETHERNET" && parts.length >= 4) {
                    rootMod.mode  = "ethernet"
                    rootMod.iface = parts[1] || ""
                    rootMod.updateSpeeds(parseFloat(parts[2]) || 0, parseFloat(parts[3]) || 0, now)
                } else {
                    rootMod.mode  = "none"
                    rootMod.prevRx = -1; rootMod.prevTx = -1
                }
            }
        }
    }

    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netProc.running = false; netProc.running = true }
    }

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    Process { id: clickRunner; command: ["bash", "-c", "omarchy-launch-wifi"] }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tipDelay.restart()
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: (e) => {
            tipDelay.stop(); root.hideTooltip(rootMod)
            if (e.button === Qt.RightButton) { clickRunner.running = false; clickRunner.running = true }
            else root.networkVisible = !root.networkVisible
        }
    }
}
