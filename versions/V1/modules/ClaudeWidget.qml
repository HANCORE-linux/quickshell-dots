import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property bool claudeActive: false
    property int  pct5h:   0
    property bool blocked: false
    property string tooltipFull: ""

    readonly property string tooltipText: tooltipFull || ("Claude · " + pct5h + "%")

    visible: claudeActive
    implicitWidth: claudeActive ? row.implicitWidth + 18 : 0
    implicitHeight: 28

    Process {
        id: detectProc
        command: ["bash", "-c", "pgrep -x claude >/dev/null 2>&1 || pgrep -x opencode >/dev/null 2>&1"]
        onExited: (code, status) => { rootMod.claudeActive = (code === 0) }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { detectProc.running = false; detectProc.running = true }
    }

    Rectangle {
        anchors.centerIn: row
        width: row.width + 18
        height: 24; radius: 12
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
            text: String.fromCodePoint(0xF167A)
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
            font.family: root.mono
            font.pixelSize: 14
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.blocked ? "BLK"
                : String(rootMod.pct5h).padStart(2, "0") + "%"
            color: rootMod.pct5h >= 90 || rootMod.blocked ? root.seal
                 : rootMod.pct5h >= 80
                     ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.7)
                     : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    Process {
        id: readProc
        command: ["cat", Quickshell.env("HOME") + "/.cache/claude-usage.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text.trim())
                    rootMod.pct5h   = Math.round((parseFloat(d["5h-utilization"]) || 0) * 100)
                    rootMod.blocked = d.status === "rejected" || d.status === "blocked"
                    var pct7d = Math.round((parseFloat(d["7d-utilization"]) || 0) * 100)
                    rootMod.tooltipFull =
                        "Claude Code\n5h: " + rootMod.pct5h + "%\n7d: " + pct7d + "%"
                } catch (e) {
                    rootMod.pct5h    = 0
                    rootMod.tooltipFull = ""
                }
            }
        }
    }

    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { readProc.running = false; readProc.running = true }
    }

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
        onEntered: if (claudeActive) tipDelay.restart()
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod) }
    }
}
