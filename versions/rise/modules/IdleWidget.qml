import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    // "stay awake" mode active when hypridle is NOT running
    property bool awake: false

    visible: awake
    implicitWidth: awake ? 20 : 0
    implicitHeight: 28

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    readonly property string tooltipText: "Idle lock disabled"

    Text {
        anchors.centerIn: parent
        text: "\uDB86\uDED6"   // coffee (Nerd Font / JetBrainsMono)
        color: root.seal
        font.family: root.mono
        font.pixelSize: 13
    }

    Process {
        id: idleProc
        command: ["bash", "-c", "pgrep -x hypridle >/dev/null && echo ON || echo OFF"]
        running: false
        stdout: StdioCollector {
            // hypridle ON → normal idle; OFF → stay-awake mode (show icon)
            onStreamFinished: { rootMod.awake = this.text.trim() === "OFF" }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { idleProc.running = false; idleProc.running = true }
    }

    Process { id: toggleProc; command: ["bash", "-c", "omarchy-toggle-idle"] }

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
            Qt.callLater(function() { idleProc.running = false; idleProc.running = true })
        }
    }
}
