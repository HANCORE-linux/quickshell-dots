import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// AI usage panel: shows Claude Code, OpenAI Codex, and OpenCode usage and lets the user
// switch which tool's icon the bar pill displays (root.aiTool). Opened from the
// combined AI pill (ClaudeWidget). Reads the same caches the bar widget reads.
PanelWindow {
    id: aiPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-ai-usage"

    readonly property int barBottom: 35
    readonly property int gap: 8

    // ── usage data: rendered from root.ai* — the single shared parse in Theme.qml
    //    that the bar pill uses too, so the two views can never drift apart. ──
    readonly property int    clPct5h:     root.aiClPct5h
    readonly property int    clPct7d:     root.aiClPct7d
    readonly property int    clReset5hTs: root.aiClReset5hTs
    readonly property int    clReset7dTs: root.aiClReset7dTs
    readonly property string clTokens:    root.aiClTokens
    readonly property string clRate:      root.aiClRate
    readonly property int    clToday:     root.aiClToday
    readonly property bool   clFresh:     root.aiClFresh
    readonly property bool   clHas:       root.aiClHas

    readonly property int    cxPct5h:     root.aiCxPct5h
    readonly property int    cxPct7d:     root.aiCxPct7d
    readonly property int    cxReset5hTs: root.aiCxReset5hTs
    readonly property int    cxReset7dTs: root.aiCxReset7dTs
    readonly property string cxPlan:      root.aiCxPlan
    readonly property string cxTokens:    root.aiCxTokens
    readonly property string cxRate:      root.aiCxRate
    readonly property int    cxToday:     root.aiCxToday
    readonly property bool   cxFresh:     root.aiCxFresh
    readonly property bool   cxHas:       root.aiCxHas

    readonly property int    ocPct5h:     root.aiOcPct5h
    readonly property int    ocPct7d:     root.aiOcPct7d
    readonly property string ocPlan:      root.aiOcPlan
    readonly property string ocTokens:    root.aiOcTokens
    readonly property string ocRate:      root.aiOcRate
    readonly property string ocModel:     root.aiOcModel
    readonly property int    ocToday:     root.aiOcToday
    readonly property bool   ocFresh:     root.aiOcFresh
    readonly property bool   ocHas:       root.aiOcHas
    readonly property var    ocModels:    root.aiOcModels
    readonly property bool   showClaude:  root.aiTool === "claude"
    readonly property bool   showCodex:   root.aiTool === "codex"
    readonly property bool   showOpenCode: root.aiTool === "opencode"
    readonly property bool   showOllama:  root.aiTool === "ollama"
    readonly property var    olInstalled: root.ollamaInstalled
    readonly property var    olActive:    root.ollamaActive

    function olFmtSize(bytes) {
        if (!bytes) return ""
        var gb = bytes / 1e9
        return gb >= 1 ? gb.toFixed(1) + " GB" : (bytes / 1e6).toFixed(0) + " MB"
    }
    function olTotalSize() {
        var total = 0
        for (var i = 0; i < olInstalled.length; i++) total += (olInstalled[i].size || 0)
        return total > 0 ? olFmtSize(total) : ""
    }
    function olFmtUntil(iso) {
        if (!iso) return ""
        var then = new Date(iso).getTime()
        if (isNaN(then)) return ""
        var mins = Math.round((then - Date.now()) / 60000)
        if (mins <= 0) return "expiring"
        if (mins < 60) return mins + "m left"
        return Math.round(mins / 60) + "h left"
    }

    // ── Load a model on demand (POST /api/generate with an empty prompt —
    //    per Ollama's API, this loads the model into memory without
    //    generating text). Applies the current keep_alive/num_ctx pills. ──
    property string loadingModel: ""
    function keepAliveValue() {
        return root.ollamaConfig.keepAlive === "inf" ? -1 : root.ollamaConfig.keepAlive
    }
    Process {
        id: loadProc
        command: []
        onRunningChanged: if (!running) aiPanel.loadingModel = ""
    }
    function loadModel(name) {
        if (!name || aiPanel.loadingModel !== "") return
        var body = { model: name, prompt: "", keep_alive: aiPanel.keepAliveValue() }
        if (root.ollamaConfig.numCtx !== "auto")
            body.options = { num_ctx: parseInt(root.ollamaConfig.numCtx) }
        aiPanel.loadingModel = name
        loadProc.command = ["curl", "-s", "-X", "POST", root.ollamaConfig.host + "/api/generate",
                             "-d", JSON.stringify(body)]
        loadProc.running = false; loadProc.running = true
    }

    // ── Pull a new model (POST /api/pull, streamed NDJSON progress) ──
    property string pullInput: ""
    readonly property bool pullValid: /^[a-zA-Z0-9_.-]+(\/[a-zA-Z0-9_.-]+)?(:[a-zA-Z0-9_.-]+)?$/.test(pullInput.trim())
    property bool pulling: false
    property real pullFraction: 0
    property string pullStatus: ""
    property string pullError: ""

    Process {
        id: pullProc
        command: []
        onRunningChanged: if (!running) aiPanel.pulling = false
        stdout: SplitParser {
            onRead: function(line) {
                if (!line) return
                try {
                    var j = JSON.parse(line)
                    if (j.error) { aiPanel.pullError = j.error; return }
                    aiPanel.pullStatus = j.status || ""
                    if (j.total && j.completed) aiPanel.pullFraction = j.completed / j.total
                    if (j.status === "success") aiPanel.pullFraction = 1
                } catch (e) { /* ignore partial/non-JSON lines */ }
            }
        }
    }
    function startPull(name) {
        if (!name || aiPanel.pulling) return
        aiPanel.pullError = ""; aiPanel.pullFraction = 0; aiPanel.pullStatus = "starting…"; aiPanel.pulling = true
        pullProc.command = ["curl", "-s", "-N", "-X", "POST", root.ollamaConfig.host + "/api/pull",
                             "-d", JSON.stringify({ name: name, stream: true })]
        pullProc.running = false; pullProc.running = true
    }

    // ── Ollama systemd service summary (read-only, no sudo needed) + edit ──
    property var svcEnv: ({})   // {KEEP_ALIVE, MAX_LOADED, HOST, NUM_PARALLEL}
    Process {
        id: svcProc
        command: ["systemctl", "show", "ollama.service", "--property=Environment"]
        stdout: StdioCollector {
            onStreamFinished: {
                var env = {}
                var m = this.text.match(/^Environment=(.*)$/m)
                if (m) m[1].split(/\s+/).forEach(function(tok) {
                    var i = tok.indexOf("=")
                    if (i > 0) env[tok.slice(0, i)] = tok.slice(i + 1)
                })
                aiPanel.svcEnv = {
                    KEEP_ALIVE: env.OLLAMA_KEEP_ALIVE || "",
                    MAX_LOADED: env.OLLAMA_MAX_LOADED_MODELS || "",
                    HOST: env.OLLAMA_HOST || "",
                    NUM_PARALLEL: env.OLLAMA_NUM_PARALLEL || ""
                }
            }
        }
    }
    Timer {
        interval: 15000; repeat: true; triggeredOnStart: true
        running: aiPanel.showOllama && root.aiUsageVisible
        onTriggered: { svcProc.running = false; svcProc.running = true }
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }
    Process { id: svcEditRunner; command: [] }
    function editServiceConfig() {
        // Pre-seed the drop-in (only if it doesn't exist yet) with just the 4
        // vars this widget tracks, commented with example values. Otherwise
        // `systemctl edit` on a unit with no existing override dumps the
        // ENTIRE original unit file as commented reference text — technically
        // correct, but reads as "everything is commented out" and buries the
        // vars we actually care about.
        var overrideDir = "/etc/systemd/system/ollama.service.d"
        var overridePath = overrideDir + "/override.conf"
        var seed = "[Service]\n"
                 + "#Environment=OLLAMA_KEEP_ALIVE=5m\n"
                 + "#Environment=OLLAMA_MAX_LOADED_MODELS=1\n"
                 + "#Environment=OLLAMA_HOST=0.0.0.0:11434\n"
                 + "#Environment=OLLAMA_NUM_PARALLEL=1\n"
        // explicit env assignment (not relying on ambient $EDITOR) since this
        // runs through sudo in a floating terminal spawned from the bar,
        // which doesn't inherit an interactive shell's env
        var cmd = "sudo mkdir -p " + aiPanel.shellQuote(overrideDir) + "; "
                + "[ -f " + aiPanel.shellQuote(overridePath) + " ] || "
                + "printf '%s' " + aiPanel.shellQuote(seed) + " | sudo tee " + aiPanel.shellQuote(overridePath) + " >/dev/null; "
                + "sudo SYSTEMD_EDITOR=nvim EDITOR=nvim systemctl edit ollama.service; "
                + "gum confirm 'Restart ollama.service to apply changes?' "
                + "&& sudo systemctl restart ollama.service "
                + "&& echo 'ollama.service restarted.' "
                + "|| echo 'No restart performed.'"
        svcEditRunner.command = ["bash", "-c",
            "omarchy-launch-floating-terminal-with-presentation " + aiPanel.shellQuote(cmd)]
        root.aiUsageVisible = false
        svcEditRunner.running = false; svcEditRunner.running = true
    }

    property real reveal: root.aiUsageVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.aiUsageVisible ? 160 : 120
            easing.type: root.aiUsageVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.aiUsageVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.aiUsageVisible = false
    }

    // ── reusable label · bar · % row ──
    component UsageRow: Item {
        property string label: ""
        property int pct: 0
        property bool dim: false
        width: parent ? parent.width : 0
        height: 16
        UiText {
            id: rowLbl
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: label; color: aiPanel.root.sumiHi
            font.family: aiPanel.root.mono; font.pixelSize: 11; font.letterSpacing: 1
        }
        UiText {
            id: rowVal
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: pct + "%"
            color: dim ? aiPanel.root.sumi : aiPanel.root.seal
            font.family: aiPanel.root.mono; font.pixelSize: 11; font.weight: Font.Medium
        }
        Rectangle {
            anchors.left: rowLbl.right; anchors.leftMargin: 8
            anchors.right: rowVal.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 8; radius: 4
            color: Qt.rgba(aiPanel.root.seal.r, aiPanel.root.seal.g, aiPanel.root.seal.b, 0.15)
            Rectangle {
                width: parent.width * Math.min(100, parent ? pct : 0) / 100
                height: parent.height; radius: 4
                color: pct >= 90 ? aiPanel.root.sealRaw : aiPanel.root.seal
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    // ── reusable key/value detail row ──
    component DetailRow: Row {
        property string k: ""
        property string v: ""
        width: parent ? parent.width : 0
        UiText {
            text: k; color: aiPanel.root.sumiHi
            font.family: aiPanel.root.mono; font.pixelSize: 11
            width: parent.width * 0.45
        }
        UiText {
            text: v; color: aiPanel.root.ink
            font.family: aiPanel.root.mono; font.pixelSize: 11
            width: parent.width * 0.55; horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    // ── labeled row of pill-style presets (Ollama CONFIG section) ──
    component ConfigPillRow: Item {
        id: pillRow
        property string label: ""
        property var options: []       // [{id, label}]
        property string selected: ""
        property var onPick: null      // function(id)
        width: parent ? parent.width : 0
        height: 22
        UiText {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: pillRow.label
            color: aiPanel.root.sumiHi
            font.family: aiPanel.root.mono; font.pixelSize: 10; font.letterSpacing: 1
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: pillRow.options
                Rectangle {
                    required property var modelData
                    readonly property bool active: modelData.id === pillRow.selected
                    width: pillLbl.implicitWidth + 14; height: 20; radius: 10
                    color: active ? aiPanel.root.fillActive : (pillMa.containsMouse ? aiPanel.root.fillHover : aiPanel.root.fillIdle)
                    border.color: (active || pillMa.containsMouse) ? aiPanel.root.seal : aiPanel.root.sep
                    border.width: 1
                    UiText {
                        id: pillLbl
                        anchors.centerIn: parent
                        text: modelData.label
                        color: (active || pillMa.containsMouse) ? aiPanel.root.seal : aiPanel.root.ink
                        font.family: aiPanel.root.mono; font.pixelSize: 9
                    }
                    MouseArea {
                        id: pillMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (pillRow.onPick) pillRow.onPick(modelData.id)
                    }
                }
            }
        }
    }

    // ── compact OpenCode per-model usage row ──
    component ModelUsageRow: Item {
        property string name: ""
        property string totalLabel: ""
        property string inputLabel: ""
        property string outputLabel: ""
        property string reasoningLabel: ""
        property string cacheReadLabel: ""
        property string cacheWriteLabel: ""
        property string todayLabel: ""
        property int pct: 0

        width: parent ? parent.width : 0
        height: 42

        UiText {
            id: modelName
            anchors.left: parent.left; anchors.top: parent.top
            width: parent.width * 0.68
            text: name
            elide: Text.ElideRight
            color: aiPanel.root.ink
            font.family: aiPanel.root.mono; font.pixelSize: 10; font.weight: Font.Medium
        }
        UiText {
            anchors.right: parent.right; anchors.top: parent.top
            text: totalLabel
            color: aiPanel.root.seal
            font.family: aiPanel.root.mono; font.pixelSize: 10; font.weight: Font.Medium
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: modelName.bottom; anchors.topMargin: 5
            height: 6; radius: 3
            color: Qt.rgba(aiPanel.root.seal.r, aiPanel.root.seal.g, aiPanel.root.seal.b, 0.14)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, pct)) / 100
                height: parent.height; radius: 3
                color: aiPanel.root.seal
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
        UiText {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            text: "I " + inputLabel + "  O " + outputLabel
                + (reasoningLabel !== "0" ? "  R " + reasoningLabel : "")
                + (cacheReadLabel !== "0" ? "  CR " + cacheReadLabel : "")
                + (cacheWriteLabel !== "0" ? "  CW " + cacheWriteLabel : "")
                + (todayLabel !== "0" ? "  today " + todayLabel : "")
            elide: Text.ElideRight
            color: aiPanel.root.sumiHi
            font.family: aiPanel.root.mono; font.pixelSize: 9
        }
    }

    Rectangle {
        id: card
        width: 500
        height: Math.min(col.implicitHeight + 24, parent.height - 2 * (barBottom + gap))
        radius: reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.aiBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
        opacity: aiPanel.reveal
        focus: root.aiUsageVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.aiUsageVisible = false;
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: 12
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: scroller.width
                spacing: 8

                // ── header ──
                Item {
                    width: parent.width
                    height: 24
                    UiText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "AI USAGE"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 13
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                    }
                    UiText {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"
                        color: closeMa.containsMouse ? root.seal : root.sumi
                        font.pixelSize: 12
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.aiUsageVisible = false
                        }
                    }
                }

                // ── segmented switch: which tool the bar shows ──
                Row {
                    width: parent.width
                    height: 28
                    spacing: 6
                    Repeater {
                        model: [ { id: "claude", label: "Claude" }, { id: "codex", label: "Codex" }, { id: "opencode", label: "OpenCode" }, { id: "ollama", label: "Ollama" } ]
                        Rectangle {
                            required property var modelData
                            width: root.evenW((parent.width - 18) / 4)
                            height: 28; radius: root.tileRadius
                            readonly property bool active: root.aiTool === modelData.id
                            color: active ? root.fillActive
                                  : segMa.containsMouse ? root.fillHover : root.fillIdle
                            border.color: (active || segMa.containsMouse) ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            UiText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: (parent.active || segMa.containsMouse) ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 11
                                font.weight: parent.active ? Font.Medium : Font.Normal
                            }
                            MouseArea {
                                id: segMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.aiTool = parent.modelData.id
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── Claude Code ──
                Item {
                    visible: aiPanel.showClaude
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "Claude Code"; color: root.ink
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    UiText {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: aiPanel.clFresh ? "live" : "stale"
                        color: aiPanel.clFresh ? root.sumi : root.sealRaw
                        font.family: root.mono; font.pixelSize: 10
                    }
                }
                UiText {
                    visible: aiPanel.showClaude && !aiPanel.clHas
                    width: parent.width
                    text: "no data — run claude"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 11
                }
                UsageRow { visible: aiPanel.showClaude && aiPanel.clHas; label: "5h"; pct: aiPanel.clPct5h; dim: !aiPanel.clFresh }
                UsageRow { visible: aiPanel.showClaude && aiPanel.clHas; label: "7d"; pct: aiPanel.clPct7d; dim: !aiPanel.clFresh }
                DetailRow { visible: aiPanel.showClaude && aiPanel.clHas; k: "5h resets in"; v: root.aiFmtResetDetail(aiPanel.clReset5hTs) || "—" }
                DetailRow { visible: aiPanel.showClaude && aiPanel.clHas; k: "7d resets in"; v: root.aiFmtResetDetail(aiPanel.clReset7dTs) || "—" }
                DetailRow { visible: aiPanel.showClaude && aiPanel.clHas && aiPanel.clTokens !== ""; k: "Tokens"; v: aiPanel.clTokens }
                DetailRow { visible: aiPanel.showClaude && aiPanel.clHas && aiPanel.clRate !== "";   k: "Rate"; v: aiPanel.clRate }
                DetailRow { visible: aiPanel.showClaude && aiPanel.clHas && aiPanel.clToday > 0; k: "Today"; v: (aiPanel.clToday / 1e6).toFixed(2) + "M tok" }

                Rectangle { visible: false; width: parent.width; height: 1; color: root.sep }

                // ── OpenAI Codex ──
                Item {
                    visible: aiPanel.showCodex
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "OpenAI Codex" + (aiPanel.cxPlan ? "  · " + aiPanel.cxPlan : "")
                        color: root.ink
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    UiText {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: aiPanel.cxFresh ? "live" : "stale"
                        color: aiPanel.cxFresh ? root.sumi : root.sealRaw
                        font.family: root.mono; font.pixelSize: 10
                    }
                }
                UiText {
                    visible: aiPanel.showCodex && !aiPanel.cxHas
                    width: parent.width
                    text: "no data — run codex"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 11
                }
                UsageRow { visible: aiPanel.showCodex && aiPanel.cxHas; label: "5h"; pct: aiPanel.cxPct5h; dim: !aiPanel.cxFresh }
                UsageRow { visible: aiPanel.showCodex && aiPanel.cxHas; label: "7d"; pct: aiPanel.cxPct7d; dim: !aiPanel.cxFresh }
                DetailRow { visible: aiPanel.showCodex && aiPanel.cxHas; k: "5h resets in"; v: root.aiFmtResetDetail(aiPanel.cxReset5hTs) || "—" }
                DetailRow { visible: aiPanel.showCodex && aiPanel.cxHas; k: "7d resets in"; v: root.aiFmtResetDetail(aiPanel.cxReset7dTs) || "—" }
                DetailRow { visible: aiPanel.showCodex && aiPanel.cxHas && aiPanel.cxTokens !== ""; k: "Tokens"; v: aiPanel.cxTokens }
                DetailRow { visible: aiPanel.showCodex && aiPanel.cxHas && aiPanel.cxRate !== "";   k: "Rate"; v: aiPanel.cxRate }
                DetailRow { visible: aiPanel.showCodex && aiPanel.cxHas && aiPanel.cxToday > 0; k: "Today"; v: (aiPanel.cxToday / 1e6).toFixed(2) + "M tok" }

                Rectangle { visible: false; width: parent.width; height: 1; color: root.sep }

                // ── OpenCode ──
                Item {
                    visible: aiPanel.showOpenCode
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "OpenCode" + (aiPanel.ocPlan ? "  · " + aiPanel.ocPlan : "")
                        color: root.ink
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    UiText {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: aiPanel.ocFresh ? "live" : "stale"
                        color: aiPanel.ocFresh ? root.sumi : root.sealRaw
                        font.family: root.mono; font.pixelSize: 10
                    }
                }
                UiText {
                    visible: aiPanel.showOpenCode && !aiPanel.ocHas
                    width: parent.width
                    text: "no data — run opencode"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 11
                }
                UsageRow { visible: aiPanel.showOpenCode && aiPanel.ocHas; label: "5h"; pct: aiPanel.ocPct5h; dim: !aiPanel.ocFresh }
                UsageRow { visible: aiPanel.showOpenCode && aiPanel.ocHas; label: "7d"; pct: aiPanel.ocPct7d; dim: !aiPanel.ocFresh }
                DetailRow { visible: aiPanel.showOpenCode && aiPanel.ocHas && aiPanel.ocTokens !== ""; k: "Tokens"; v: aiPanel.ocTokens }
                DetailRow { visible: aiPanel.showOpenCode && aiPanel.ocHas && aiPanel.ocRate !== "";   k: "Rate"; v: aiPanel.ocRate }
                DetailRow { visible: aiPanel.showOpenCode && aiPanel.ocHas && aiPanel.ocToday > 0; k: "Today"; v: (aiPanel.ocToday / 1e6).toFixed(2) + "M tok" }
                DetailRow { visible: aiPanel.showOpenCode && aiPanel.ocHas && aiPanel.ocModel !== ""; k: "Latest"; v: aiPanel.ocModel }

                Item {
                    visible: aiPanel.showOpenCode && aiPanel.ocHas && aiPanel.ocModels.length > 0
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "MODELS"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                    UiText {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: "recent"
                        color: root.sumi
                        font.family: root.mono; font.pixelSize: 10
                    }
                }
                Repeater {
                    model: (aiPanel.showOpenCode && aiPanel.ocHas) ? aiPanel.ocModels : []
                    ModelUsageRow {
                        width: col.width
                        name: modelData.name || ""
                        totalLabel: modelData.totalLabel || ""
                        inputLabel: modelData.inputLabel || "0"
                        outputLabel: modelData.outputLabel || "0"
                        reasoningLabel: modelData.reasoningLabel || "0"
                        cacheReadLabel: modelData.cacheReadLabel || "0"
                        cacheWriteLabel: modelData.cacheWriteLabel || "0"
                        todayLabel: modelData.todayLabel || "0"
                        pct: parseInt(modelData.pct) || 0
                    }
                }

                // ── Ollama (local models — no quota, so just install/active state) ──
                Item {
                    visible: aiPanel.showOllama
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "Ollama"; color: root.ink
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    UiText {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: aiPanel.olInstalled.length + " installed"
                            + (aiPanel.olTotalSize() ? "  ·  " + aiPanel.olTotalSize() : "")
                        color: root.sumi
                        font.family: root.mono; font.pixelSize: 10
                    }
                }
                UiText {
                    visible: aiPanel.showOllama && aiPanel.olInstalled.length === 0
                    width: parent.width
                    text: "no data — is ollama running?"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 11
                }

                Item {
                    visible: aiPanel.showOllama && aiPanel.olActive.length > 0
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "ACTIVE"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                }
                Repeater {
                    model: aiPanel.showOllama ? aiPanel.olActive : []
                    Column {
                        width: col.width
                        spacing: 1
                        Row {
                            width: parent.width
                            spacing: 8
                            UiText {
                                width: parent.width - 78
                                text: (modelData.name || "?")
                                color: root.seal
                                font.family: root.mono; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            UiText {
                                width: 70
                                horizontalAlignment: Text.AlignRight
                                text: aiPanel.olFmtSize(modelData.size)
                                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                                font.family: root.mono; font.pixelSize: 10
                            }
                        }
                        Row {
                            width: parent.width
                            spacing: 8
                            UiText {
                                width: parent.width - 78
                                text: [modelData.param, (modelData.vram > 0 ? "GPU" : "CPU")].filter(s => s).join("  ·  ")
                                color: root.sumi
                                font.family: root.mono; font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                            UiText {
                                width: 70
                                horizontalAlignment: Text.AlignRight
                                text: aiPanel.olFmtUntil(modelData.until)
                                color: root.sumi
                                font.family: root.mono; font.pixelSize: 9
                            }
                        }
                    }
                }

                Item {
                    visible: aiPanel.showOllama && aiPanel.olInstalled.length > 0
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "INSTALLED"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                }
                Repeater {
                    model: aiPanel.showOllama ? aiPanel.olInstalled : []
                    Column {
                        id: installedRow
                        width: col.width
                        spacing: 1
                        readonly property bool isLoaded: aiPanel.olActive.some(m => m.name === (modelData.name || ""))
                        Row {
                            width: parent.width
                            spacing: 8
                            UiText {
                                width: parent.width - 78
                                text: (modelData.name || "?")
                                color: root.ink
                                font.family: root.mono; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            UiText {
                                width: 70
                                horizontalAlignment: Text.AlignRight
                                text: aiPanel.olFmtSize(modelData.size)
                                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                                font.family: root.mono; font.pixelSize: 10
                            }
                        }
                        UiText {
                            visible: text !== ""
                            width: parent.width
                            text: [modelData.param, modelData.quant, modelData.family].filter(s => s).join("  ·  ")
                            color: root.sumi
                            font.family: root.mono; font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                        Item {
                            width: parent.width
                            height: 22
                            visible: !installedRow.isLoaded
                            Rectangle {
                                id: loadBtn
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 46; height: 18; radius: 9
                                readonly property bool busy: aiPanel.loadingModel === (modelData.name || "")
                                color: loadMa.containsMouse ? root.fillHover : root.fillIdle
                                border.color: (loadMa.containsMouse || busy) ? root.seal : root.sep
                                border.width: 1
                                UiText {
                                    anchors.centerIn: parent
                                    text: loadBtn.busy ? "…" : "Load"
                                    color: (loadMa.containsMouse || loadBtn.busy) ? root.seal : root.ink
                                    font.family: root.mono; font.pixelSize: 9
                                }
                                MouseArea {
                                    id: loadMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !loadBtn.busy
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: aiPanel.loadModel(modelData.name || "")
                                }
                            }
                        }
                    }
                }

                // ── pull a new model ──
                Rectangle { visible: aiPanel.showOllama; width: parent.width; height: 1; color: root.sep }
                Item {
                    visible: aiPanel.showOllama
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "PULL MODEL"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                }
                Row {
                    visible: aiPanel.showOllama
                    width: parent.width; height: 26; spacing: 8
                    Rectangle {
                        width: parent.width - 78; height: 26; radius: root.tileRadius
                        color: root.fillIdle
                        border.color: pullNameInput.activeFocus ? root.seal : root.sep
                        border.width: 1
                        TextInput {
                            id: pullNameInput
                            anchors.fill: parent; anchors.margins: 7
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.ink
                            font.family: root.mono; font.pixelSize: 10
                            clip: true
                            onTextChanged: aiPanel.pullInput = text
                            Keys.onReturnPressed: if (aiPanel.pullValid && !aiPanel.pulling) aiPanel.startPull(text.trim())
                        }
                        UiText {
                            visible: pullNameInput.text === ""
                            anchors.left: parent.left; anchors.leftMargin: 7; anchors.verticalCenter: parent.verticalCenter
                            text: "model name  e.g. llama3.2:3b"
                            color: root.sumi
                            font.family: root.mono; font.pixelSize: 10
                        }
                    }
                    Rectangle {
                        width: 70; height: 26; radius: root.tileRadius
                        readonly property bool enabledNow: aiPanel.pullValid && !aiPanel.pulling
                        opacity: enabledNow ? 1 : 0.4
                        color: pullMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: pullMa.containsMouse ? root.seal : root.sep
                        border.width: 1
                        UiText {
                            anchors.centerIn: parent
                            text: aiPanel.pulling ? "…" : "Pull"
                            color: pullMa.containsMouse ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 10
                        }
                        MouseArea {
                            id: pullMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.enabledNow
                            cursorShape: Qt.PointingHandCursor
                            onClicked: aiPanel.startPull(pullNameInput.text.trim())
                        }
                    }
                }
                UiText {
                    visible: aiPanel.showOllama && pullNameInput.text !== "" && !aiPanel.pullValid
                    width: parent.width
                    text: "invalid model name"
                    color: root.sealRaw
                    font.family: root.mono; font.pixelSize: 9
                }
                Rectangle {
                    visible: aiPanel.showOllama && (aiPanel.pulling || aiPanel.pullStatus !== "")
                    width: parent.width; height: 8; radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, aiPanel.pullFraction))
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
                UiText {
                    visible: aiPanel.showOllama && (aiPanel.pullError !== "" || aiPanel.pullStatus !== "")
                    width: parent.width
                    text: aiPanel.pullError || aiPanel.pullStatus
                    color: aiPanel.pullError !== "" ? root.sealRaw : root.sumi
                    font.family: root.mono; font.pixelSize: 9
                    elide: Text.ElideRight
                }

                // ── runtime config (per-request presets, not daemon-wide) ──
                Rectangle { visible: aiPanel.showOllama; width: parent.width; height: 1; color: root.sep }
                Item {
                    visible: aiPanel.showOllama
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "CONFIG"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                }
                ConfigPillRow {
                    visible: aiPanel.showOllama
                    width: parent.width
                    label: "keep_alive"
                    selected: root.ollamaConfig.keepAlive
                    options: [{id:"5m",label:"5m"},{id:"30m",label:"30m"},{id:"inf",label:"∞"}]
                    onPick: function(id) { root.setOllamaConfig("keepAlive", id) }
                }
                ConfigPillRow {
                    visible: aiPanel.showOllama
                    width: parent.width
                    label: "num_ctx"
                    selected: root.ollamaConfig.numCtx
                    options: [{id:"auto",label:"auto"},{id:"8192",label:"8k"},{id:"16384",label:"16k"},{id:"32768",label:"32k"}]
                    onPick: function(id) { root.setOllamaConfig("numCtx", id) }
                }
                ConfigPillRow {
                    visible: aiPanel.showOllama
                    width: parent.width
                    label: "poll"
                    selected: String(root.ollamaConfig.pollSec)
                    options: [{id:"1",label:"1s"},{id:"2",label:"2s"},{id:"5",label:"5s"}]
                    onPick: function(id) { root.setOllamaConfig("pollSec", parseInt(id)) }
                }
                Item {
                    visible: aiPanel.showOllama
                    width: parent.width; height: 24
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "host"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: parent.width * 0.62; height: 22; radius: root.tileRadius
                        color: root.fillIdle
                        border.color: hostInput.activeFocus ? root.seal : root.sep
                        border.width: 1
                        TextInput {
                            id: hostInput
                            anchors.fill: parent; anchors.margins: 6
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.ink
                            font.family: root.mono; font.pixelSize: 10
                            text: root.ollamaConfig.host
                            clip: true
                            onEditingFinished: {
                                var v = text.trim()
                                if (/^https?:\/\/.+/.test(v)) root.setOllamaConfig("host", v)
                                else text = root.ollamaConfig.host
                            }
                        }
                    }
                }

                // ── systemd service summary + edit ──
                Rectangle { visible: aiPanel.showOllama; width: parent.width; height: 1; color: root.sep }
                Item {
                    visible: aiPanel.showOllama
                    width: parent.width; height: 16
                    UiText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "SERVICE (systemd)"
                        color: root.sumiHi
                        font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                    }
                }
                DetailRow { visible: aiPanel.showOllama; k: "KEEP_ALIVE"; v: aiPanel.svcEnv.KEEP_ALIVE || "(default)" }
                DetailRow { visible: aiPanel.showOllama; k: "MAX_LOADED"; v: aiPanel.svcEnv.MAX_LOADED || "(default)" }
                DetailRow { visible: aiPanel.showOllama; k: "HOST"; v: aiPanel.svcEnv.HOST || "(default)" }
                DetailRow { visible: aiPanel.showOllama; k: "NUM_PARALLEL"; v: aiPanel.svcEnv.NUM_PARALLEL || "(default)" }
                Rectangle {
                    visible: aiPanel.showOllama
                    width: parent.width
                    height: 26; radius: root.tileRadius
                    color: svcEditMa.containsMouse ? root.fillHover : root.fillIdle
                    border.color: svcEditMa.containsMouse ? root.seal : root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    UiText {
                        anchors.centerIn: parent
                        text: "Edit service config…"
                        color: svcEditMa.containsMouse ? root.seal : root.ink
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        id: svcEditMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: aiPanel.editServiceConfig()
                    }
                }
            }
        }
    }

    // Usage data + polling live in Theme.qml (shared with the bar pill); this panel
    // only renders from root.ai* and bumps the refresh cadence via root.aiUsageVisible.
}
