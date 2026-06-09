import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property string profile: root.powerProfileCurrent

    readonly property bool isPowerSaver:  profile === "power-saver"
    readonly property bool isBalanced:    profile === "balanced"
    readonly property bool isPerformance: profile === "performance"

    readonly property string shortName: {
        if (isPowerSaver)  return "SAV"
        if (isPerformance) return "PRF"
        return "BAL"
    }

    readonly property string tooltipText: {
        if (isPowerSaver)  return "Power Saver"
        if (isPerformance) return "Performance"
        return "Balanced"
    }

    visible: implicitWidth > 0.5
    implicitWidth: root.modPower ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    clip: true
    opacity: root.modPower ? 1 : 0

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
            text: "PWR"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.shortName
            color: {
                if (rootMod.isPowerSaver)  return root.indigo
                if (rootMod.isPerformance) return root.seal
                return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            }
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    Process {
        id: profileProc
        command: ["bash", "-c", "powerprofilesctl get 2>/dev/null || echo balanced"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim()
                if (p) { rootMod.profile = p; root.powerProfileCurrent = p }
            }
        }
    }

    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { profileProc.running = false; profileProc.running = true }
    }

    Process {
        id: setProfileProc
        command: ["bash", "-c", "powerprofilesctl set balanced"]
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited: { tip.hide() }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) {
                var profiles = ["power-saver", "balanced", "performance"]
                var idx = profiles.indexOf(root.powerProfileCurrent)
                var next = profiles[(Math.max(0, idx) + 1) % profiles.length]
                setProfileProc.command = ["bash", "-c", "powerprofilesctl set " + next]
                setProfileProc.running = false; setProfileProc.running = true
                root.powerProfileCurrent = next
            } else {
                root.powerProfileVisible = !root.powerProfileVisible
            }
        }
    }
}
