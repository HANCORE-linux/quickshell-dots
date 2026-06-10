import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../modules"

PanelWindow {
    id: volPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-volume"

    readonly property int barBottom: 35
    readonly property int gap: 8

    AudioData { id: audio }
    readonly property int    volume:   audio.volume
    readonly property bool   muted:    audio.muted
    readonly property string portType: audio.portType
    property bool   micMuted: false

    // ── per-app mixer + device switcher state ──
    property var    apps:        []   // [{idx, name, vol, muted}]
    property var    sinks:       []   // [{name, desc}]
    property string defaultSink: ""
    property string _appsRaw:    ""
    property string _sinksRaw:   ""

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function run(cmd) { actProc.command = ["bash", "-c", cmd]; actProc.running = false; actProc.running = true }

    function refreshAll() {
        audio.refresh()
        appsProc.running   = false; appsProc.running   = true
        sinksProc.running  = false; sinksProc.running  = true
        defSinkProc.running = false; defSinkProc.running = true
        micData.running    = false; micData.running    = true
    }

    property real reveal: root.volVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.volVisible ? 160 : 120
            easing.type: root.volVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
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
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: 6
        y: barBottom + gap
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
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Volume"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Text {
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
            Text {
                text: "OUTPUT"
                color: root.sumi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }

            Item {
                width: parent.width
                height: 30
                Text {
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
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * (volPanel.muted ? 0 : Math.min(volPanel.volume / 100, 1))
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // ── output device switcher ──
            Text {
                text: "OUTPUT DEVICE"
                color: root.sumi
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
                        height: 26; radius: 4
                        color: isDef     ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                             : hovered    ? Qt.rgba(root.ink.r,  root.ink.g,  root.ink.b,  0.12)
                                          : Qt.rgba(root.ink.r,  root.ink.g,  root.ink.b,  0.06)
                        border.color: (isDef || hovered) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: devTile.isDef ? "●" : "○"
                                color: devTile.isDef ? root.seal : root.sumi
                                font.family: root.mono; font.pixelSize: 10
                            }
                            Text {
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
                                volPanel.run("pactl set-default-sink " + volPanel.shq(devTile.modelData.name))
                                volPanel.defaultSink = devTile.modelData.name
                                Qt.callLater(function() { volPanel.refreshAll() })
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── mute toggle ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: muteMa.containsMouse
                    ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                    : volPanel.muted ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: (muteMa.containsMouse || volPanel.muted) ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: volPanel.muted ? "Unmute" : "Mute"
                    color: (muteMa.containsMouse || volPanel.muted) ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: muteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        muteRunner.running = false
                        muteRunner.running = true
                        Qt.callLater(function() { audio.refresh() })
                    }
                }
            }

            // ── per-app mixer ──
            Rectangle { width: parent.width; height: 1; color: root.sep; visible: volPanel.apps.length > 0 }
            Text {
                visible: volPanel.apps.length > 0
                text: "APPS"
                color: root.sumi
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
                        Text {
                            id: appMute
                            anchors.left: parent.left
                            anchors.top: parent.top
                            text: appRow.modelData.muted ? String.fromCodePoint(0xE04F) : String.fromCodePoint(0xE050)
                            font.family: "Material Symbols Rounded"; font.pixelSize: 15
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
                        Text {
                            anchors.left: appMute.right; anchors.leftMargin: 6
                            anchors.top: parent.top
                            anchors.right: appPct.left; anchors.rightMargin: 6
                            text: appRow.modelData.name
                            color: appRow.modelData.muted ? root.sumi : root.ink
                            font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Text {
                            id: appPct
                            anchors.right: parent.right
                            anchors.top: parent.top
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
                            color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
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
            Text {
                text: "INPUT"
                color: root.sumi
                font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }

            Row {
                width: parent.width
                Text {
                    text: "Microphone"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.5
                }
                Text {
                    text: volPanel.micMuted ? "Muted" : "Active"
                    color: volPanel.micMuted
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.5)
                        : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                    font.family: root.mono; font.pixelSize: 11
                }
            }

            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: micMuteMa.containsMouse
                    ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                    : volPanel.micMuted ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: (micMuteMa.containsMouse || volPanel.micMuted) ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
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
                        micMuteRunner.running = false
                        micMuteRunner.running = true
                        Qt.callLater(function() {
                            micData.running = false
                            micData.running = true
                        })
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── open audio ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: audioBtnMa.containsMouse ? Qt.lighter(root.seal, 1.15) : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
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

    Process { id: muteRunner;    command: ["bash", "-c", "pamixer -t"] }
    Process { id: micMuteRunner; command: ["bash", "-c", "pamixer --default-source -t"] }
    Process { id: audioRunner;   command: ["bash", "-c", "omarchy-launch-audio"] }
    Process { id: actProc;       command: [] }

    Process {
        id: micData
        command: ["bash", "-c", "pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print $2}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                volPanel.micMuted = this.text.trim() === "yes"
            }
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
                        out.push({ name: j[i].name, desc: d })
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
