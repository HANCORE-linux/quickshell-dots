import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property bool silenced: false

    visible: silenced
    implicitWidth: silenced ? 20 : 0
    implicitHeight: 28

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    readonly property string tooltipText: "Notifications silenced"

    Text {
        anchors.centerIn: parent
        text: "\uE7F6"   // notifications_off
        color: root.seal
        font.family: "Material Symbols Rounded"
        font.pixelSize: 14
    }

    Process {
        id: dndProc
        command: ["bash", "-c", "makoctl mode 2>/dev/null | grep -q 'do-not-disturb' && echo ON || echo OFF"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: { rootMod.silenced = this.text.trim() === "ON" }
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { dndProc.running = false; dndProc.running = true }
    }

    Process { id: toggleProc; command: ["bash", "-c", "omarchy-toggle-notification-silencing"] }

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
            Qt.callLater(function() { dndProc.running = false; dndProc.running = true })
        }
    }
}
