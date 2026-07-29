import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G8", root.seal)

    property bool updateAvailable: false

    visible: updateAvailable
    implicitWidth: updateAvailable ? 20 : 0
    implicitHeight: 28


    readonly property string tooltipText: "Omarchy update available"

    IconText {
        anchors.centerIn: parent
        text: "\uE627"   // sync
        color: rootMod.contentColor
        font.pixelSize: 15
    }

    Process {
        id: updateProc
        command: ["bash", "-c", "omarchy-update-available >/dev/null 2>&1 && echo YES || echo NO"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: { rootMod.updateAvailable = this.text.trim() === "YES" }
        }
    }

    Timer {
        interval: 21600000   // 6h
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: { updateProc.running = false; updateProc.running = true }
    }

    Process { id: runProc; command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation omarchy-update"] }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: {
            tip.hide()
            runProc.running = false; runProc.running = true
        }
    }
}
