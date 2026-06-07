import QtQuick
import Quickshell

Item {
    id: rootMod
    required property var root

    implicitWidth: logo.width + 18
    implicitHeight: 28

    readonly property string tooltipText: "Control center"

    // animated wave phase
    property real phase: 0
    NumberAnimation on phase {
        from: 0; to: 2 * Math.PI
        duration: 2600; loops: Animation.Infinite; running: true
    }

    // ── pill background (same style as other widgets) with the wave inside ──
    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: logo.width + 18
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
        clip: true

        Canvas {
            id: wave
            anchors.fill: parent
            opacity: 0.55

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cy = height / 2
                var amp = 3.0
                var k = (2 * Math.PI) / width * 2   // two cycles across the width

                function drawWave(phaseOff, alpha) {
                    ctx.beginPath()
                    for (var x = 0; x <= width; x += 2) {
                        var y = cy + Math.sin(x * k + rootMod.phase + phaseOff) * amp
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.strokeStyle = Qt.rgba(root.seal.r, root.seal.g, root.seal.b, alpha)
                    ctx.lineWidth = 1.5
                    ctx.lineCap = "round"
                    ctx.stroke()
                }

                drawWave(0,       0.45)
                drawWave(Math.PI, 0.22)
            }

            Connections {
                target: rootMod
                function onPhaseChanged() { wave.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }

    // ── bob2 logo: transparent PNG colorized with theme seal ──
    Canvas {
        id: logo
        anchors.centerIn: parent
        height: 20
        width: Math.round(height * 656 / 192)   // native aspect ratio

        property color tint: root.seal
        onTintChanged: requestPaint()

        Component.onCompleted: loadImage("../assets/bob2.png")
        onImageLoaded: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!isImageLoaded("../assets/bob2.png") || width < 1 || height < 1) return
            ctx.drawImage("../assets/bob2.png", 0, 0, width, height)
            var img = ctx.getImageData(0, 0, width, height)
            var d   = img.data
            var r   = Math.round(tint.r * 255)
            var g   = Math.round(tint.g * 255)
            var b   = Math.round(tint.b * 255)
            for (var i = 0; i < d.length; i += 4) {
                d[i]   = r
                d[i+1] = g
                d[i+2] = b
            }
            ctx.putImageData(img, 0, 0)
        }
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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tipDelay.restart()
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: {
            tipDelay.stop(); root.hideTooltip(rootMod)
            root.controlVisible = !root.controlVisible
        }
    }
}
