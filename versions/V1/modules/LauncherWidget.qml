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
            Connections {
                target: root
                function onSealChanged() { wave.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }

    // ── bob2 logo: flat-color tint shader — exact seal color, keeps alpha ──
    Image {
        id: logo
        anchors.centerIn: parent
        height: 20
        width: Math.round(height * 656 / 192)
        source: "../assets/bob2.png"
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true
        layer.enabled: true
        layer.effect: ShaderEffect {
            property color tintColor: root.seal
            fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: {
            tip.hide()
            root.controlVisible = !root.controlVisible
        }
    }
}
