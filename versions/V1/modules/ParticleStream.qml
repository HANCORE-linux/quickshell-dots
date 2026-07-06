import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

Item {
    id: root
    required property var   theme
    required property Item  layout   // island: exposes pillRuns, runRightEdge(), runLeftEdge()
    property bool active: false
    property int  mode:   1          // 1=stream, 2=surge, 3=bolt, 4=bolt2, 5=stream2, 6=surge2, 7=reactor, 8=quotes
    property string monitor: ""      // this bar's output (for monitor-focus pulses)

    opacity: active ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutCubic } }

    // ── event impulses for the mode-7 reactor ──
    // tiny bounded queue; each pulse has a fixed lifetime and is pruned on push/paint
    property var pulses: []
    property bool animating7: false
    property bool animating8: false
    property int lastWsId: -1
    property int pendingWsId: -1
    property int pendingWsDir: 1
    property string activeAddr7: ""
    property string pendingUrgentAddr7: ""
    property string pendingUrgentCls7: ""
    property var recentOpen7: ({})
    // Persistent ambient particle field for the reactor (mode 7): the very
    // particles that condense into event text stay visible drifting at rest and
    // reorganise to form the text on events, then disperse. Set false to keep the
    // pure zero-idle reactor (empty at rest, ~0% CPU).
    property bool ambientField7: true

    // External-event feed: any tool can push a message to the reactor by writing
    // one line "<epoch_ms>\tLEFT\tRIGHT" to ~/.cache/qs-reactor-event (truncate).
    // First load only baselines, so pre-existing content is not replayed on start.
    property double lastReactorTs: -1
    property bool reactorBaselined: false
    FileView {
        id: reactorEventFile
        path: Quickshell.env("HOME") + "/.cache/qs-reactor-event"
        watchChanges: true
        onFileChanged: reactorEventFile.reload()
        onLoaded: {
            if (!root.reactorBaselined) { root.reactorBaselined = true; root.lastReactorTs = Date.now(); return }
            var raw = (reactorEventFile.text() || "").trim()
            if (raw === "") return
            var nl = raw.lastIndexOf("\n")
            if (nl >= 0) raw = raw.slice(nl + 1)
            var parts = raw.split("\t")
            var ts = parseFloat(parts[0])
            if (!isFinite(ts) || ts <= root.lastReactorTs) return
            root.lastReactorTs = ts
            if (root.armed7 && root.active && root.mode === 7)
                root.pushText(parts[1] || "", parts[2] || "", 1, "long")
        }
    }

    onModeChanged: {
        warnQueue7 = []
        warnQueueTimer.stop()
        if (mode !== 7) {
            pulses = []
            animating7 = false
            pendingUrgentAddr7 = ""
            pendingUrgentCls7 = ""
            urgentAddr = ""
            urgentCls = ""
            urgentNags = 0
            recentOpen7 = ({})
            urgentProbe7.stop()
        } else {
            pulses = []
            animating7 = root.ambientField7   // field needs a running paint loop
            var ws7 = Hyprland.focusedWorkspace
            lastWsId = ws7 && ws7.id > 0 ? ws7.id : -1
            canvas.tick7 = 16
            Qt.callLater(function() {
                if (root.active && root.mode === 7)
                    root.pushText("REACTOR", "ARMED", 1, "short")
            })
        }
        if (mode === 8) {
            animating8 = true
            quoteWake8.stop()
            canvas.tick7 = 16
        } else {
            animating8 = false
            quoteWake8.stop()
            canvas.quoteSwarm = null
        }
        canvas.requestPaint()
    }

    onActiveChanged: {
        if (!active) {
            animating7 = false
            animating8 = false
            quoteWake8.stop()
            pendingUrgentAddr7 = ""
            pendingUrgentCls7 = ""
            urgentAddr = ""
            urgentCls = ""
            urgentNags = 0
            recentOpen7 = ({})
            urgentProbe7.stop()
            warnQueue7 = []
            warnQueueTimer.stop()
        } else if (mode === 8) {
            animating8 = true
            quoteWake8.stop()
            canvas.tick7 = 16
            canvas.requestPaint()
        }
    }

    function scheduleQuoteWake8(delay) {
        if (!active || mode !== 8) return
        quoteWake8.interval = Math.max(250, Math.ceil(delay))
        quoteWake8.restart()
    }

    Timer {
        id: quoteWake8
        repeat: false
        running: false
        onTriggered: {
            if (!root.active || root.mode !== 8) return
            root.animating8 = true
            canvas.tick7 = 16
            canvas.requestPaint()
        }
    }

    readonly property string quotesPath8: Quickshell.env("HOME") + "/.config/quickshell/bar/quotes.txt"
    property var quotes8: [
        { q: "THE ONLY WAY TO DO GREAT WORK IS TO LOVE WHAT YOU DO.", a: "STEVE JOBS" }
    ]

    function sanitizeQuote8(s, cap) {
        s = String(s || "").toUpperCase()
        s = s.replace(/\u2018|\u2019|\u0060|\u00b4/g, "'")
             .replace(/\u201c|\u201d/g, "")
             .replace(/\u2014|\u2013|\u2015/g, "-")
             .replace(/\u2026/g, ".")
        var ok = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,'!-/; "
        var out = ""
        for (var i = 0; i < s.length && out.length < cap; i++)
            if (ok.indexOf(s.charAt(i)) >= 0) out += s.charAt(i)
        return out.replace(/ +/g, " ").trim()
    }

    function parseQuotes8(text) {
        var out = []
        var lines = String(text || "").split(/\r?\n/)
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "" || line.charAt(0) === "#") continue
            var cut = line.lastIndexOf("|")
            var q = cut >= 0 ? line.substring(0, cut) : line
            var a = cut >= 0 ? line.substring(cut + 1) : ""
            q = sanitizeQuote8(q, 160)
            a = sanitizeQuote8(a, 36)
            if (q !== "") out.push({ q: q, a: a })
        }
        return out
    }

    function reloadQuotes8() {
        var parsed = []
        try { parsed = parseQuotes8(quotesFile8.text()) } catch (e) {}
        if (parsed.length > 0) quotes8 = parsed
        if (canvas) {
            canvas.quoteSwarm = null
            if (active && mode === 8) {
                animating8 = true
                canvas.tick7 = 16
                canvas.requestPaint()
            }
        }
    }

    FileView {
        id: quotesFile8
        path: root.quotesPath8
        watchChanges: true
        onFileChanged: quotesFile8.reload()
        onLoaded: root.reloadQuotes8()
    }

    function pulseLife7(p) {
        if (!p) return 0
        if (p.k === "text") return p.life || 10500
        if (p.k === "monsweep") return p.life || 3400
        if (p.k === "win") return 1600
        return 5000
    }

    function pushPulse(kind, dir, opts) {
        if (!active || mode !== 7) return
        var tnow = Date.now()
        var ps = []
        for (var i = 0; i < pulses.length; i++)
            if (tnow - pulses[i].t < pulseLife7(pulses[i])) ps.push(pulses[i])
        var p = { t: tnow, k: kind, d: dir === undefined ? 1 : dir }
        opts = opts || ({})
        if (opts.life !== undefined) p.life = opts.life
        if (opts.gain !== undefined) p.gain = opts.gain
        if (opts.count !== undefined) p.count = opts.count
        if (ps.length < 8) ps.push(p)
        pulses = ps
        animating7 = true
        canvas.tick7 = 16
        canvas.requestPaint()
    }

    function workspaceLabel(n) {
        return n === 0 ? "EMPTY" : (n === 1 ? "1 APP" : n + " APPS")
    }

    function requestWorkspaceText(id, dir) {
        if (!active || mode !== 7 || id <= 0) return
        pendingWsId = id
        pendingWsDir = dir
        wsCountProc.running = false
        wsCountProc.running = true
    }

    function eventAddr7(data) {
        var s = String(data || "").trim()
        if (s === "") return ""
        var comma = s.indexOf(",")
        if (comma >= 0) s = s.substring(0, comma)
        return s.replace(/^0x/, "").toLowerCase()
    }

    function classForAddr7(addr) {
        if (addr === "") return ""
        try {
            var tls = Hyprland.toplevels.values
            for (var i = 0; i < tls.length; i++) {
                var o = tls[i].lastIpcObject
                if (o && String(o.address || "").replace(/^0x/, "").toLowerCase() === addr)
                    return o.class || o.initialClass || ""
            }
        } catch (e) {}
        return ""
    }

    function rememberOpen7(addr) {
        if (addr === "") return
        var ro = recentOpen7
        var now = Date.now()
        ro[addr] = now
        for (var k in ro)
            if (now - ro[k] > 5000) delete ro[k]
        recentOpen7 = ro
    }

    function commitUrgent7() {
        var addr = pendingUrgentAddr7
        var cls = pendingUrgentCls7
        pendingUrgentAddr7 = ""
        pendingUrgentCls7 = ""
        if (!active || mode !== 7 || addr === "") return
        if (addr === activeAddr7) return

        var ro = recentOpen7
        var openedAt = ro[addr] || 0
        if (openedAt > 0 && Date.now() - openedAt < 2500) {
            delete ro[addr]
            recentOpen7 = ro
            return
        }

        cls = cls || classForAddr7(addr)
        if (cls === "") return
        urgentAddr = addr
        urgentCls = cls
        urgentNags = 0
        var wn0 = warnNext; wn0.urgent = 0; warnNext = wn0
        warnCheck()
    }

    Timer {
        id: urgentProbe7
        interval: 700
        repeat: false
        running: false
        onTriggered: root.commitUrgent7()
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            var f = Hyprland.focusedWorkspace
            var id = f ? f.id : -1
            if (id > 0 && root.lastWsId > 0 && id !== root.lastWsId) {
                // Quickshell's Hyprland.workspace mirror can be stale here; read the
                // compositor's own snapshot once per switch for the visible app count.
                root.requestWorkspaceText(id, id > root.lastWsId ? 1 : -1)
            }
            if (id > 0) root.lastWsId = id
        }
        function onFocusedMonitorChanged() {
            var m = Hyprland.focusedMonitor
            if (m && root.monitor !== "" && m.name === root.monitor)
                root.pushPulse("monsweep", 1)
        }
        function onRawEvent(event) {
            if (event.name === "openwindow") {
                root.rememberOpen7(root.eventAddr7(event.data))
                root.pushPulse("win", 1)
            }
            else if (event.name === "closewindow") {
                root.pushPulse("win", -1)
                var ac = root.eventAddr7(event.data)
                var ro = root.recentOpen7
                if (ac !== "" && ro[ac] !== undefined) {
                    delete ro[ac]
                    root.recentOpen7 = ro
                }
                if (root.urgentAddr !== "" && ac === root.urgentAddr) root.clearUrgent7()
                if (root.pendingUrgentAddr7 !== "" && ac === root.pendingUrgentAddr7) {
                    root.pendingUrgentAddr7 = ""
                    root.pendingUrgentCls7 = ""
                    urgentProbe7.stop()
                }
            }
            else if (event.name === "fullscreen") {
                var fsOn7 = String(event.data).trim() === "1"
                root.pushText("FULLSCREEN", fsOn7 ? "ON" : "OFF", 1, "short")
            }
            else if (event.name === "urgent") {
                // Some apps briefly raise urgent while they are still opening.
                // Delay the warning and drop it if the window is already focused.
                var adr = root.eventAddr7(event.data)
                if (adr !== "") {
                    root.pendingUrgentAddr7 = adr
                    root.pendingUrgentCls7 = root.classForAddr7(adr)
                    urgentProbe7.restart()
                }
            }
            else if (event.name === "activewindowv2") {
                // focusing the urgent window resolves the warning
                var a2 = root.eventAddr7(event.data)
                root.activeAddr7 = a2
                if (root.urgentAddr !== "" && a2 === root.urgentAddr) root.clearUrgent7()
                if (root.pendingUrgentAddr7 !== "" && a2 === root.pendingUrgentAddr7) {
                    root.pendingUrgentAddr7 = ""
                    root.pendingUrgentCls7 = ""
                    urgentProbe7.stop()
                }
            }
        }
    }

    Process {
        id: wsCountProc
        command: ["hyprctl", "workspaces", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var id = root.pendingWsId
                if (id <= 0) return
                var n = -1
                try {
                    var arr = JSON.parse(this.text)
                    for (var i = 0; i < arr.length; i++) {
                        if (arr[i].id === id) {
                            if (arr[i].windows !== undefined) n = Number(arr[i].windows)
                            break
                        }
                    }
                } catch (e) {}
                root.pushText("WS " + id, n >= 0 ? root.workspaceLabel(n) : "", root.pendingWsDir, "short")
            }
        }
    }

    property string pendingThemeName7: ""

    function themeName7() {
        var n = pendingThemeName7
        if (n === "") {
            try { n = String(themeNameState.text() || "").trim() } catch (e) {}
        }
        if (n === "" && theme.lastAppliedName !== undefined)
            n = String(theme.lastAppliedName || "").trim()
        return n
    }

    function scheduleThemeText7(name) {
        if (name !== undefined) pendingThemeName7 = String(name || "").trim()
        themeNameState.reload()
        themeTextTimer.restart()
    }

    // theme switch rewrites the live theme files; debounce them into one name pulse
    FileView {
        id: themeColorsState
        path: theme.colorsPath
        watchChanges: true
        onFileChanged: root.scheduleThemeText7()
    }

    FileView {
        id: themeNameState
        path: Quickshell.env("HOME") + "/.config/omarchy/current/theme.name"
        watchChanges: true
        onFileChanged: root.scheduleThemeText7()
    }

    Connections {
        target: theme
        function onLastAppliedNameChanged() {
            if (theme.lastAppliedName !== "") root.scheduleThemeText7(theme.lastAppliedName)
        }
        function onReactorTest(kind, arg) {
            root.runReactorTest(String(kind || ""), String(arg || ""))
        }
    }

    Timer {
        id: themeTextTimer
        interval: 180
        repeat: false
        onTriggered: {
            var name = root.themeName7()
            root.pendingThemeName7 = ""
            root.pushText(name !== "" ? name : "THEME CHANGED", "THEME LOADED", 1, "long")
        }
    }

    // battery entering low while discharging → queued warning text (laptop only)
    readonly property var batDev: UPower.displayDevice
    readonly property int batPct7: {
        if (!batDev) return 0
        var p = Number(batDev.percentage)
        if (!isFinite(p)) return 0
        return Math.round(p <= 1.0 ? p * 100 : p)
    }
    readonly property bool batLow: batDev !== null && batDev.isLaptopBattery
                                   && batDev.state !== UPowerDeviceState.Charging
                                   && batDev.state !== UPowerDeviceState.FullyCharged
                                   && batPct7 <= 20
    onBatLowChanged: if (batLow) warnCheck()   // warning: recurs while low

    // If this timer runs, the new QML generation loaded far enough to render.
    Timer {
        interval: 1400
        running: true
        repeat: false
        onTriggered: root.pushText("QS CONFIG RELOAD", "NO ERRORS", 1, "long")
    }

    // ── text pulses: the swarm flies in and condenses into a message ──
    // arm only after startup settles, so binding churn on load can't fire
    property bool armed7: false
    Timer {
        interval: 3000; running: true; repeat: false
        onTriggered: {
            root.armed7 = true
            root.lastNotifC = root.notifC
            root.lastNet7 = root.netMode7
        }
    }

    function sanitize7(s, cap) {
        s = (s || "").toUpperCase()
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        s = s.replace(/ß/g, "SS").replace(/Ø/g, "O").replace(/Æ/g, "AE")
             .replace(/[—–]/g, "-").replace(/[’`´]/g, "'")
        var ok = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,'!-/;< "
        var out = ""
        for (var i = 0; i < s.length && out.length < cap; i++)
            if (ok.indexOf(s.charAt(i)) >= 0) out += s.charAt(i)
        return out.replace(/ +/g, " ").trim()
    }

    function pushText(l, r, dir, profile, force) {
        if (!active || mode !== 7) return
        l = sanitize7(l, 64); r = sanitize7(r, 28)
        if (l === "" && r === "") return
        var tnow = Date.now()
        var sh = profile === "short"
        var wn = profile === "warn"    // warning: longer, and the held text throbs
        if (!wn && dnd7 && force !== true) return
        var ps = []
        for (var i = 0; i < pulses.length; i++) {
            var keep = pulseLife7(pulses[i])
            if (tnow - pulses[i].t >= keep) continue
            if (pulses[i].k !== "text") ps.push(pulses[i])
            else if (!wn && pulses[i].w) return
        }
        var lifeL = Math.min(9500, 4500 + l.length * 55)
        ps.push({ t: tnow, k: "text", d: dir === undefined ? 1 : dir, l: l, r: r, w: wn,
                  two: !wn && !sh && l.length > 24,
                  life: wn ? 10000 : (sh ? 4200 : lifeL), s0: sh ? 900 : 1500, s1: sh ? 1500 : 2300,
                  r0: wn ? 8600 : (sh ? 3000 : lifeL - 1500), r1: wn ? 9400 : (sh ? 3600 : lifeL - 700) })
        pulses = ps
        animating7 = true
        canvas.tick7 = 16
        canvas.requestPaint()
    }

    function testParts7(arg) {
        var parts = String(arg || "").split("|")
        return { l: parts[0] || "", r: parts.length > 1 ? parts.slice(1).join("|") : "" }
    }

    function runReactorTest(kind, arg) {
        if (!active || mode !== 7) return

        kind = String(kind || "").trim().toLowerCase()
        arg = String(arg || "")

        if (kind === "text" || kind === "text-long") {
            var t = testParts7(arg || "THIS IS A LONG REACTOR TEST MESSAGE|SOURCE")
            pushText(t.l, t.r || "TEST", 1, "long")
        } else if (kind === "text-short") {
            var ts = testParts7(arg || "REACTOR|TEST")
            pushText(ts.l, ts.r, 1, "short")
        } else if (kind === "text-warn" || kind === "warn") {
            var tw = testParts7(arg || "OFFLINE!|NETWORK")
            pushText(tw.l, tw.r || "WARNING", 1, "warn", true)
        } else if (kind === "win" || kind === "win-open") {
            pushPulse("win", arg === "close" || arg === "-1" ? -1 : 1)
        } else if (kind === "win-close") {
            pushPulse("win", -1)
        } else if (kind === "monsweep" || kind === "sweep") {
            pushPulse("monsweep", arg === "-1" ? -1 : 1, { life: 5200, gain: 0.82, count: 54 })
        } else if (kind === "pacman" || kind === "packages") {
            var parsedN = parseInt(arg || "3")
            var n = isFinite(parsedN) ? Math.max(1, parsedN) : 3
            pushText(n + (n === 1 ? " PACKAGE" : " PACKAGES") + " CHANGED", "PACMAN", 1, "long")
        } else if (kind === "urgent") {
            if (!armed7) return
            urgentAddr = "__test__"
            urgentCls = sanitize7(arg || "ATTENTION", 28) || "ATTENTION"
            urgentNags = 0
            var wn0 = warnNext
            wn0.urgent = 0
            warnNext = wn0
            warnCheck()
        } else if (kind === "quota") {
            if (!armed7) return
            var who = sanitize7(arg || "CLAUDE", 16) || "CLAUDE"
            queueWarn7(who + " 90", "AI QUOTA!")
        } else if (kind === "ws" || kind === "workspace") {
            var ws = parseInt(arg || "1")
            pushText("WS " + (isFinite(ws) && ws > 0 ? ws : 1), "TEST APPS", 1, "short")
        } else if (kind === "clear") {
            pulses = []
            animating7 = false
            warnQueue7 = []
            warnQueueTimer.stop()
            clearUrgent7()
            canvas.requestPaint()
        } else {
            pushText("REACTOR TEST", kind.toUpperCase(), 1, "short")
        }
    }

    // ── warning engine: warnings are STATES, not events — they re-announce
    //    themselves while the state lasts, and stop the moment it ends ──
    property var warnNext: ({ offline: 0, batt: 0, aicl: 0, aicx: 0, urgent: 0 })
    property var warnQueue7: []
    property string urgentAddr: ""
    property string urgentCls: ""
    property int urgentNags: 0

    function clearUrgent7() {
        var cls = urgentCls
        if (cls !== "" && warnQueue7.length > 0) {
            var q = []
            for (var i = 0; i < warnQueue7.length; i++) {
                var w = warnQueue7[i]
                if (!(w.l === cls && w.r === "WANTS YOU!")) q.push(w)
            }
            warnQueue7 = q
            if (q.length === 0) warnQueueTimer.stop()
        }
        urgentAddr = ""
        urgentCls = ""
        urgentNags = 0
        var wn0 = warnNext
        wn0.urgent = 0
        warnNext = wn0
    }

    function queueWarn7(l, r) {
        if (!armed7 || !active || mode !== 7) return false
        var q = warnQueue7.slice(0)
        for (var i = 0; i < q.length; i++) {
            if (q[i].l === l && q[i].r === r) return false
        }
        if (q.length >= 5) q.shift()
        q.push({ l: l, r: r })
        warnQueue7 = q
        if (!warnQueueTimer.running) {
            warnQueueTimer.interval = 1
            warnQueueTimer.restart()
        }
        return true
    }

    function drainWarnQueue7() {
        if (!active || mode !== 7 || warnQueue7.length === 0) {
            warnQueueTimer.stop()
            return
        }
        var q = warnQueue7.slice(0)
        var w = q.shift()
        warnQueue7 = q
        pushText(w.l, w.r, 1, "warn")
        if (q.length === 0) warnQueueTimer.stop()
        else warnQueueTimer.interval = 4200
    }

    function warnCheck() {
        if (!armed7 || !active || mode !== 7) return
        var tnow = Date.now()
        var wn = warnNext
        if (netMode7 === "none") {
            if (tnow >= wn.offline && queueWarn7("OFFLINE!", "NETWORK")) wn.offline = tnow + 120000
        } else wn.offline = 0
        if (batLow) {
            if (tnow >= wn.batt) {
                if (queueWarn7("BATTERY " + batPct7, "PLUG IN!"))
                    wn.batt = tnow + 120000
            }
        } else wn.batt = 0
        if (aiClHot) {
            if (tnow >= wn.aicl && queueWarn7("CLAUDE " + aiCl7, "AI QUOTA!")) wn.aicl = tnow + 300000
        } else wn.aicl = 0
        if (aiCxHot) {
            if (tnow >= wn.aicx && queueWarn7("CODEX " + aiCx7, "AI QUOTA!")) wn.aicx = tnow + 300000
        } else wn.aicx = 0
        if (urgentAddr !== "" && urgentCls !== "") {
            if (tnow >= wn.urgent && urgentNags < 3
                    && queueWarn7(urgentCls, "WANTS YOU!")) {
                wn.urgent = tnow + 60000 * Math.pow(3, urgentNags)
                urgentNags++
            }
        } else {
            wn.urgent = 0
            urgentNags = 0
        }
        warnNext = wn
    }

    Timer {
        id: warnQueueTimer
        interval: 1
        repeat: true
        running: false
        onTriggered: {
            interval = 4200
            root.drainWarnQueue7()
        }
    }

    Timer {
        interval: 30000; repeat: true
        running: root.active && root.mode === 7
        onTriggered: root.warnCheck()
    }

    // track change → swarm forms TITLE (left) and ARTIST - ALBUM (right)
    MprisSelect { id: psSel }
    readonly property string psTrack: psSel.player ? (psSel.player.trackTitle || "") : ""
    onPsTrackChanged: {
        if (!armed7 || psTrack === "") return
        var ar = psSel.player ? (psSel.player.trackArtist || "") : ""
        var al = psSel.player ? (psSel.player.trackAlbum  || "") : ""
        pushText(psTrack, ar + (al ? " - " + al : ""), 1, "long")
    }

    // new notification (the bar's mako poll counts up) → fetch newest, show
    // message left of the clock and its source right of it
    readonly property int notifC: theme.notifCount === undefined ? 0 : theme.notifCount
    property int lastNotifC: -1
    onNotifCChanged: {
        var prev = lastNotifC
        lastNotifC = notifC
        if (armed7 && active && mode === 7 && !dnd7 && prev >= 0 && notifC > prev) notifFetch.running = true
    }
    Process {
        id: notifFetch
        command: ["bash", "-c", "makoctl list -j 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d
                try { d = JSON.parse(this.text) } catch (e) { return }
                if (!d) return
                var e0 = d.length !== undefined ? d[0] : d
                if (!e0) return
                var s0 = e0.summary || "", b0 = e0.body || ""
                var msg = s0 && b0 && b0 !== s0 ? s0 + " - " + b0 : (s0 || b0)
                root.pushText(msg, e0.app_name || "NOTIFY", 1, "long")
            }
        }
    }

    // ── status-change pulses (sources: theme mirrors + Pipewire) ──
    // network dropped / came back
    readonly property string netMode7: theme.networkMode !== undefined ? theme.networkMode : ""
    property string lastNet7: ""
    onNetMode7Changed: {
        if (armed7 && lastNet7 !== "" && netMode7 !== lastNet7) {
            if (netMode7 === "none")       warnCheck()   // warning: recurs while offline
            else if (lastNet7 === "none")  pushText("ONLINE", "NETWORK", 1, "short")
        }
        lastNet7 = netMode7
    }

    // Omarchy pushed an update (UpdateWidget's 6h poll flipped to available)
    readonly property bool upd7: theme.omarchyUpdateAvail === true
    onUpd7Changed: if (armed7 && upd7) pushText("UPDATE READY", "OMARCHY", 1, "long")

    // do-not-disturb toggled
    readonly property bool dnd7: theme.notifSilenced === true
    onDnd7Changed: if (armed7) pushText(dnd7 ? "DND ON" : "DND OFF", "", 1, "short", true)

    // voxtype starts listening
    readonly property string vox7: theme.voxState !== undefined ? theme.voxState : "idle"
    onVox7Changed: if (armed7 && vox7 === "recording") pushText("VOXTYPE", "REC", 1, "short")

    // mute toggled (Pipewire pushes instantly)
    AudioData { id: psAudio }
    readonly property bool mute7: psAudio.muted === true
    onMute7Changed: {
        if (!armed7) return
        if (mute7) pushText("VOLUME", "MUTED", 1, "short")
        else pushText("VOLUME", "UNMUTED", 1, "short")
    }

    // AI quota crossing 90% of the 5h window (hysteresis: rearms below 85%)
    readonly property int aiCl7: theme.aiClPct5h !== undefined ? theme.aiClPct5h : 0
    readonly property int aiCx7: theme.aiCxPct5h !== undefined ? theme.aiCxPct5h : 0
    property bool aiClHot: false
    property bool aiCxHot: false
    readonly property string helperOwnerMonitor7: Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    readonly property bool ownsGlobalHelpers7: root.monitor === "" || root.monitor === helperOwnerMonitor7
    onAiCl7Changed: {
        if (aiCl7 >= 90 && !aiClHot) { aiClHot = true; warnCheck() }
        else if (aiCl7 < 85) aiClHot = false
    }
    onAiCx7Changed: {
        if (aiCx7 >= 90 && !aiCxHot) { aiCxHot = true; warnCheck() }
        else if (aiCx7 < 85) aiCxHot = false
    }

    // pacman transaction finished (streaming log tail — no helper script)
    Process {
        id: pacTail
        running: root.active && root.mode === 7 && root.ownsGlobalHelpers7
        command: ["bash", "-c", "tail -n 0 -F /var/log/pacman.log 2>/dev/null"]
        property int pkgN: 0
        onRunningChanged: if (!running) pkgN = 0
        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("transaction started") >= 0) pacTail.pkgN = 0
                else if (line.indexOf("] upgraded ") >= 0
                         || line.indexOf("] installed ") >= 0
                         || line.indexOf("] removed ") >= 0) pacTail.pkgN++
                else if (line.indexOf("transaction completed") >= 0 && pacTail.pkgN > 0)
                    root.pushText(pacTail.pkgN + (pacTail.pkgN === 1 ? " PACKAGE" : " PACKAGES") + " CHANGED",
                                  "PACMAN", 1, "long")
            }
        }
    }

    Timer {
        // mode 7 self-paces: the 60fps tick machinery alone (clear + texture
        // upload, both screens) costs ~23% CPU — so full rate only during
        // fast motion, half rate while a motif just breathes, ~4Hz in the
        // dark between events (canvas.tick7 is set from onPaint)
        interval: (root.mode === 7 || root.mode === 8) ? canvas.tick7 : ((root.mode === 5 || root.mode === 6) ? 16 : 33)
        repeat: true
        running: root.active && ((root.mode === 7 && root.animating7)
                                 || (root.mode === 8 && root.animating8)
                                 || (root.mode !== 7 && root.mode !== 8))
        onTriggered: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Threaded
        // adaptive tick for mode 7/8: 16ms while moving, slower while idle/holding
        property int tick7: 250
        // dot-matrix glyph table for text pulses, built once on first use
        property var swarmData: null
        // mode 8 quotes cache, separate from the mode-7 event cache
        property var quoteData: null
        property var quoteSwarm: null
        property real fieldFade: 1.0   // ambient-field dim while text is forming
        property int  recruited: 0     // pool particles currently spelling the text

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

            if (root.mode === 8) {
                // Quotes: drifting dots periodically snap into a readable
                // quote on the widest left-side gap and its author on the widest
                // right-side gap. Adapted from the original quote swarm plugin.
                if (!canvas.quoteData) {
                    canvas.quoteData = (function() {
                        var F35 = {
                            A: [[1,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                            B: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[1,4]],
                            C: [[0,0],[1,0],[2,0],[0,1],[0,2],[0,3],[0,4],[1,4],[2,4]],
                            D: [[0,0],[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4]],
                            E: [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[0,3],[0,4],[1,4],[2,4]],
                            F: [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[0,3],[0,4]],
                            G: [[0,0],[1,0],[2,0],[0,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                            H: [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                            I: [[0,0],[1,0],[2,0],[1,1],[1,2],[1,3],[0,4],[1,4],[2,4]],
                            J: [[2,0],[2,1],[2,2],[0,3],[2,3],[1,4]],
                            K: [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[2,4]],
                            L: [[0,0],[0,1],[0,2],[0,3],[0,4],[1,4],[2,4]],
                            M: [[0,0],[2,0],[0,1],[1,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                            N: [[0,0],[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                            O: [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                            P: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[0,4]],
                            Q: [[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[1,4],[2,4]],
                            R: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[2,4]],
                            S: [[1,0],[2,0],[0,1],[1,2],[2,3],[0,4],[1,4]],
                            T: [[0,0],[1,0],[2,0],[1,1],[1,2],[1,3],[1,4]],
                            U: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                            V: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[1,4]],
                            W: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[1,3],[2,3],[0,4],[2,4]],
                            X: [[0,0],[2,0],[0,1],[2,1],[1,2],[0,3],[2,3],[0,4],[2,4]],
                            Y: [[0,0],[2,0],[0,1],[2,1],[1,2],[1,3],[1,4]],
                            Z: [[0,0],[1,0],[2,0],[2,1],[1,2],[0,3],[0,4],[1,4],[2,4]],
                            "0": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                            "1": [[1,0],[0,1],[1,1],[1,2],[1,3],[0,4],[1,4],[2,4]],
                            "2": [[0,0],[1,0],[2,0],[2,1],[0,2],[1,2],[2,2],[0,3],[0,4],[1,4],[2,4]],
                            "3": [[0,0],[1,0],[2,0],[2,1],[1,2],[2,2],[2,3],[0,4],[1,4],[2,4]],
                            "4": [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[2,3],[2,4]],
                            "5": [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[2,3],[0,4],[1,4]],
                            "6": [[1,0],[2,0],[0,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                            "7": [[0,0],[1,0],[2,0],[2,1],[1,2],[1,3],[1,4]],
                            "8": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                            "9": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[2,3],[0,4],[1,4]],
                            ".": [[1,4]],
                            ",": [[1,3],[0,4]],
                            "'": [[1,0],[1,1]],
                            "!": [[1,0],[1,1],[1,2],[1,4]],
                            "-": [[0,2],[1,2],[2,2]],
                            "/": [[2,0],[2,1],[1,2],[0,3],[0,4]],
                            ";": [[1,1],[1,3],[0,4]]
                        }
                        return { F35: F35 }
                    })()
                }

                var F8 = canvas.quoteData.F35
                var QUOTES8 = root.quotes8
                var T8 = 16000
                var lo8 = now / T8
                var cycle8 = Math.floor(lo8)
                var sd8 = cycle8 * 131.7
                var st8 = hash(sd8 + 9) * 0.2
                var t8 = (lo8 - cycle8 - st8) * T8
                var END8 = 12600
                if (t8 < 0 || t8 >= END8) {
                    root.animating8 = false
                    canvas.tick7 = 250
                    root.scheduleQuoteWake8(t8 < 0 ? -t8 : T8 - t8)
                    ctx.globalAlpha = 1.0
                    return
                }
                root.animating8 = true

                var al8 = Math.min(1, t8 / 400) * Math.min(1, (END8 - t8) / 400)
                var q8 = 0
                if (t8 >= 2800) q8 = 1
                else if (t8 > 2000) {
                    var u8 = (t8 - 2000) / 800
                    q8 = u8 * u8 * (3 - 2 * u8)
                }
                if (t8 > 9800) {
                    var r8a = Math.min(1, (t8 - 9800) / 800)
                    r8a = r8a * r8a * (3 - 2 * r8a)
                    q8 *= 1 - r8a
                }
                canvas.tick7 = (q8 >= 0.999 && t8 < 9800) ? 33 : 16

                var gaps8 = []
                for (var gi8 = 0; gi8 + 1 < runs.length; gi8++) {
                    var gx18 = root.layout.runRightEdge(runs[gi8].e)
                    var gx28 = root.layout.runLeftEdge(runs[gi8 + 1].s)
                    if (gx28 - gx18 < 10 || !isFinite(gx18) || !isFinite(gx28)) continue
                    gaps8.push({ x1: gx18, x2: gx28 })
                }
                if (gaps8.length === 0) {
                    root.animating8 = false
                    canvas.tick7 = 250
                    root.scheduleQuoteWake8(1000)
                    ctx.globalAlpha = 1.0
                    return
                }

                var iW18 = -1, iW28 = -1
                for (var wi8 = 0; wi8 < gaps8.length; wi8++) {
                    var ww8 = gaps8[wi8].x2 - gaps8[wi8].x1
                    if (iW18 < 0 || ww8 > gaps8[iW18].x2 - gaps8[iW18].x1) {
                        iW28 = iW18
                        iW18 = wi8
                    } else if (iW28 < 0 || ww8 > gaps8[iW28].x2 - gaps8[iW28].x1) {
                        iW28 = wi8
                    }
                }
                if (iW28 >= 0 && gaps8[iW28].x1 < gaps8[iW18].x1) {
                    var sw8i = iW18
                    iW18 = iW28
                    iW28 = sw8i
                }
                var gwA8 = gaps8[iW18].x2 - gaps8[iW18].x1
                var gwB8 = iW28 >= 0 ? gaps8[iW28].x2 - gaps8[iW28].x1 : 0

                var key8 = "q" + cycle8
                if (!canvas.quoteSwarm || canvas.quoteSwarm.key !== key8) {
                    var textGrid8 = function(str, colOff, rowOff, pts) {
                        for (var ci8 = 0; ci8 < str.length; ci8++) {
                            var L8 = F8[str.charAt(ci8)]
                            if (!L8) continue
                            for (var li8 = 0; li8 < L8.length; li8++)
                                pts.push([colOff + ci8 * 4 + L8[li8][0], rowOff + L8[li8][1]])
                        }
                    }
                    var cellFor8 = function(cols, rows2, gapw) {
                        var c8 = Math.min(3.2, (gapw - 24) / Math.max(1, cols - 1), (height - 6) / Math.max(1, rows2 - 1))
                        return c8 > 0 && isFinite(c8) ? c8 : 0
                    }
                    var fitCell8 = function(cols, rows2, gapw, minCell) {
                        var c8 = cellFor8(cols, rows2, gapw)
                        return c8 >= minCell ? c8 : 0
                    }

                    var qA8 = null, qB8 = null
                    var ONE_LINE_MAX_CHARS8 = 44
                    var MIN_ONE_LINE_CELL8 = 2.65
                    var MIN_TWO_LINE_CELL8 = 2.35
                    var TWO_LINE_ROWS8 = 11
                    var TWO_LINE_OFFSET8 = 6
                    var q08 = cycle8 % QUOTES8.length
                    for (var qi8 = 0; qi8 < QUOTES8.length && !qA8; qi8++) {
                        var Q8 = QUOTES8[(q08 + qi8) % QUOTES8.length]
                        var c18 = Q8.q.length * 4 - 1
                        if (Q8.q.length <= ONE_LINE_MAX_CHARS8 && fitCell8(c18, 5, gwA8, MIN_ONE_LINE_CELL8) > 0) {
                            qA8 = { pts: [], rows: 5, cols: c18 }
                            textGrid8(Q8.q, 0, 0, qA8.pts)
                        } else {
                            var ws8 = Q8.q.split(" "), best8 = -1, bl8 = 1e9
                            for (var si8 = 1; si8 < ws8.length; si8++) {
                                var m8 = Math.max(ws8.slice(0, si8).join(" ").length,
                                                  ws8.slice(si8).join(" ").length)
                                if (m8 < bl8) { bl8 = m8; best8 = si8 }
                            }
                            if (best8 > 0 && fitCell8(bl8 * 4 - 1, TWO_LINE_ROWS8, gwA8, MIN_TWO_LINE_CELL8) > 0) {
                                var s18 = ws8.slice(0, best8).join(" ")
                                var s28 = ws8.slice(best8).join(" ")
                                qA8 = { pts: [], rows: TWO_LINE_ROWS8, cols: bl8 * 4 - 1 }
                                textGrid8(s18, Math.round((bl8 - s18.length) * 2), 0, qA8.pts)
                                textGrid8(s28, Math.round((bl8 - s28.length) * 2), TWO_LINE_OFFSET8, qA8.pts)
                            }
                        }
                        if (qA8) {
                            var au8 = "-" + Q8.a
                            var ca8 = au8.length * 4 - 1
                            if (gwB8 > 0 && fitCell8(ca8, 5, gwB8, MIN_TWO_LINE_CELL8) > 0) {
                                qB8 = { pts: [], rows: 5, cols: ca8 }
                                textGrid8(au8, 0, 0, qB8.pts)
                            }
                        }
                    }

                    var alien8 = function(gapw, so8) {
                        var n8 = Math.min(6, Math.floor((gapw - 24) / 12))
                        if (n8 < 1) return null
                        var ap8 = []
                        for (var ag8 = 0; ag8 < n8; ag8++)
                            for (var ar8 = 0; ar8 < 5; ar8++)
                                for (var ac8 = 0; ac8 < 3; ac8++)
                                    if (hash(sd8 + so8 + ag8 * 37.3 + ar8 * 5.1 + ac8 * 1.7) < 0.42)
                                        ap8.push([ag8 * 4 + ac8, ar8])
                        return ap8.length ? { pts: ap8, rows: 5, cols: n8 * 4 - 1 } : null
                    }
                    if (!qA8) {
                        qA8 = alien8(gwA8, 61)
                        qB8 = gwB8 > 0 ? alien8(gwB8, 87) : null
                    }

                    var aM8 = [], aGC8 = [], aGR8 = [], aHF8 = [], aP18 = [], aF18 = [], aP28 = [], aF28 = []
                    var mk8 = function(gg8, m8k) {
                        if (!gg8) return
                        for (var di8 = 0; di8 < gg8.pts.length; di8++) {
                            var sp8 = (m8k * 4000 + di8) * 13.7 + sd8
                            aM8.push(m8k); aGC8.push(gg8.pts[di8][0]); aGR8.push(gg8.pts[di8][1])
                            aHF8.push(hash(sp8 + 5))
                            aP18.push(700 + 500 * hash(sp8 + 1)); aF18.push(6.283 * hash(sp8 + 2))
                            aP28.push(600 + 500 * hash(sp8 + 3)); aF28.push(6.283 * hash(sp8 + 4))
                        }
                    }
                    mk8(qA8, 0); mk8(qB8, 1)

                    var freeN8 = aM8.length ? Math.max(20, Math.min(40, Math.round(aM8.length * 0.25))) : 80
                    for (var fi8 = 0; fi8 < freeN8; fi8++) {
                        var sf8 = (9000 + fi8) * 13.7 + sd8
                        aM8.push(2); aGC8.push(0); aGR8.push(0)
                        aHF8.push(hash(sf8 + 5))
                        aP18.push(700 + 500 * hash(sf8 + 1)); aF18.push(6.283 * hash(sf8 + 2))
                        aP28.push(600 + 500 * hash(sf8 + 3)); aF28.push(6.283 * hash(sf8 + 4))
                    }

                    canvas.quoteSwarm = {
                        key: key8, n: aM8.length, m: aM8, gc: aGC8, gr: aGR8, hf: aHF8,
                        p1: aP18, f1: aF18, p2: aP28, f2: aF28,
                        px: new Array(aM8.length), py: new Array(aM8.length),
                        pv: new Array(aM8.length), pg: new Array(aM8.length),
                        pc: new Array(aM8.length),
                        colsA: qA8 ? qA8.cols : 1, rowsA: qA8 ? qA8.rows : 1,
                        colsB: qB8 ? qB8.cols : 1, rowsB: qB8 ? qB8.rows : 1,
                        hasA: !!qA8, hasB: !!qB8
                    }
                }

                var qs8 = canvas.quoteSwarm
                var geo8 = [null, null]
                var mkGeo8 = function(slot, gidx, cols, rows2, has8) {
                    if (gidx < 0 || !has8) return
                    var gp8 = gaps8[gidx]
                    var cl8 = Math.min(3.2, (gp8.x2 - gp8.x1 - 24) / Math.max(1, cols - 1),
                                       (height - 6) / Math.max(1, rows2 - 1))
                    if (cl8 < 1.9) return
                    geo8[slot] = { ox: (gp8.x1 + gp8.x2) / 2 - (cols - 1) * cl8 / 2,
                                   oy: cy - (rows2 - 1) * cl8 / 2, cell: cl8 }
                }
                mkGeo8(0, iW18, qs8.colsA, qs8.rowsA, qs8.hasA)
                mkGeo8(1, iW28, qs8.colsB, qs8.rowsB, qs8.hasB)

                var fx18 = gaps8[0].x1
                var fx28 = gaps8[gaps8.length - 1].x2
                var fw8 = fx28 - fx18
                var wy8 = (height / 2 - 5) * 0.9
                var hold8 = q8 >= 0.999
                var N8 = qs8.n
                var MM8 = qs8.m, GC8 = qs8.gc, GR8 = qs8.gr, HF8 = qs8.hf
                var P18 = qs8.p1, F18 = qs8.f1, P28 = qs8.p2, F28 = qs8.f2
                var PX8 = qs8.px, PY8 = qs8.py, PV8 = qs8.pv, PG8 = qs8.pg, PC8 = qs8.pc
                var gA8 = geo8[0], gB8 = geo8[1]

                for (var i8 = 0; i8 < N8; i8++) {
                    var m88 = MM8[i8]
                    var g88 = m88 === 0 ? gA8 : (m88 === 1 ? gB8 : null)
                    if (hold8 && g88) {
                        PX8[i8] = g88.ox + GC8[i8] * g88.cell + 0.4 * Math.sin(now / 240 + i8)
                        PY8[i8] = g88.oy + GR8[i8] * g88.cell + 0.4 * Math.cos(now / 300 + i8 * 1.7)
                        PV8[i8] = 1
                        PG8[i8] = g88.cell * 0.62
                        PC8[i8] = g88.cell * 0.30
                        continue
                    }
                    var px8 = fx18 + HF8[i8] * fw8 + 60 * Math.sin(now / P18[i8] + F18[i8])
                    var py8 = cy + wy8 * Math.sin(now / P28[i8] + F28[i8])
                    var rg8 = 2.4, rc8 = 1.05
                    if (g88 && q8 > 0) {
                        px8 += (g88.ox + GC8[i8] * g88.cell - px8) * q8
                        py8 += (g88.oy + GR8[i8] * g88.cell - py8) * q8
                        rg8 += (g88.cell * 0.62 - 2.4) * q8
                        rc8 += (g88.cell * 0.30 - 1.05) * q8
                    }

                    var vis8 = 0
                    for (var vg8 = 0; vg8 < gaps8.length; vg8++) {
                        if (px8 >= gaps8[vg8].x1 - 2 && px8 <= gaps8[vg8].x2 + 2) {
                            vis8 = Math.max(0, Math.min(1, Math.min(
                                    (px8 - gaps8[vg8].x1 + 2) / 6,
                                    (gaps8[vg8].x2 + 2 - px8) / 6)))
                            break
                        }
                    }
                    PX8[i8] = px8; PY8[i8] = py8; PV8[i8] = vis8; PG8[i8] = rg8; PC8[i8] = rc8
                }

                var drawR8
                ctx.fillStyle = seal
                ctx.globalAlpha = 0.30 * al8
                for (i8 = 0; i8 < N8; i8++)
                    if (PV8[i8] >= 0.999) { drawR8 = PG8[i8]; ctx.fillRect(PX8[i8] - drawR8, PY8[i8] - drawR8, drawR8 * 2, drawR8 * 2) }
                for (i8 = 0; i8 < N8; i8++)
                    if (PV8[i8] > 0.01 && PV8[i8] < 0.999) {
                        ctx.globalAlpha = 0.30 * al8 * PV8[i8]
                        drawR8 = PG8[i8]; ctx.fillRect(PX8[i8] - drawR8, PY8[i8] - drawR8, drawR8 * 2, drawR8 * 2)
                    }
                ctx.fillStyle = "#ffffff"
                ctx.globalAlpha = 0.92 * al8
                for (i8 = 0; i8 < N8; i8++)
                    if (PV8[i8] >= 0.999) { drawR8 = PC8[i8]; ctx.fillRect(PX8[i8] - drawR8, PY8[i8] - drawR8, drawR8 * 2, drawR8 * 2) }
                for (i8 = 0; i8 < N8; i8++)
                    if (PV8[i8] > 0.01 && PV8[i8] < 0.999) {
                        ctx.globalAlpha = 0.92 * al8 * PV8[i8]
                        drawR8 = PC8[i8]; ctx.fillRect(PX8[i8] - drawR8, PY8[i8] - drawR8, drawR8 * 2, drawR8 * 2)
                    }
                ctx.globalAlpha = 1.0
                return
            }

            if (root.mode === 7) {
                // ══ EVENT REACTOR: the bar reacts to the session ══
                // No loop, no schedule: dots appear only as impulses from real
                // events. Producers today:
                //   window open/close  -> subtle clock-side pulse in/out
                //   monitor focus      -> soft sweep on that bar only
                //   workspace/fullscreen/theme/config reload/notification/track
                //   DND/mute/Voxtype/update/pacman -> text swarm
                //   warning states     -> recurring text while true:
                //     OFFLINE, BATTERY, AI QUOTA, URGENT.
                // Everything decays; the timer stops when no pulse is alive.
                if (!canvas.swarmData) {
                    // 3×5 dot-matrix glyphs, built once (NOT per frame)
                    canvas.swarmData = { F35: {
                        A: [[1,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                        B: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[1,4]],
                        C: [[0,0],[1,0],[2,0],[0,1],[0,2],[0,3],[0,4],[1,4],[2,4]],
                        D: [[0,0],[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4]],
                        E: [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[0,3],[0,4],[1,4],[2,4]],
                        F: [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[0,3],[0,4]],
                        G: [[0,0],[1,0],[2,0],[0,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                        H: [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                        I: [[0,0],[1,0],[2,0],[1,1],[1,2],[1,3],[0,4],[1,4],[2,4]],
                        J: [[2,0],[2,1],[2,2],[0,3],[2,3],[1,4]],
                        K: [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[2,4]],
                        L: [[0,0],[0,1],[0,2],[0,3],[0,4],[1,4],[2,4]],
                        M: [[0,0],[2,0],[0,1],[1,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                        N: [[0,0],[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[2,4]],
                        O: [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                        P: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[0,4]],
                        Q: [[1,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[1,4],[2,4]],
                        R: [[0,0],[1,0],[0,1],[2,1],[0,2],[1,2],[0,3],[2,3],[0,4],[2,4]],
                        S: [[1,0],[2,0],[0,1],[1,2],[2,3],[0,4],[1,4]],
                        T: [[0,0],[1,0],[2,0],[1,1],[1,2],[1,3],[1,4]],
                        U: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                        V: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[1,4]],
                        W: [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[1,3],[2,3],[0,4],[2,4]],
                        X: [[0,0],[2,0],[0,1],[2,1],[1,2],[0,3],[2,3],[0,4],[2,4]],
                        Y: [[0,0],[2,0],[0,1],[2,1],[1,2],[1,3],[1,4]],
                        Z: [[0,0],[1,0],[2,0],[2,1],[1,2],[0,3],[0,4],[1,4],[2,4]],
                        "0": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                        "1": [[1,0],[0,1],[1,1],[1,2],[1,3],[0,4],[1,4],[2,4]],
                        "2": [[0,0],[1,0],[2,0],[2,1],[0,2],[1,2],[2,2],[0,3],[0,4],[1,4],[2,4]],
                        "3": [[0,0],[1,0],[2,0],[2,1],[1,2],[2,2],[2,3],[0,4],[1,4],[2,4]],
                        "4": [[0,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[2,3],[2,4]],
                        "5": [[0,0],[1,0],[2,0],[0,1],[0,2],[1,2],[2,3],[0,4],[1,4]],
                        "6": [[1,0],[2,0],[0,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                        "7": [[0,0],[1,0],[2,0],[2,1],[1,2],[1,3],[1,4]],
                        "8": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[0,3],[2,3],[0,4],[1,4],[2,4]],
                        "9": [[0,0],[1,0],[2,0],[0,1],[2,1],[0,2],[1,2],[2,2],[2,3],[0,4],[1,4]],
                        ".": [[1,4]],
                        ",": [[1,3],[0,4]],
                        "'": [[1,0],[1,1]],
                        "!": [[1,0],[1,1],[1,2],[1,4]],
                        "-": [[0,2],[1,2],[2,2]],
                        "/": [[2,0],[2,1],[1,2],[0,3],[0,4]],
                        ";": [[1,1],[1,3],[0,4]],
                        "<": [[2,0],[1,1],[0,2],[1,3],[2,4]]
                    } }
                }
                var gaps7 = []
                for (var gi = 0; gi + 1 < runs.length; gi++) {
                    var gx1 = root.layout.runRightEdge(runs[gi].e)
                    var gx2 = root.layout.runLeftEdge(runs[gi + 1].s)
                    if (gx2 - gx1 < 10 || !isFinite(gx1) || !isFinite(gx2)) continue
                    gaps7.push({ x1: gx1, x2: gx2 })
                }
                if (gaps7.length === 0) {
                    root.animating7 = false
                    canvas.tick7 = 250
                    ctx.globalAlpha = 1.0
                    return
                }
                var fx1 = gaps7[0].x1
                var fx2 = gaps7[gaps7.length - 1].x2
                var iW7 = 0
                for (var wi7 = 1; wi7 < gaps7.length; wi7++)
                    if (gaps7[wi7].x2 - gaps7[wi7].x1 > gaps7[iW7].x2 - gaps7[iW7].x1) iW7 = wi7
                var wcx = (gaps7[iW7].x1 + gaps7[iW7].x2) / 2

                var vis7 = function(px) {
                    for (var vg = 0; vg < gaps7.length; vg++)
                        if (px >= gaps7[vg].x1 - 2 && px <= gaps7[vg].x2 + 2)
                            return Math.max(0, Math.min(1, Math.min(
                                    (px - gaps7[vg].x1 + 2) / 6,
                                    (gaps7[vg].x2 + 2 - px) / 6)))
                    return 0
                }
                var dot7 = function(px, py, rg, rc, a) {
                    if (a <= 0.01) return
                    var v = vis7(px)
                    if (v <= 0.01) return
                    ctx.globalAlpha = 0.30 * a * v; ctx.fillStyle = seal
                    ctx.fillRect(px - rg, py - rg, rg * 2, rg * 2)
                    ctx.globalAlpha = 0.92 * a * v; ctx.fillStyle = "#ffffff"
                    ctx.fillRect(px - rc, py - rc, rc * 2, rc * 2)
                }
                var clockGapPair7 = function() {
                    var mid = width / 2
                    var li = -1, ri = -1
                    for (var ci7 = 0; ci7 < gaps7.length; ci7++) {
                        if (gaps7[ci7].x2 <= mid && (li < 0 || gaps7[ci7].x2 > gaps7[li].x2)) li = ci7
                        if (gaps7[ci7].x1 >= mid && (ri < 0 || gaps7[ci7].x1 < gaps7[ri].x1)) ri = ci7
                    }
                    if (li < 0 && ri < 0) return [iW7, iW7]
                    if (li < 0) li = ri
                    if (ri < 0) ri = li
                    return [li, ri]
                }
                var sweep7 = function(p, age, life, dir, gain, cnt) {
                    // murmuration, not a line: the flock moves as ONE body
                    // along a slow serpentine, breathing wider and tighter,
                    // while each dot only drifts gently around the moving
                    // centre and twinkles — that coherence is what makes it
                    // read as a swarm instead of scattered noise
                    var sdp = p.t % 86400000
                    var fade = age > life - 600 ? (life - age) / 600 : 1
                    var span = fx2 - fx1 + 120
                    var amp = height / 2 - 8
                    var breath = 1 + 0.35 * Math.sin(now / 1100 + sdp)       // flock breathes
                    var gy = amp * 0.55 * Math.sin(now / 1400 + sdp * 1.7)   // shared undulation
                    for (var i = 0; i < cnt; i++) {
                        var dly = hash(sdp + i * 7 + 1) * 900
                        var a2 = age - dly
                        if (a2 < 0) continue
                        var e = a2 / life
                        if (e > 1) continue
                        e += 0.025 * Math.sin(now / 480 + 6.283 * hash(sdp + i * 7 + 2))  // gentle surge
                        var gx = dir > 0 ? fx1 - 60 + e * span : fx2 + 60 - e * span
                        var xi = gx + (hash(sdp + i * 7 + 3) - 0.5) * 110 * breath
                                 + 10 * Math.sin(now / (900 + 500 * hash(sdp + i * 7 + 4))
                                                 + 6.283 * hash(sdp + i * 7 + 5))
                        var yi = cy + gy * (0.6 + 0.4 * hash(sdp + i * 7 + 2))
                                 + (hash(sdp + i * 7 + 6) - 0.5) * amp * breath * 0.5
                                 + 3 * Math.sin(now / (600 + 300 * hash(sdp + i * 7 + 4)) + i)
                        var sz = 1.6 + hash(sdp + i * 7 + 5) * 1.2
                        var tw = 0.8 + 0.2 * Math.sin(now / 350 + i * 1.9)   // twinkle
                        dot7(xi, yi, sz, sz * 0.45,
                             gain * fade * tw * Math.min(1, a2 / 350))
                    }
                }

                // ── ambient pool: one set of particles drifting through the gaps;
                //    on an event these same particles reorganise into the text ──
                var ps7 = root.pulses
                var N9 = 110
                var driftPos = function(i) {
                    var r1 = hash(i * 3 + 1), r2 = hash(i * 3 + 2), r3 = hash(i * 3 + 3)
                    var bf = hash(i * 5 + 7)
                    return { x: fx1 + bf * (fx2 - fx1)
                                + 16 * Math.sin(now / (1700 + 900 * r1) + 6.283 * r2),
                             y: cy + (height / 2 - 5) * 0.78 * Math.sin(now / (1300 + 800 * r3) + 6.283 * r1) }
                }
                var paintField = function(fromIdx, alpha) {
                    if (alpha <= 0.01) return
                    for (var fi = fromIdx; fi < N9; fi++) {
                        var d = driftPos(fi)
                        var tw = 0.55 + 0.30 * Math.sin(now / 640 + fi * 1.3)
                        dot7(d.x, d.y, 1.3, 0.5, alpha * tw)
                    }
                }
                var hasText7 = false
                for (var ht = 0; ht < ps7.length; ht++)
                    if (ps7[ht].k === "text" && now - ps7[ht].t < root.pulseLife7(ps7[ht])) hasText7 = true
                if (!hasText7) canvas.recruited = 0
                if (ps7.length === 0) {
                    if (root.ambientField7) {
                        canvas.fieldFade += (1.0 - canvas.fieldFade) * 0.06
                        canvas.recruited = 0
                        paintField(0, 0.5 * canvas.fieldFade)
                        root.animating7 = true
                        canvas.tick7 = 64            // slow drift, ~15 fps
                        ctx.globalAlpha = 1.0
                        return
                    }
                    root.animating7 = false
                    canvas.tick7 = 250
                    ctx.globalAlpha = 1.0
                    return
                }
                if (root.ambientField7) {
                    // recruited particles are drawn by the text swarm below; the rest
                    // keep drifting, dimmed while a message is on screen
                    canvas.fieldFade += ((hasText7 ? 0.4 : 1.0) - canvas.fieldFade) * 0.06
                    paintField(canvas.recruited, 0.5 * canvas.fieldFade)
                }

                var alive7 = false
                var livePs7 = []
                for (var pi7 = 0; pi7 < ps7.length; pi7++) {
                    var p = ps7[pi7]
                    var age = now - p.t
                    if (age < root.pulseLife7(p)) livePs7.push(p)
                    var sd = p.t % 86400000
                    if (p.k === "monsweep") {
                        var lifeM = p.life || 3400
                        if (age >= lifeM) continue
                        alive7 = true; sweep7(p, age, lifeM, p.d, p.gain || 0.55, p.count || 30)
                    } else if (p.k === "win") {
                        if (age >= 1600) continue
                        alive7 = true
                        var tw7 = age / 1600
                        var ew7 = tw7 * tw7 * (3 - 2 * tw7)
                        var aw7 = Math.sin(Math.min(1, tw7) * Math.PI)
                        var gp7 = clockGapPair7()
                        for (var side7 = 0; side7 < 2; side7++) {
                            var wg7 = gaps7[gp7[side7]]
                            if (!wg7) continue
                            var sg7 = side7 === 0 ? -1 : 1
                            var near7 = sg7 < 0 ? wg7.x2 - 8 : wg7.x1 + 8
                            var travel7 = Math.min(34, Math.max(8, (wg7.x2 - wg7.x1) * 0.45))
                            var far7 = sg7 < 0 ? Math.max(wg7.x1 + 8, near7 - travel7)
                                                : Math.min(wg7.x2 - 8, near7 + travel7)
                            var pw7 = p.d > 0 ? ew7 : 1 - ew7
                            for (var wi7p = 0; wi7p < 14; wi7p++) {
                                var lag7 = hash(sd + side7 * 100 + wi7p * 9 + 1) * 0.28
                                var u7p = Math.max(0, Math.min(1, pw7 - lag7 + 0.12))
                                var px7p = near7 + (far7 - near7) * u7p
                                    + (hash(sd + side7 * 100 + wi7p * 9 + 2) - 0.5) * 7
                                var py7p = cy + (hash(sd + side7 * 100 + wi7p * 9 + 3) - 0.5) * (height - 10) * 0.68
                                    + 2 * Math.sin(now / 360 + wi7p)
                                var a7p = aw7 * (0.45 + 0.45 * hash(sd + side7 * 100 + wi7p * 9 + 4))
                                dot7(px7p, py7p, 1.8, 0.8, a7p)
                            }
                        }
                    } else if (p.k === "text") {
                        // ── the swarm flies in, condenses into the message
                        //    on the widest gap plus optional secondary source, holds,
                        //    then flies on and dissolves ──
                        if (age >= p.life) continue
                        alive7 = true
                        if (!p.grid) {
                            // built once per pulse: wrap + layout dot targets
                            var F = canvas.swarmData.F35
                            var mkPts = function(str, colOff, rowOff, pts, m) {
                                for (var ci = 0; ci < str.length; ci++) {
                                    var L = F[str.charAt(ci)]
                                    if (!L) continue
                                    for (var li = 0; li < L.length; li++)
                                        pts.push([colOff + ci * 4 + L[li][0], rowOff + L[li][1], m])
                                }
                            }
                            var hasRightText7 = p.r !== ""
                            var i1 = 0, i2 = -1
                            for (var wj = 1; wj < gaps7.length; wj++)
                                if (gaps7[wj].x2 - gaps7[wj].x1 > gaps7[i1].x2 - gaps7[i1].x1) { i2 = i1; i1 = wj }
                                else if (i2 < 0 || gaps7[wj].x2 - gaps7[wj].x1 > gaps7[i2].x2 - gaps7[i2].x1) i2 = wj
                            if (!hasRightText7) i2 = -1
                            else if (i2 >= 0 && gaps7[i2].x1 < gaps7[i1].x1) {
                                var sw7 = i1
                                i1 = i2
                                i2 = sw7
                            }
                            var gwA7 = gaps7[i1].x2 - gaps7[i1].x1
                            var mc = Math.max(3, Math.floor(((gwA7 - 24) / 2.0 + 1) / 4))
                            var l1 = p.l, l2 = ""
                            if (p.l.length > mc || p.two) {  // balanced wrap, hard cap
                                var cut = p.l.lastIndexOf(" ", Math.min(mc, Math.ceil(p.l.length / 2) + 6))
                                if (cut < 4) cut = Math.min(mc, Math.ceil(p.l.length / 2))
                                l1 = p.l.substring(0, cut).trim().substring(0, mc)
                                l2 = p.l.substring(cut).trim().substring(0, mc)
                            }
                            var mxl = Math.max(l1.length, l2.length)
                            var pts7t = []
                            mkPts(l1, Math.round((mxl - l1.length) * 2), 0, pts7t, 0)
                            if (l2) mkPts(l2, Math.round((mxl - l2.length) * 2), 7, pts7t, 0)
                            var colsB7 = 1
                            if (i2 >= 0 && hasRightText7) {
                                var mcB = Math.max(3, Math.floor(((gaps7[i2].x2 - gaps7[i2].x1 - 24) / 2.0 + 1) / 4))
                                var rr = p.r.substring(0, mcB)
                                colsB7 = Math.max(1, rr.length * 4 - 1)
                                mkPts(rr, 0, 0, pts7t, 1)
                            }
                            p.grid = { pts: pts7t, colsA: Math.max(1, mxl * 4 - 1),
                                       rowsA: l2 ? 12 : 5, colsB: colsB7, rowsB: 5 }
                        }
                        var G = p.grid
                        // geometry per frame (gaps breathe with the layout)
                        var hasRightGeo7 = p.r !== ""
                        var j1 = 0, j2 = -1
                        for (var wk = 1; wk < gaps7.length; wk++)
                            if (gaps7[wk].x2 - gaps7[wk].x1 > gaps7[j1].x2 - gaps7[j1].x1) { j2 = j1; j1 = wk }
                            else if (j2 < 0 || gaps7[wk].x2 - gaps7[wk].x1 > gaps7[j2].x2 - gaps7[j2].x1) j2 = wk
                        if (!hasRightGeo7) j2 = -1
                        else if (j2 >= 0 && gaps7[j2].x1 < gaps7[j1].x1) {
                            var swg7 = j1
                            j1 = j2
                            j2 = swg7
                        }
                        var geoT = [null, null]
                        var mg7 = function(slot, gp, cols, rows2) {
                            if (!gp) return
                            var cl = Math.min(cols <= 11 ? 5.4 : 3.2,
                                              (gp.x2 - gp.x1 - 24) / Math.max(1, cols - 1),
                                              (height - 6) / (rows2 - 1))
                            if (cl < 1.8) return
                            geoT[slot] = { ox: (gp.x1 + gp.x2) / 2 - (cols - 1) * cl / 2,
                                           oy: cy - (rows2 - 1) * cl / 2, cell: cl }
                        }
                        mg7(0, gaps7[j1], G.colsA, G.rowsA)
                        mg7(1, j2 >= 0 ? gaps7[j2] : null, G.colsB, G.rowsB)
                        // envelope: fly-in → snap → hold → release → fly-out
                        var qT = 0
                        if (age >= p.s1) qT = 1
                        else if (age > p.s0) { var uT = (age - p.s0) / (p.s1 - p.s0); qT = uT * uT * (3 - 2 * uT) }
                        if (age > p.r0) { var rT = Math.min(1, (age - p.r0) / (p.r1 - p.r0)); rT = rT * rT * (3 - 2 * rT); qT *= 1 - rT }
                        var alT = Math.min(1, age / 450) * Math.min(1, (p.life - age) / 450)
                        // warnings throb while held — the whole text breathes
                        // in brightness and size as one body
                        var wA = 1, wS = 1
                        if (p.w && qT > 0.9) {
                            wA = 0.78 + 0.28 * Math.sin(now / 280)
                            wS = 1 + 0.15 * Math.sin(now / 280)
                        }
                        var enter7 = Math.max(0, 1 - age / p.s0); enter7 = enter7 * enter7
                        var leave7 = age > p.r1 ? (age - p.r1) / (p.life - p.r1) : 0; leave7 = leave7 * leave7
                        var shift7 = p.d * (fx2 - fx1) * 0.45 * (leave7 - enter7)
                        var sdT = p.t % 86400000
                        var Ptot = G.pts.length
                        var af7 = root.ambientField7
                        // with the field on, the SAME pool particles form the text
                        // (subsampled if the message has more dots than the pool);
                        // with it off, the original fly-in from the edge is used
                        var step7 = (af7 && Ptot > N9) ? Math.ceil(Ptot / N9) : 1
                        var jj7 = 0
                        for (var ti = 0; ti < Ptot; ti += step7) {
                            var ptT = G.pts[ti]
                            var gT = geoT[ptT[2]]
                            var pxT, pyT, rgT, rcT
                            if (af7) {
                                var d07 = driftPos(jj7)          // start = pool drift
                                pxT = d07.x; pyT = d07.y; rgT = 1.3; rcT = 0.5
                            } else {
                                pxT = fx1 + hash(sdT + ti * 7 + 5) * (fx2 - fx1) + shift7
                                      + 12 * Math.sin(now / (800 + 500 * hash(sdT + ti * 7 + 1))
                                                      + 6.283 * hash(sdT + ti * 7 + 2))
                                pyT = cy + (height / 2 - 6) * 0.85
                                      * Math.sin(now / (600 + 500 * hash(sdT + ti * 7 + 3))
                                                 + 6.283 * hash(sdT + ti * 7 + 4))
                                rgT = 2.2; rcT = 1.0
                            }
                            if (gT && qT > 0) {
                                pxT += (gT.ox + ptT[0] * gT.cell - pxT) * qT
                                pyT += (gT.oy + ptT[1] * gT.cell - pyT) * qT
                                if (qT > 0.98) {         // the held text breathes
                                    pxT += 0.4 * Math.sin(now / 240 + jj7)
                                    pyT += 0.4 * Math.cos(now / 300 + jj7 * 1.7)
                                }
                                rgT += (gT.cell * 0.62 - rgT) * qT
                                rcT += (gT.cell * 0.30 - rcT) * qT
                            }
                            dot7(pxT, pyT, rgT * wS, rcT * wS, alT * wA)
                            jj7++
                        }
                        canvas.recruited = af7 ? jj7 : 0
                    }
                }
                if (livePs7.length !== ps7.length) root.pulses = livePs7
                root.animating7 = root.ambientField7 ? true : alive7
                canvas.tick7 = alive7 ? 16 : (root.ambientField7 ? 64 : 250)
                ctx.globalAlpha = 1.0
                return
            }

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

                } else if (root.mode === 3) {
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
                } else if (root.mode === 4) {
                    // ══ SPARK GAP (Bolt2): the pill edges are electrodes ══
                    // Tiny arcs crackle sporadically at the edges — barely-there
                    // life, no rails, no orbs. Every several seconds the gap
                    // breaks down and ONE full bolt arcs across as the payoff,
                    // flickering twice before it dies.
                    var aS  = Math.min(height * 0.30, 5.5)

                    // ── micro sparks: short-lived arcs at random edge spots ──
                    // time is sliced into slots; each slot rolls a few spark
                    // candidates per gap (deterministic — no state kept)
                    var slot = Math.floor(now / 300)
                    var sIn  = (now % 300) / 300            // 0..1 inside the slot
                    for (var sk = 0; sk < 2; sk++) {
                        var sps = slot * 77.7 + g * 13.3 + sk * 311.1
                        if (hash(sps) > 0.32) continue        // most slots stay quiet
                        var life = 1 - sIn                    // quick fade within the slot
                        if (life <= 0) continue
                        var left = hash(sps + 1) < 0.5
                        var ex0  = left ? x1 : x2
                        var dir  = left ? 1 : -1
                        var ey0  = cy + (hash(sps + 2) - 0.5) * height * 0.45
                        var sln  = 4 + hash(sps + 3) * 6      // 4..10 px reach
                        ctx.lineJoin = "round"
                        ctx.beginPath(); ctx.moveTo(ex0, ey0)
                        for (var sj = 1; sj <= 3; sj++) {
                            ctx.lineTo(ex0 + dir * sln * (sj / 3),
                                       ey0 + (hash(sps + 4 + sj) - 0.5) * 4)
                        }
                        var fl4 = 0.6 + 0.4 * Math.sin(now / 23 + sps)
                        ctx.globalAlpha = 0.30 * life * fl4; ctx.strokeStyle = seal;      ctx.lineWidth = 1.6; ctx.stroke()
                        ctx.globalAlpha = 0.75 * life * fl4; ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 0.7; ctx.stroke()
                        // tiny hot point on the electrode
                        ctx.globalAlpha = 0.55 * life
                        ctx.fillStyle   = "#ffffff"
                        ctx.beginPath(); ctx.arc(ex0, ey0, 0.9, 0, Math.PI * 2); ctx.fill()
                    }

                    // ── breakdown: one full arc bridges the gap, then darkness ──
                    var T4  = 4000
                    var lo4 = now / T4 + g * 0.37
                    var ph4 = lo4 - Math.floor(lo4)
                    var sd4 = Math.floor(lo4) * 131.7 + g * 53.3
                    var st4 = 0.10 + hash(sd4 + 99) * 0.75    // irregular breakdown moment
                    var s4  = (ph4 - st4) * T4                // ms since breakdown
                    if (s4 >= 0 && s4 < 340) {
                        // double-flicker envelope: strike, dip, weaker restrike, die
                        var b4 = 0
                        if      (s4 <  90) b4 = 1.0
                        else if (s4 < 150) b4 = 0.25
                        else if (s4 < 230) b4 = 0.7
                        else               b4 = 0.7 * (1 - (s4 - 230) / 110)
                        b4 *= 0.82 + 0.18 * Math.sin(now / 21)

                        var segs = Math.max(4, Math.min(16, Math.round(gw / 22)))
                        ctx.lineJoin = "round"
                        ctx.beginPath(); ctx.moveTo(x1, cy)
                        for (var i = 1; i <= segs; i++) {
                            ctx.lineTo(x1 + (i / segs) * gw,
                                       (i === segs) ? cy : cy + (hash(sd4 + i) - 0.5) * 2 * aS)
                        }
                        ctx.globalAlpha = 0.42 * b4; ctx.strokeStyle = seal;      ctx.lineWidth = 3.4; ctx.stroke()
                        ctx.globalAlpha = 0.95 * b4; ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.2; ctx.stroke()

                        // electrode blooms while the arc burns
                        var ebr = 6 + b4 * 3
                        var eps = [ x1, x2 ]
                        for (var eb = 0; eb < 2; eb++) {
                            var eg4 = ctx.createRadialGradient(eps[eb], cy, 0, eps[eb], cy, ebr)
                            eg4.addColorStop(0.0, rgba(0.50 * b4))
                            eg4.addColorStop(1.0, rgba(0.0))
                            ctx.globalAlpha = 1.0; ctx.fillStyle = eg4
                            ctx.beginPath(); ctx.arc(eps[eb], cy, ebr, 0, Math.PI * 2); ctx.fill()
                        }
                    }
                } else if (root.mode === 5) {
                    // ══ TRANSFER (Stream2): the pills exchange energy, drop by drop ══
                    // A droplet of light grows on the left pill edge, detaches,
                    // glides across and is absorbed by the right edge with a
                    // tiny flash. Edge-anchored like Spark Gap; flow stays
                    // left → right like Stream. Between drops: nothing.
                    var T5  = 3200
                    var lo5 = now / T5 + g * 0.41
                    var ph5 = lo5 - Math.floor(lo5)
                    var sd5 = Math.floor(lo5) * 131.7 + g * 53.3
                    var st5 = hash(sd5 + 9) * 0.22            // irregular start
                    var p5  = (ph5 - st5) / 0.74              // the whole hand-over
                    if (p5 >= 0 && p5 <= 1) {
                        var R5 = 2.4                           // droplet core radius
                        var dx5, sc5 = 1.0
                        if (p5 < 0.40) {
                            // growing on the left edge, swelling out of the pill
                            dx5 = x1
                            sc5 = p5 / 0.40
                        } else if (p5 < 0.85) {
                            // detached: glide over, eased — slow exit, fast arrival
                            var u5 = (p5 - 0.40) / 0.45
                            u5  = u5 * u5 * (3 - 2 * u5)       // smoothstep
                            dx5 = x1 + u5 * gw
                        } else {
                            dx5 = -1                            // absorbed — flash phase below
                        }

                        if (dx5 >= 0) {
                            // short fading trail while gliding
                            if (p5 >= 0.40 && dx5 > x1 + 4) {
                                var tt5 = ctx.createLinearGradient(dx5 - 14, 0, dx5, 0)
                                tt5.addColorStop(0.0, rgba(0.0))
                                tt5.addColorStop(1.0, rgba(0.35))
                                ctx.globalAlpha = 1.0; ctx.strokeStyle = tt5; ctx.lineWidth = 1.4
                                ctx.beginPath(); ctx.moveTo(Math.max(x1, dx5 - 14), cy)
                                ctx.lineTo(dx5, cy); ctx.stroke()
                            }
                            // the droplet: seal bloom + white core, breathing slightly
                            var br5 = 0.92 + 0.08 * Math.sin(now / 130)
                            var bg5 = ctx.createRadialGradient(dx5, cy, 0, dx5, cy, R5 * 2.6 * sc5 * br5)
                            bg5.addColorStop(0.0, rgba(0.55 * sc5))
                            bg5.addColorStop(1.0, rgba(0.0))
                            ctx.globalAlpha = 1.0; ctx.fillStyle = bg5
                            ctx.beginPath(); ctx.arc(dx5, cy, R5 * 2.6 * sc5 * br5, 0, Math.PI * 2); ctx.fill()
                            ctx.globalAlpha = 0.92 * sc5; ctx.fillStyle = "#ffffff"
                            ctx.beginPath(); ctx.arc(dx5, cy, R5 * 0.7 * sc5, 0, Math.PI * 2); ctx.fill()
                        } else {
                            // absorbed: quick flash on the right edge, swallowed by the pill
                            var fb5 = 1 - (p5 - 0.85) / 0.15
                            var fg5 = ctx.createRadialGradient(x2, cy, 0, x2, cy, 8)
                            fg5.addColorStop(0.0, rgba(0.60 * fb5))
                            fg5.addColorStop(1.0, rgba(0.0))
                            ctx.globalAlpha = 1.0; ctx.fillStyle = fg5
                            ctx.beginPath(); ctx.arc(x2, cy, 8, 0, Math.PI * 2); ctx.fill()
                            ctx.globalAlpha = 0.9 * fb5; ctx.fillStyle = "#ffffff"
                            ctx.beginPath(); ctx.arc(x2, cy, 1.2 * fb5, 0, Math.PI * 2); ctx.fill()
                        }
                    }
                } else if (root.mode === 6) {
                    // ══ COLLIDER (Surge2): two particles smash mid-gap ══
                    // Surge's converge-DNA, but with punch: two bright points
                    // accelerate from the pill edges, collide in the middle —
                    // impact flash, debris sparks fly off and burn out. Then
                    // darkness until the next shot.
                    var T6  = 3800
                    var lo6 = now / T6 + g * 0.31
                    var ph6 = lo6 - Math.floor(lo6)
                    var sd6 = Math.floor(lo6) * 131.7 + g * 53.3
                    var st6 = hash(sd6 + 9) * 0.5              // irregular shot moment
                    var s6  = (ph6 - st6) * T6                 // ms since launch
                    if (s6 >= 0 && s6 < 1180) {
                        var mid6 = (x1 + x2) / 2
                        var IN6  = 580                         // in-flight time
                        if (s6 < IN6) {
                            // approach: accelerating heads with motion-blur trails
                            var u6  = (s6 / IN6); u6 = u6 * u6
                            var xs6 = [ x1 + u6 * (mid6 - x1), x2 - u6 * (x2 - mid6) ]
                            for (var c6 = 0; c6 < 2; c6++) {
                                var hx6 = xs6[c6]
                                var bk6 = (c6 === 0 ? -1 : 1) * (8 + u6 * 14)   // trail length grows with speed
                                var tg6 = ctx.createLinearGradient(hx6 + bk6, 0, hx6, 0)
                                tg6.addColorStop(0.0, rgba(0.0))
                                tg6.addColorStop(1.0, rgba(0.45))
                                ctx.globalAlpha = 1.0; ctx.strokeStyle = tg6; ctx.lineWidth = 1.6
                                ctx.beginPath(); ctx.moveTo(hx6 + bk6, cy); ctx.lineTo(hx6, cy); ctx.stroke()
                                var hg6 = ctx.createRadialGradient(hx6, cy, 0, hx6, cy, 4.5)
                                hg6.addColorStop(0.0, rgba(0.50))
                                hg6.addColorStop(1.0, rgba(0.0))
                                ctx.fillStyle = hg6
                                ctx.beginPath(); ctx.arc(hx6, cy, 4.5, 0, Math.PI * 2); ctx.fill()
                                ctx.globalAlpha = 0.95; ctx.fillStyle = "#ffffff"
                                ctx.beginPath(); ctx.arc(hx6, cy, 1.5, 0, Math.PI * 2); ctx.fill()
                            }
                        } else {
                            // impact: flash + debris sparks flying out, burning up
                            var t6  = (s6 - IN6) / 600          // 0..1 through the aftermath
                            var fl6 = Math.pow(1 - t6, 1.6)
                            var fr6 = 5 + t6 * 9                // bloom expands as it dies
                            var ig6 = ctx.createRadialGradient(mid6, cy, 0, mid6, cy, fr6)
                            ig6.addColorStop(0.0, rgba(0.60 * fl6))
                            ig6.addColorStop(1.0, rgba(0.0))
                            ctx.globalAlpha = 1.0; ctx.fillStyle = ig6
                            ctx.beginPath(); ctx.arc(mid6, cy, fr6, 0, Math.PI * 2); ctx.fill()
                            if (t6 < 0.25) {
                                ctx.globalAlpha = 0.95 * (1 - t6 / 0.25); ctx.fillStyle = "#ffffff"
                                ctx.beginPath(); ctx.arc(mid6, cy, 1.8, 0, Math.PI * 2); ctx.fill()
                            }
                            // debris: short spark shards, decelerating outward
                            var ez6 = 1 - Math.pow(1 - t6, 2)   // ease-out travel
                            ctx.lineJoin = "round"
                            for (var k6 = 0; k6 < 5; k6++) {
                                var an6 = (hash(sd6 + 30 + k6) - 0.5) * 2.4
                                         + (k6 % 2 === 0 ? 0 : Math.PI)        // both directions
                                var dd6 = (8 + hash(sd6 + 40 + k6) * 14) * ez6
                                var sxa = mid6 + Math.cos(an6) * dd6
                                var sya = cy   + Math.sin(an6) * dd6 * 0.55    // squashed into the bar
                                var sxb = sxa + Math.cos(an6) * 3.5
                                var syb = sya + Math.sin(an6) * 3.5 * 0.55
                                ctx.globalAlpha = 0.75 * fl6
                                ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 0.8
                                ctx.beginPath(); ctx.moveTo(sxa, sya); ctx.lineTo(sxb, syb); ctx.stroke()
                            }
                        }
                    }
                }

                ctx.restore()
            }

            ctx.globalAlpha = 1.0
        }
    }
}
