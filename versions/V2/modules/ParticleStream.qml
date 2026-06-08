import QtQuick

Item {
    id: root
    required property var   theme
    required property Item  layout   // island: exposes pillRuns, runRightEdge(), runLeftEdge()
    property bool active: false
    property int  mode:   1          // 1=stream, 2=surge, 3=bolt

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
            // deterministic pseudo-random 0..1 (stable per seed; drives the bolt's jagged path)
            function hash(n) { var s = Math.sin(n * 127.1) * 43758.5453; return s - Math.floor(s) }

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

                if (root.mode === 1) {
                    // ══ STREAM: dots riding a glowing rail ══

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
                    var sp1  = 65   // px between fast dots
                    var sp2  = 110  // px between slow dots
                    var off1 = (now / 1000 * 70) % sp1
                    var off2 = (now / 1000 * 38) % sp2

                    // fast layer — cap at 60 iterations (60×65 = 3900 px)
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

                } else if (root.mode === 2) {
                    // ══ SURGE: current pulses race inward from both edges, meet, flash ══
                    var T     = 3900
                    // per-gap phase offset → the pulses ripple across the bar, gap by gap
                    var p     = (((now % T) / T) + g * 0.20) % 1   // 0..1 cycle
                    var env   = Math.min(1, p / 0.12)       // quick fade-in at the edges
                    var mid   = (x1 + x2) / 2
                    var reach = gw / 2
                    var xL    = x1 + p * reach
                    var xR    = x2 - p * reach

                    // faint rail for continuity
                    ctx.globalAlpha = 0.16
                    ctx.strokeStyle = seal
                    ctx.lineWidth   = 1.0
                    ctx.beginPath(); ctx.moveTo(x1, cy); ctx.lineTo(x2, cy); ctx.stroke()

                    // current traces: faint at origin edge → bright at the head
                    var lg = ctx.createLinearGradient(x1, 0, xL, 0)
                    lg.addColorStop(0.0, rgba(0.0)); lg.addColorStop(1.0, rgba(0.5 * env))
                    ctx.globalAlpha = 1.0; ctx.strokeStyle = lg; ctx.lineWidth = 1.6
                    ctx.beginPath(); ctx.moveTo(x1, cy); ctx.lineTo(xL, cy); ctx.stroke()
                    var rg = ctx.createLinearGradient(x2, 0, xR, 0)
                    rg.addColorStop(0.0, rgba(0.0)); rg.addColorStop(1.0, rgba(0.5 * env))
                    ctx.strokeStyle = rg
                    ctx.beginPath(); ctx.moveTo(x2, cy); ctx.lineTo(xR, cy); ctx.stroke()

                    // bright heads (seal glow + white core)
                    ctx.globalAlpha = 0.45 * env; ctx.fillStyle = seal
                    ctx.beginPath(); ctx.arc(xL, cy, 4.0, 0, Math.PI * 2); ctx.fill()
                    ctx.beginPath(); ctx.arc(xR, cy, 4.0, 0, Math.PI * 2); ctx.fill()
                    ctx.globalAlpha = 0.95 * env; ctx.fillStyle = "#ffffff"
                    ctx.beginPath(); ctx.arc(xL, cy, 1.7, 0, Math.PI * 2); ctx.fill()
                    ctx.beginPath(); ctx.arc(xR, cy, 1.7, 0, Math.PI * 2); ctx.fill()

                    // soft flash where the two pulses meet
                    if (p > 0.78) {
                        var fl = (p - 0.78) / 0.22          // 0..1 bloom
                        ctx.globalAlpha = 0.50 * (1 - fl); ctx.fillStyle = "#ffffff"
                        ctx.beginPath(); ctx.arc(mid, cy, 2 + fl * 6,  0, Math.PI * 2); ctx.fill()
                        ctx.globalAlpha = 0.30 * (1 - fl); ctx.fillStyle = seal
                        ctx.beginPath(); ctx.arc(mid, cy, 4 + fl * 10, 0, Math.PI * 2); ctx.fill()
                    }

                } else {
                    // ══ BOLT: current waves charge the field, then discharge as an arc ══
                    var Tb    = 2800
                    var local = now / Tb + g * 0.37          // per-gap offset → cycles stagger
                    var ph    = local - Math.floor(local)    // 0..1 within this gap's cycle
                    var seed  = Math.floor(local) * 131.7 + g * 53.3

                    var charging = ph < 0.82
                    var charge   = Math.pow(Math.min(1, ph / 0.82), 1.6)  // 0..1 build-up (eases in → surges)
                    var dw       = charging ? 0 : (ph - 0.82) / 0.18      // 0..1 through discharge
                    var waveI    = charging ? charge : (1 - dw)           // swells, then collapses into the bolt

                    // ── charged field: two overlapping wave lines that swell as they charge ──
                    var baseAmp = Math.min(height * 0.30, 6.0)
                    var amp     = (0.22 + 0.78 * waveI) * baseAmp          // swells toward discharge
                    var stepw   = Math.max(2, Math.round(gw / 120))        // fine sampling → smooth, crisp curve
                    // (freq, drift, phase, weight) — opposite drifts → the two lines cross and overlap
                    var waves = [ [0.055, -3.0, 0.0, 1.00],
                                  [0.072,  3.6, 2.4, 0.78] ]
                    for (var wi = 0; wi < waves.length; wi++) {
                        var wk = waves[wi][0], wsp = waves[wi][1], wp = waves[wi][2], ww = waves[wi][3]
                        ctx.beginPath()
                        var first = true
                        for (var wx = x1; wx <= x2; wx += stepw) {
                            var wy = cy + amp * ww * Math.sin(wx * wk + now / 1000 * wsp + wp)
                            if (first) { ctx.moveTo(wx, wy); first = false }
                            else        ctx.lineTo(wx, wy)
                        }
                        // faint wide glow, then a crisp thin core (same path → sharp definition)
                        ctx.globalAlpha = (0.05 + waveI * 0.16) * ww
                        ctx.strokeStyle = seal; ctx.lineWidth = 2.6; ctx.stroke()
                        ctx.globalAlpha = (0.22 + waveI * 0.55) * ww
                        ctx.strokeStyle = seal; ctx.lineWidth = 1.0; ctx.stroke()
                    }

                    // ── discharge: the stored charge releases as a bright arc + flash ──
                    if (!charging) {
                        var env  = Math.pow(1 - dw, 1.7)                   // sharp onset, quick decay
                        var aB   = env * (0.7 + 0.3 * Math.sin(now / 30))  // bright crackle
                        var segs = Math.max(4, Math.min(14, Math.round(gw / 26)))
                        var amp  = Math.min(height * 0.26, 4.6)

                        // release flash: a bright bloom filling the gap, lingering after the strike
                        var fla = Math.pow(Math.max(0, 1 - dw / 0.78), 1.3)
                        if (fla > 0) {
                            var fh  = 9
                            var fgr = ctx.createLinearGradient(0, cy - fh, 0, cy + fh)
                            fgr.addColorStop(0.0, rgba(0.0))
                            fgr.addColorStop(0.5, rgba(0.24 * fla))
                            fgr.addColorStop(1.0, rgba(0.0))
                            ctx.globalAlpha = 1.0; ctx.fillStyle = fgr
                            ctx.fillRect(x1, cy - fh, gw, fh * 2)
                        }

                        // the jagged arc — wide seal glow + crisp bright white core
                        ctx.lineJoin = "round"
                        ctx.beginPath(); ctx.moveTo(x1, cy)
                        for (var i = 1; i <= segs; i++) {
                            var bx = x1 + (i / segs) * gw
                            var by = (i === segs) ? cy : cy + (hash(seed + i) - 0.5) * 2 * amp
                            ctx.lineTo(bx, by)
                        }
                        ctx.globalAlpha = 0.42 * aB; ctx.strokeStyle = seal;      ctx.lineWidth = 3.4; ctx.stroke()
                        ctx.globalAlpha = 0.95 * aB; ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.2; ctx.stroke()

                        // short fork
                        var bm = Math.floor(segs * 0.45)
                        var fx = x1 + (bm / segs) * gw
                        var fy = cy + (hash(seed + bm) - 0.5) * 2 * amp
                        ctx.beginPath(); ctx.moveTo(fx, fy)
                        for (var j = 1; j <= 3; j++) {
                            ctx.lineTo(fx + j * (gw * 0.07),
                                       fy + (hash(seed + 90 + j) - 0.5) * 2 * amp - j * 1.2)
                        }
                        ctx.globalAlpha = 0.5 * aB; ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 0.8; ctx.stroke()
                    }
                }

                ctx.restore()
            }

            ctx.globalAlpha = 1.0
        }
    }
}
