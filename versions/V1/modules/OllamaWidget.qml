import QtQuick

Item {
    id: rootMod
    required property var root

    visible: implicitWidth > 0.5
    implicitWidth: root.modOllama ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modOllama ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    readonly property string tooltipText: root.ollama.connected
        ? "Ollama " + root.ollama.version + " · " + root.ollama.loadedModels.length
            + " loaded · " + formatVram(root.ollama.loadedVramBytes)
        : "Ollama offline"

    function formatVram(bytes) {
        if (!(bytes > 0)) return "0 MiB"
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GiB"
        return Math.round(bytes / 1048576) + " MiB"
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(row.width) + 18
        height: root.pillH
        radius: root.pillRadius
        color: root.pill
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.compactOllama ? 4 : 5

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 18
            source: Qt.resolvedUrl("../assets/ollama.svg")
            sourceSize: Qt.size(16, 18)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            layer.enabled: true
            layer.smooth: true
            layer.effect: ShaderEffect {
                property color tintColor: root.ollama.connected ? root.seal : root.sumi
                fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
            }
        }

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compactOllama
            text: "GPU"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
            font.family: root.mono
            font.pixelSize: 12
        }

        Canvas {
            id: gpuWave
            visible: !root.compactOllama
            width: 36
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            property color tint: root.seal
            onTintChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var h = root.ollama.gpuHistory
                if (!h || h.length < 2) return

                var maxV = 0.25
                for (var n = 0; n < h.length; n++) {
                    if (h[n] > maxV) maxV = h[n]
                }
                maxV = Math.min(1, Math.max(0.25, maxV * 1.15))

                var pts = []
                for (var i = 0; i < h.length; i++) {
                    var x = (i / (root.ollama.gpuMaxSamples - 1)) * width
                    var y = height - (h[i] / maxV) * height
                    pts.push({ x: x, y: y })
                }

                ctx.beginPath()
                ctx.moveTo(pts[0].x, height)
                ctx.lineTo(pts[0].x, pts[0].y)
                for (var j = 1; j < pts.length; j++) {
                    var cx = (pts[j-1].x + pts[j].x) / 2
                    ctx.bezierCurveTo(cx, pts[j-1].y, cx, pts[j].y, pts[j].x, pts[j].y)
                }
                ctx.lineTo(pts[pts.length-1].x, height)
                ctx.closePath()
                ctx.fillStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.12)
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(pts[0].x, pts[0].y)
                for (var k = 1; k < pts.length; k++) {
                    var mx = (pts[k-1].x + pts[k].x) / 2
                    ctx.bezierCurveTo(mx, pts[k-1].y, mx, pts[k].y, pts[k].x, pts[k].y)
                }
                ctx.strokeStyle = tint
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.stroke()
            }

            Component.onCompleted: requestPaint()
            Connections {
                target: root.ollama
                function onGpuHistoryChanged() { gpuWave.requestPaint() }
            }
        }

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.ollama.gpuPercent >= 0
                ? String(Math.min(100, root.ollama.gpuPercent)).padStart(2, "0") + "%"
                : "N/A"
            color: root.ollama.connected ? root.seal : root.sumi
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: tip.hide()
        onClicked: { tip.hide(); root.ollamaVisible = !root.ollamaVisible }
    }
}
