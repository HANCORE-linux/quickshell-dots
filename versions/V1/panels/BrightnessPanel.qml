import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: briPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-brightness"

    readonly property int barBottom: 35
    readonly property int gap: 8

    property int percent: 0

    property real reveal: root.brightnessVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.brightnessVisible ? 160 : 120
            easing.type: root.brightnessVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.brightnessVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.brightnessVisible = false }

    function refresh() { briData.running = false; briData.running = true }

    Rectangle {
        id: card
        width: 280
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: parent.width - width - 6
        y: barBottom + gap
        opacity: briPanel.reveal
        focus: root.brightnessVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.brightnessVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Brightness"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: closeMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.brightnessVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── interactive bar ──
            Item {
                width: parent.width
                height: 30
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: briPanel.percent + "%"
                    color: root.seal
                    font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
                }
                Rectangle {
                    id: track
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 8; radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * briPanel.percent / 100
                        height: parent.height; radius: 4; color: root.seal
                        Behavior on width { NumberAnimation { duration: 150 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (e) => setFromX(e.x)
                        onPositionChanged: (e) => { if (pressed) setFromX(e.x) }
                        function setFromX(px) {
                            var p = Math.max(1, Math.min(100, Math.round(px / track.width * 100)))
                            setRunner.command = ["bash", "-c", "brightnessctl set " + p + "% -q"]
                            setRunner.running = false; setRunner.running = true
                            briPanel.percent = p
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── +/- buttons ──
            Row {
                width: parent.width
                spacing: 8
                Rectangle {
                    id: btnDown
                    width: (parent.width - 8) / 2; height: 28; radius: 4
                    color: _dn.containsMouse ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                                             : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                    border.color: _dn.containsMouse ? root.seal : root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "− 5%"; color: _dn.containsMouse ? root.seal : root.sumi
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        id: _dn
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { downRunner.running = false; downRunner.running = true; Qt.callLater(briPanel.refresh) }
                    }
                }
                Rectangle {
                    id: btnUp
                    width: (parent.width - 8) / 2; height: 28; radius: 4
                    color: _up.containsMouse ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                                             : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                    border.color: _up.containsMouse ? root.seal : root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: "+ 5%"; color: _up.containsMouse ? root.seal : root.sumi
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        id: _up
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { upRunner.running = false; upRunner.running = true; Qt.callLater(briPanel.refresh) }
                    }
                }
            }
        }
    }

    Process {
        id: briData
        command: ["bash", "-c",
            "BL=$(ls /sys/class/backlight/ 2>/dev/null | head -1); [ -z \"$BL\" ] && exit; " +
            "CUR=$(cat /sys/class/backlight/$BL/brightness 2>/dev/null || echo 0); " +
            "MAX=$(cat /sys/class/backlight/$BL/max_brightness 2>/dev/null || echo 100); " +
            "echo $((MAX > 0 ? CUR * 100 / MAX : 0))"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim())
                if (!isNaN(v)) briPanel.percent = Math.max(0, Math.min(100, v))
            }
        }
    }

    Process { id: setRunner;  command: ["bash", "-c", "true"] }
    Process { id: upRunner;   command: ["bash", "-c", "brightnessctl set +5% -q"] }
    Process { id: downRunner; command: ["bash", "-c", "brightnessctl set 5%- -q"] }

    onVisibleChanged: { if (visible) refresh() }
}
