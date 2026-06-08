import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    // awake = true  → idle inhibited (hypridle NOT running) → Stay Awake: ON
    // awake = false → idle active   (hypridle running)      → Stay Awake: OFF
    property bool awake: false

    implicitWidth: 22
    implicitHeight: 28

    readonly property string tooltipText: awake ? "Stay Awake: ON" : "Stay Awake: OFF"

    Text {
        anchors.centerIn: parent
        // 󰛨 U+F06E8 = activated / 󰛩 U+F06E9 = deactivated
        text: rootMod.awake ? String.fromCodePoint(0xF06E8) : String.fromCodePoint(0xF06E9)
        font.family: root.mono
        font.pixelSize: 14
        color: rootMod.awake
            ? root.seal
            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Process {
        id: stateProc
        command: ["bash", "-c", "pgrep -x hypridle >/dev/null && echo OFF || echo ON"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: { rootMod.awake = this.text.trim() === "ON" }
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { stateProc.running = false; stateProc.running = true }
    }

    Process { id: toggleProc; command: ["omarchy-toggle-idle"] }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited:  tip.hide()
        onClicked: {
            tip.hide()
            toggleProc.running = false; toggleProc.running = true
            Qt.callLater(function() { stateProc.running = false; stateProc.running = true })
        }
    }
}
