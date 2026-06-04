import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: volPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-volume"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property int    volume:   0
    property bool   muted:    false
    property string portType: "default"
    property bool   micMuted: false

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
                    color: root.sumi
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
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
                    font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
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

            // ── port info ──
            Row {
                width: parent.width
                Text {
                    text: "Device"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.4
                }
                Text {
                    text: {
                        if (volPanel.portType === "headphone") return "Headphones"
                        if (volPanel.portType === "headset")   return "Headset"
                        return "Speakers"
                    }
                    color: root.ink
                    font.family: root.mono; font.pixelSize: 11
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── mute toggle ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: volPanel.muted
                    ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: volPanel.muted ? root.seal : root.sep
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: volPanel.muted ? "Unmute" : "Mute"
                    color: volPanel.muted ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        muteRunner.running = false
                        muteRunner.running = true
                        Qt.callLater(function() {
                            audioData.lines = []
                            audioData.running = false
                            audioData.running = true
                        })
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
                color: volPanel.micMuted
                    ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: volPanel.micMuted ? root.seal : root.sep
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: volPanel.micMuted ? "Unmute mic" : "Mute mic"
                    color: volPanel.micMuted ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
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
                color: root.seal
                Text {
                    anchors.centerIn: parent
                    text: "Open audio"
                    color: root.paper
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
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

    Process {
        id: audioData
        command: ["bash", "-c",
            "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '[0-9]+(?=%)' | head -1; " +
            "pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}'; " +
            "pactl list sinks 2>/dev/null | grep -A80 \"Name: $(pactl get-default-sink)\" | grep 'Active Port' | awk '{print $NF}'"
        ]
        stdout: SplitParser {
            onRead: function(line) { audioData.lines.push(line.trim()) }
        }
        onExited: {
            if (audioData.lines.length >= 2) {
                volPanel.volume = parseInt(audioData.lines[0]) || 0
                volPanel.muted  = (audioData.lines[1] === "yes")
                var port = audioData.lines[2] || ""
                if (port.includes("headphone"))    volPanel.portType = "headphone"
                else if (port.includes("headset")) volPanel.portType = "headset"
                else                               volPanel.portType = "default"
            }
            audioData.lines = []
        }
        property var lines: []
    }

    Process { id: muteRunner;    command: ["bash", "-c", "pamixer -t"] }
    Process { id: micMuteRunner; command: ["bash", "-c", "pamixer --default-source -t"] }
    Process { id: audioRunner;   command: ["bash", "-c", "omarchy-launch-audio"] }

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

    onVisibleChanged: {
        if (visible) {
            audioData.lines = []
            audioData.running = false
            audioData.running = true
            micData.running = false
            micData.running = true
        }
    }
}
