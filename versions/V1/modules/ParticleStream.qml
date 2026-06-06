import QtQuick

Item {
    id: root
    required property var   theme
    required property Item  layout   // island: exposes pillRuns, runRightEdge(), runLeftEdge()
    property bool active: false

    opacity: active ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutCubic } }

    Timer {
        interval: 16
        repeat: true
        running: root.active
        onTriggered: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx  = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.active) return
            if (!root.layout || !root.layout.pillRuns) return

            var now  = Date.now()
            var cy   = height / 2
            var seal = root.theme.seal
            if (!seal) return
            var sr   = Math.round(seal.r * 255)
            var sg   = Math.round(seal.g * 255)
            var sb   = Math.round(seal.b * 255)

            function rgba(a) { return "rgba(" + sr + "," + sg + "," + sb + "," + a + ")" }

            var runs = root.layout.pillRuns

            for (var g = 0; g + 1 < runs.length; g++) {
                var x1 = root.layout.runRightEdge(runs[g].e)
                var x2 = root.layout.runLeftEdge(runs[g + 1].s)
                var gw = x2 - x1
                // guard against NaN/Infinity (would cause infinite loops below)
                if (gw < 10 || !isFinite(x1) || !isFinite(x2)) continue

                // clip drawing strictly to this gap
                ctx.save()
                ctx.beginPath()
                ctx.rect(x1, 0, gw, height)
                ctx.clip()

                // ── outer glow: diffuse aura around the track ──
                var gh  = 8
                var grd = ctx.createLinearGradient(0, cy - gh, 0, cy + gh)
                grd.addColorStop(0.00, rgba(0.00))
                grd.addColorStop(0.25, rgba(0.06))
                grd.addColorStop(0.45, rgba(0.11))
                grd.addColorStop(0.50, rgba(0.14))
                grd.addColorStop(0.55, rgba(0.11))
                grd.addColorStop(0.75, rgba(0.06))
                grd.addColorStop(1.00, rgba(0.00))
                ctx.globalAlpha = 1.0
                ctx.fillStyle   = grd
                ctx.fillRect(x1, cy - gh, gw, gh * 2)

                // ── center line: the rail the dots ride on ──
                ctx.globalAlpha = 0.55
                ctx.strokeStyle = rgba(1.0)
                ctx.lineWidth   = 1.5
                ctx.beginPath(); ctx.moveTo(x1, cy); ctx.lineTo(x2, cy); ctx.stroke()
                // white core of the rail
                ctx.globalAlpha = 0.28
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth   = 0.75
                ctx.beginPath(); ctx.moveTo(x1, cy); ctx.lineTo(x2, cy); ctx.stroke()

                // ── global stream: fixed speed + spacing, gap is a viewport ──
                // same density and speed in every gap regardless of width
                var sp1  = 65   // px between fast dots
                var sp2  = 110  // px between slow dots
                var off1 = (now / 1000 * 70) % sp1
                var off2 = (now / 1000 * 38) % sp2

                // fast layer: enumerate dots whose global x falls in [x1, x2)
                // cap at 60 iterations — covers any realistic screen width (60×65 = 3900 px)
                var k1 = Math.ceil((x1 - off1) / sp1)
                for (var di = 0; di < 60; di++) {
                    var fx = off1 + (k1 + di) * sp1
                    if (fx >= x2) break
                    var dotId   = (k1 + di + 100000)
                    var isPulse = (dotId % 5 === 0)
                    if (isPulse) {
                        var pulse = 0.5 + 0.5 * Math.sin(now / 700 + dotId * 2.4)
                        ctx.globalAlpha = 0.28 + pulse * 0.18
                        ctx.fillStyle   = seal
                        ctx.beginPath(); ctx.arc(fx, cy, 4.0 + pulse * 1.5, 0, Math.PI * 2); ctx.fill()
                        ctx.globalAlpha = 0.95
                        ctx.fillStyle   = "#ffffff"
                        ctx.beginPath(); ctx.arc(fx, cy, 1.6 + pulse * 0.4, 0, Math.PI * 2); ctx.fill()
                    } else {
                        ctx.globalAlpha = 0.30
                        ctx.fillStyle   = seal
                        ctx.beginPath(); ctx.arc(fx, cy, 4.5, 0, Math.PI * 2); ctx.fill()
                        ctx.globalAlpha = 0.90
                        ctx.fillStyle   = "#ffffff"
                        ctx.beginPath(); ctx.arc(fx, cy, 1.6, 0, Math.PI * 2); ctx.fill()
                    }
                }

                // slow layer
                var k2 = Math.ceil((x1 - off2) / sp2)
                for (var dj = 0; dj < 40; dj++) {
                    var sx = off2 + (k2 + dj) * sp2
                    if (sx >= x2) break
                    ctx.globalAlpha = 0.11
                    ctx.fillStyle   = seal
                    ctx.beginPath(); ctx.arc(sx, cy, 8.5, 0, Math.PI * 2); ctx.fill()
                    ctx.globalAlpha = 0.50
                    ctx.fillStyle   = "#ffffff"
                    ctx.beginPath(); ctx.arc(sx, cy, 2.3, 0, Math.PI * 2); ctx.fill()
                }

                ctx.restore()
            }

            ctx.globalAlpha = 1.0
        }
    }
}
