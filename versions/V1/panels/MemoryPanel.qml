import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: memPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-memory"

    readonly property int barBottom: 35
    readonly property int gap: 8

    property int memTotal: 0
    property int memAvail: 0
    property int memFree: 0
    property int memBuffers: 0
    property int memCached: 0
    readonly property int memUsed: Math.max(0, memTotal - memAvail)
    readonly property int pct: memTotal > 0 ? Math.round(memUsed / memTotal * 100) : 0
    readonly property real usedGiB: memUsed / 1024
    readonly property real totalGiB: memTotal / 1024

    property real reveal: root.memVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.memVisible ? 160 : 120
            easing.type: root.memVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.memVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.memVisible = false
    }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: 6
        y: barBottom + gap
        opacity: memPanel.reveal
        focus: root.memVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.memVisible = false;
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
                    text: "Memory"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.memVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── usage bar ──
            Item {
                width: parent.width
                height: 30
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: memPanel.pct + "%"
                    color: root.seal
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 8; radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * memPanel.pct / 100
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // ── stats ──
            Column {
                width: parent.width
                spacing: 4
                Row {
                    width: parent.width
                    Text { text: "Used"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: memPanel.usedGiB.toFixed(1) + " GiB"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    Text { text: memPanel.memUsed + " MiB"; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
                Row {
                    width: parent.width
                    Text { text: "Available"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: (memPanel.memAvail / 1024).toFixed(1) + " GiB"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    Text { text: memPanel.memAvail + " MiB"; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
                Row {
                    width: parent.width
                    Text { text: "Total"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: memPanel.totalGiB.toFixed(1) + " GiB"; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                    Text { text: memPanel.memTotal + " MiB"; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6); font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.3 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── button ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: btopMa.containsMouse ? Qt.lighter(root.seal, 1.15) : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "Open btop"
                    color: root.paper
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: btopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.memVisible = false;
                        btopRunner.running = false;
                        btopRunner.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: memData
        command: ["bash", "-c",
            "awk '/MemTotal:/ {t=$2} /MemFree:/ {f=$2} /MemAvailable:/ {a=$2} /Buffers:/ {b=$2} /^Cached:/ {c=$2} END{printf \"%d %d %d %d %d\", t/1024, a/1024, f/1024, b/1024, c/1024}' /proc/meminfo"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split(/\s+/)
                if (parts.length >= 5) {
                    memPanel.memTotal = parseInt(parts[0]) || 0
                    memPanel.memAvail = parseInt(parts[1]) || 0
                    memPanel.memFree = parseInt(parts[2]) || 0
                    memPanel.memBuffers = parseInt(parts[3]) || 0
                    memPanel.memCached = parseInt(parts[4]) || 0
                }
            }
        }
    }

    Process {
        id: btopRunner
        command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation 'btop'"]
    }

    onVisibleChanged: {
        if (visible) {
            memData.running = false
            memData.running = true
        }
    }
}
