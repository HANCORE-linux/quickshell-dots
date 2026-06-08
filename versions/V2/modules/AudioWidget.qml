import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    AudioData { id: audio; poll: true }
    readonly property int    volume:   audio.volume
    readonly property bool   muted:    audio.muted
    readonly property string portType: audio.portType

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

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    Process { id: muteRunner;    command: ["bash", "-c", "pamixer -t"] }
    Process { id: volUpRunner;   command: ["bash", "-c", "pamixer --increase 5"] }
    Process { id: volDownRunner; command: ["bash", "-c", "pamixer --decrease 5"] }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited: { tip.hide() }
        onWheel: (e) => {
            if (e.angleDelta.y > 0) { volUpRunner.running = false; volUpRunner.running = true }
            else                    { volDownRunner.running = false; volDownRunner.running = true }
            audio.refresh()
        }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) { muteRunner.running = false; muteRunner.running = true }
            else                             { root.volVisible = !root.volVisible }
        }
    }
}
