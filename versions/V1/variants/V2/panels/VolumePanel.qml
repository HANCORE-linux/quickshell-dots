import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../modules"

PanelWindow {
    id: volPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-volume"

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    AudioData { id: audio }
    readonly property int    volume:   audio.volume
    readonly property bool   muted:    audio.muted
    property bool   micMuted: false
    property real   micLevel: 0
    property bool   notifyMicStateAfterRefresh: false
    property bool   micStateRefreshPending: false
    readonly property real micNoiseFloorDb: -55
    readonly property bool micMeterAvailable: micPeakLoader.status === Loader.Ready
        && micPeakLoader.item !== null
    readonly property real micPeakValue: micMeterAvailable ? micPeakLoader.item.peak : 0

    Loader {
        id: micPeakLoader
        active: true
        source: "MicrophonePeakMonitor.qml"
        onLoaded: {
            item.panelOpen = Qt.binding(function() { return root.volVisible })
            item.muted = Qt.binding(function() { return volPanel.micMuted })
        }
    }

    function peakToMeter(peak) {
        if (!isFinite(peak) || peak <= 0) return 0
        // PwNodePeakMonitor exposes the cube root of linear amplitude.
        var amplitude = peak * peak * peak
        var db = 20 * Math.log(amplitude) / Math.LN10
        if (db <= micNoiseFloorDb) return 0
        return Math.max(0, Math.min(1, (db - micNoiseFloorDb) / -micNoiseFloorDb))
    }

    Timer {
        interval: 45
        repeat: true
        running: root.volVisible && volPanel.micMeterAvailable
        onTriggered: {
            var sample = volPanel.micMuted ? 0 : volPanel.peakToMeter(volPanel.micPeakValue)
            volPanel.micLevel = sample >= volPanel.micLevel
                ? sample : Math.max(sample, volPanel.micLevel * 0.78)
        }
        onRunningChanged: if (!running) volPanel.micLevel = 0
    }

    // ── per-app mixer + device switcher state ──
    property var    apps:        []   // [{idx, name, vol, muted}]
    property var    sinks:       []   // [{index, name, desc}]
    property string defaultSink: ""
    property string _appsRaw:    ""
    property string _sinksRaw:   ""
    property bool   audioErrorNotified: false

    readonly property string outputMuteCommand:
        "(command -v omarchy-swayosd-client >/dev/null 2>&1 && omarchy-swayosd-client --output-volume mute-toggle) || " +
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle || " +
        "pamixer -t"

    readonly property string micMuteCommand:
        "if command -v omarchy-audio-input-mute >/dev/null 2>&1; then " +
        "omarchy-audio-input-mute; " +
        "else wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || pamixer --default-source -t; fi"

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function run(cmd, refreshAfter) {
        actProc.running = false
        actProc.refreshAfterExit = refreshAfter === true
        actProc.command = ["bash", "-c", cmd]
        actProc.running = true
    }
    function notifyAudioError(action, exitCode) {
        if (exitCode === 0 || audioErrorNotified) return
        audioErrorNotified = true
        audioErrNotify.command = ["bash", "-c",
            "notify-send -a 'QS-Shell' 'Audio command failed' " +
            volPanel.shq(action + " failed; audio backend unavailable.") +
            " 2>/dev/null || true"]
        audioErrNotify.running = false
        audioErrNotify.running = true
    }
    function notifyMicState() {
        var title = micMuted ? "Microphone muted" : "Microphone active"
        var body = micMuted ? "Input has been disabled" : "Input is ready"
        micStateNotify.command = ["notify-send", "-a", "Audio",
            "-h", "string:x-canonical-private-synchronous:qs-microphone", title, body]
        micStateNotify.running = false
        micStateNotify.running = true
    }
    function parseMicMuteState(text) {
        var match = String(text || "").trim().match(/^Mute:\s*(yes|no)$/i)
        if (!match) return -1
        return match[1].toLowerCase() === "yes" ? 1 : 0
    }
    function refreshMicState(notifyAfter) {
        if (notifyAfter === true) notifyMicStateAfterRefresh = true
        if (micData.running) {
            micStateRefreshPending = true
            return
        }
        micData.running = true
    }

    function setDefaultSink(dev) {
        if (!dev || !dev.name) return

        var sinkName = volPanel.shq(dev.name)
        var nodeId = (dev.index !== undefined && dev.index !== null) ? String(dev.index).replace(/[^0-9]/g, "") : ""
        var cmd = ""
        if (nodeId.length > 0)
            cmd += "timeout 2 wpctl set-default " + nodeId + " 2>/dev/null || true\n"
        cmd += "timeout 2 pactl set-default-sink " + sinkName + " 2>/dev/null || true\n"
        cmd += "timeout 2 pactl list short sink-inputs 2>/dev/null | awk '{ print $1 }' | while read -r input; do\n"
        cmd += "  [ -n \"$input\" ] && timeout 2 pactl move-sink-input \"$input\" " + sinkName + " 2>/dev/null || true\n"
        cmd += "done"

        volPanel.defaultSink = dev.name
        volPanel.run(cmd, true)
    }

    function refreshAll() {
        audio.refresh()
        appsProc.running   = false; appsProc.running   = true
        sinksProc.running  = false; sinksProc.running  = true
        defSinkProc.running = false; defSinkProc.running = true
        volPanel.refreshMicState(false)
    }

    readonly property real reveal: root.volReveal
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.volVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.volVisible = false
    }

    Rectangle {
        id: card
        width: 280
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelBorder
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: volPanel.root
            ownerActive: volPanel.root.volVisible
            targetX: volPanel.root.volumeBarX
            reveal: volPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.volumeBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - volPanel.reveal)
            : (barBottom + gap) - 2 * (1 - volPanel.reveal)
        opacity: volPanel.reveal
        focus: root.volVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.volVisible = false;
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── header ──
            Item {
                width: parent.width
                height: 24
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Volume"
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
                        onClicked: root.volVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── volume bar ──
            UiText {
                text: "OUTPUT"
                color: root.sumiHi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }

            Item {
                width: parent.width
                height: 30
                UiText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: volPanel.muted ? "Muted" : volPanel.volume + "%"
                    color: volPanel.muted
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.4)
                        : root.seal
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 8; radius: 4
                    color: root.fillActive
                    Rectangle {
                        width: parent.width * (volPanel.muted ? 0 : Math.min(volPanel.volume / 100, 1))
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // ── output device switcher ──
            UiText {
                text: "OUTPUT DEVICE"
                color: root.sumiHi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: volPanel.sinks
                    delegate: Rectangle {
                        id: devTile
                        required property var modelData
                        readonly property bool isDef:   devTile.modelData.name === volPanel.defaultSink
                        readonly property bool hovered: devMa.containsMouse
                        width: parent.width
                        height: 26; radius: root.panelButtonRadius
                        color: isDef     ? root.fillActive
                             : hovered ? root.fillHover : root.fillIdle
                        border.color: (isDef || hovered) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 6
                            UiText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: devTile.isDef ? "●" : "○"
                                color: devTile.isDef ? root.seal : root.sumi
                                font.family: root.mono; font.pixelSize: 10
                            }
                            UiText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 22
                                text: devTile.modelData.desc
                                color: (devTile.isDef || devTile.hovered) ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: devMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                volPanel.setDefaultSink(devTile.modelData)
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── mute toggle ──
            Rectangle {
                width: parent.width
                height: 28; radius: root.panelButtonRadius
                color: volPanel.muted ? root.fillActive
                    : muteMa.containsMouse ? root.fillHover
                    : root.fillIdle
                border.color: (muteMa.containsMouse || volPanel.muted) ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: volPanel.muted ? "Unmute volume" : "Mute volume"
                    color: (muteMa.containsMouse || volPanel.muted) ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: muteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!muteRunner.running) muteRunner.running = true
                    }
                }
            }

            // ── per-app mixer ──
            Rectangle { width: parent.width; height: 1; color: root.sep; visible: volPanel.apps.length > 0 }
            UiText {
                visible: volPanel.apps.length > 0
                text: "APPS"
                color: root.sumiHi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Column {
                width: parent.width
                spacing: 8
                Repeater {
                    model: volPanel.apps
                    delegate: Item {
                        id: appRow
                        required property var modelData
                        width: parent.width
                        height: 32
                        property int liveVol: modelData.vol

                        // mute glyph
                        IconText {
                            id: appMute
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: appRow.modelData.muted ? String.fromCodePoint(0xE04F) : String.fromCodePoint(0xE050)
                            font.pixelSize: 15
                            color: appRow.modelData.muted ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4) : root.seal
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -3
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    volPanel.run("pactl set-sink-input-mute " + appRow.modelData.idx + " toggle")
                                    Qt.callLater(function() { volPanel.refreshAll() })
                                }
                            }
                        }
                        UiText {
                            anchors.left: appMute.right; anchors.leftMargin: 6
                            anchors.verticalCenter: appMute.verticalCenter
                            anchors.verticalCenterOffset: 1
                            anchors.right: appPct.left; anchors.rightMargin: 6
                            text: appRow.modelData.name
                            color: appRow.modelData.muted ? root.sumi : root.ink
                            font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        UiText {
                            id: appPct
                            anchors.right: parent.right
                            anchors.verticalCenter: appMute.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: appRow.liveVol + "%"
                            color: root.seal
                            font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
                        }

                        // draggable volume bar
                        Rectangle {
                            id: appTrack
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 8; radius: 4
                            color: root.fillActive
                            Rectangle {
                                width: parent.width * Math.min(appRow.liveVol / 100, 1)
                                height: parent.height; radius: 4
                                color: appRow.modelData.muted ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.4) : root.seal
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.topMargin: -8; anchors.bottomMargin: -4
                                cursorShape: Qt.PointingHandCursor
                                function setFromX(x) {
                                    appRow.liveVol = Math.max(0, Math.min(100, Math.round(x / appTrack.width * 100)))
                                }
                                onPressed:          function(m) { setFromX(m.x) }
                                onPositionChanged:  function(m) { if (pressed) setFromX(m.x) }
                                onReleased: {
                                    volPanel.run("pactl set-sink-input-volume " + appRow.modelData.idx + " " + appRow.liveVol + "%")
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── mic section ──
            UiText {
                text: "INPUT"
                color: root.sumiHi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }

            Row {
                width: parent.width
                UiText {
                    text: "Microphone"
                    color: root.sumiHi
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.5
                }
                UiText {
                    text: volPanel.micMuted ? "Muted" : "Active"
                    color: volPanel.micMuted
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.5)
                        : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.5
                    horizontalAlignment: Text.AlignRight
                }
            }

            Item {
                width: parent.width
                height: visible ? 8 : 0
                visible: volPanel.micMeterAvailable

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: root.fillIdle
                    border.color: root.sep
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * volPanel.micLevel
                        radius: parent.radius
                        color: volPanel.micMuted
                            ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.25)
                            : root.seal
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 28; radius: root.panelButtonRadius
                color: volPanel.micMuted ? root.fillActive
                    : micMuteMa.containsMouse ? root.fillHover
                    : root.fillIdle
                border.color: (micMuteMa.containsMouse || volPanel.micMuted) ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: volPanel.micMuted ? "Unmute mic" : "Mute mic"
                    color: (micMuteMa.containsMouse || volPanel.micMuted) ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: micMuteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!micMuteRunner.running) micMuteRunner.running = true
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── open audio ──
            Rectangle {
                width: parent.width
                height: 28; radius: root.panelButtonRadius
                color: audioBtnMa.containsMouse ? root.fillPrimaryHover : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: "Open audio"
                    color: root.paper
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: audioBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.volVisible = false
                        audioRunner.running = false
                        audioRunner.running = true
                    }
                }
            }
        }
    }

    Process { id: audioErrNotify }
    Process { id: micStateNotify }
    Process {
        id: muteRunner
        command: ["bash", "-c", volPanel.outputMuteCommand]
        onExited: (code) => {
            volPanel.notifyAudioError("Mute volume", code)
            audio.refresh()
        }
    }
    Process {
        id: micMuteRunner
        command: ["bash", "-c", volPanel.micMuteCommand]
        onExited: (code) => {
            volPanel.notifyAudioError("Mute mic", code)
            volPanel.refreshMicState(code === 0)
        }
    }
    Process { id: audioRunner;   command: ["bash", "-c", "omarchy-launch-audio"] }
    Process {
        id: actProc
        property bool refreshAfterExit: false
        command: []
        onExited: {
            if (refreshAfterExit) {
                refreshAfterExit = false
                volPanel.refreshAll()
            }
        }
    }

    Process {
        id: micData
        command: ["env", "LC_ALL=C", "pactl", "get-source-mute", "@DEFAULT_SOURCE@"]
        running: false
        stdout: StdioCollector { id: micDataOut }
        // pactl get-source-mute prints "Mute: yes" | "Mute: no". Only act on an explicit,
        // VALID read (exit 0 + a parsed yes/no): empty/failed/malformed output must NOT flip
        // micMuted to false — that would falsely report "Microphone active". On a bad read we
        // keep the previous state, drop any pending toggle notification, and surface the
        // failure through the existing audio-error path.
        onExited: (code) => {
            var state = volPanel.parseMicMuteState(micDataOut.text)
            var valid = code === 0 && state >= 0
            var rerun = volPanel.micStateRefreshPending
            volPanel.micStateRefreshPending = false
            if (rerun) {
                Qt.callLater(function() { volPanel.refreshMicState(false) })
                return
            }
            var pending = volPanel.notifyMicStateAfterRefresh
            volPanel.notifyMicStateAfterRefresh = false
            if (!valid) {
                volPanel.notifyAudioError("Read mic state", code !== 0 ? code : 1)
                return
            }
            volPanel.micMuted = state === 1
            if (pending) volPanel.notifyMicState()
        }
    }

    // per-app streams
    Process {
        id: appsProc
        command: ["bash", "-c", "pactl -f json list sink-inputs 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "[]")
                if (raw === volPanel._appsRaw) return   // unchanged → no rebuild/flicker
                volPanel._appsRaw = raw
                var out = []
                try {
                    var j = JSON.parse(raw)
                    for (var i = 0; i < j.length; i++) {
                        var s = j[i], p = s.properties || {}
                        var nm = p["application.name"] || p["media.name"] || p["application.process.binary"] || "App"
                        var vk = Object.keys(s.volume || {})
                        var vp = vk.length ? String(s.volume[vk[0]].value_percent) : "0%"
                        out.push({ idx: s.index, name: nm, vol: (parseInt(vp.replace("%", "")) || 0), muted: !!s.mute })
                    }
                } catch (e) {}
                volPanel.apps = out
            }
        }
    }

    // output devices
    Process {
        id: sinksProc
        command: ["bash", "-c", "pactl -f json list sinks 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "[]")
                if (raw === volPanel._sinksRaw) return
                volPanel._sinksRaw = raw
                var out = []
                try {
                    var j = JSON.parse(raw)
                    for (var i = 0; i < j.length; i++) {
                        var d = j[i].description
                        if (!d || d === "(null)") {
                            var p = j[i].properties || {}
                            d = p["device.description"] || p["alsa.card_name"] || j[i].name
                        }
                        out.push({ index: j[i].index, name: j[i].name, desc: d })
                    }
                } catch (e) {}
                volPanel.sinks = out
            }
        }
    }

    Process {
        id: defSinkProc
        command: ["bash", "-c", "pactl get-default-sink 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: { volPanel.defaultSink = this.text.trim() }
        }
    }

    // light refresh while open so new apps / external changes show up
    Timer {
        interval: 2000; repeat: true
        running: volPanel.visible
        onTriggered: {
            appsProc.running   = false; appsProc.running   = true
            defSinkProc.running = false; defSinkProc.running = true
        }
    }

    onVisibleChanged: {
        if (visible) volPanel.refreshAll()
    }
}
