import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property int volume: 50
    property bool muted: false
    property string portType: "default"

    readonly property string tooltipText: muted
        ? "Muted · " + volume + "%"
        : "Audio " + volume + "%"

    implicitWidth: row.implicitWidth + 18
    implicitHeight: 28

    Rectangle {
        anchors.centerIn: row
        width: row.width + 18
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "VOL"
            color: rootMod.muted
                ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        // ── workspace-capsule style slider ──
        Item {
            id: slider
            width: 34
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            readonly property real ratio: rootMod.muted ? 0 : Math.min(rootMod.volume / 100, 1)

            // track capsule
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 8
                radius: 4
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.18)
            }

            // fill capsule — seal pill like the active workspace
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(slider.ratio > 0 ? 8 : 0, parent.width * slider.ratio)
                height: 8
                radius: 4
                color: root.seal
                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(rootMod.volume).padStart(2, '0') + "%"
            color: rootMod.muted
                ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.35)
                : root.seal
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    Process {
        id: audioProc
        command: ["bash", "-c",
            "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '[0-9]+(?=%)' | head -1; " +
            "pactl get-sink-mute   @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}'; " +
            "pactl list sinks 2>/dev/null | grep -A80 \"Name: $(pactl get-default-sink)\" | grep 'Active Port' | awk '{print $NF}'"
        ]
        running: false
        stdout: SplitParser {
            onRead: function(line) { audioProc.lines.push(line.trim()) }
        }
        onExited: {
            if (audioProc.lines.length >= 2) {
                rootMod.volume = parseInt(audioProc.lines[0]) || 0
                rootMod.muted  = (audioProc.lines[1] === "yes")
                var port = audioProc.lines[2] || ""
                if (port.includes("headphone"))    rootMod.portType = "headphone"
                else if (port.includes("headset")) rootMod.portType = "headset"
                else                               rootMod.portType = "default"
            }
            audioProc.lines = []
        }
        property var lines: []
    }

    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { audioProc.lines = []; audioProc.running = true }
    }

    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            if (!rootMod.tooltipText) return
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    Process { id: muteRunner;    command: ["bash", "-c", "pamixer -t"] }
    Process { id: volUpRunner;   command: ["bash", "-c", "pamixer --increase 5"] }
    Process { id: volDownRunner; command: ["bash", "-c", "pamixer --decrease 5"] }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tipDelay.restart()
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod) }
        onWheel: (e) => {
            if (e.angleDelta.y > 0) { volUpRunner.running = false; volUpRunner.running = true }
            else                    { volDownRunner.running = false; volDownRunner.running = true }
            audioProc.lines = []; audioProc.running = false; audioProc.running = true
        }
        onClicked: (e) => {
            tipDelay.stop(); root.hideTooltip(rootMod)
            if (e.button === Qt.RightButton) { muteRunner.running = false; muteRunner.running = true }
            else                             { root.volVisible = !root.volVisible }
        }
    }
}
