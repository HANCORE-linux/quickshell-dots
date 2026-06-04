import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property bool recording: false
    property int  elapsed:   0   // seconds

    visible: recording
    implicitWidth: recording ? row.implicitWidth + 14 : 0
    implicitHeight: 28

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    readonly property string elapsedStr: {
        var h = Math.floor(elapsed / 3600)
        var m = Math.floor((elapsed % 3600) / 60)
        var s = elapsed % 60
        function pad(n) { return n < 10 ? "0" + n : String(n) }
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }
    readonly property string tooltipText: "Recording · " + elapsedStr + "\nClick to stop"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        // pulsing record dot
        Text {
            id: dot
            anchors.verticalCenter: parent.verticalCenter
            text: "\uE061"   // fiber_manual_record
            color: root.seal
            font.family: "Material Symbols Rounded"
            font.pixelSize: 13

            SequentialAnimation on opacity {
                running: rootMod.recording
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
            }
            // reset opacity when not recording
            onVisibleChanged: if (!rootMod.recording) opacity = 1.0
        }

        // timer
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.elapsedStr
            color: root.seal
            font.family: root.mono
            font.pixelSize: 11
        }
    }

    Process {
        id: recProc
        command: ["bash", "-c",
            "PID=$(pgrep -f '^gpu-screen-recorder' | head -1); " +
            "if [ -n \"$PID\" ]; then echo \"REC $(ps -o etimes= -p $PID 2>/dev/null | tr -d ' ')\"; else echo OFF; fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim()
                if (t.indexOf("REC") === 0) {
                    rootMod.recording = true
                    rootMod.elapsed = parseInt(t.split(" ")[1]) || 0
                } else {
                    rootMod.recording = false
                    rootMod.elapsed = 0
                }
            }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { recProc.running = false; recProc.running = true }
    }

    Process { id: toggleProc; command: ["bash", "-c", "omarchy-capture-screenrecording --stop-recording"] }

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: tipDelay.restart()
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: {
            tipDelay.stop(); root.hideTooltip(rootMod)
            toggleProc.running = false; toggleProc.running = true
            Qt.callLater(function() { recProc.running = false; recProc.running = true })
        }
    }
}
