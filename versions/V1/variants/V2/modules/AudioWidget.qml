import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    AudioData { id: audio; poll: true }
    readonly property int    volume:   audio.volume
    readonly property bool   muted:    audio.muted
    readonly property string volumeIcon: "graphic_eq"
    readonly property color contentColor: root.widgetContentColor("G6", root.widgetIconColor)

    readonly property string tooltipText: muted
        ? "Muted · " + volume + "%"
        : "Audio " + volume + "%"

    visible: implicitWidth > 0.5
    implicitWidth: root.modVolume ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modVolume ? 1 : 0
    Behavior on opacity      { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        IconText {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.volumeIcon
            color: rootMod.muted
                ? Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.35)
                : rootMod.contentColor
            font.pixelSize: 15
            font.weight: Font.Medium
            fill: 1
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        UiText {
            visible: !root.iconOnly("G6")
            anchors.verticalCenter: parent.verticalCenter
            text: String(rootMod.volume).padStart(2, '0') + "%"
            color: rootMod.muted
                ? Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.35)
                : rootMod.contentColor
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 160 } }
        }

    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    property bool audioErrorNotified: false
    property int pendingVolumeSteps: 0

    readonly property string muteCommand:
        "(command -v omarchy-swayosd-client >/dev/null 2>&1 && omarchy-swayosd-client --output-volume mute-toggle) || " +
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle || " +
        "pamixer -t"

    function volumeCommand(steps) {
        var amount = Math.min(100, Math.abs(steps) * 5)
        var up = steps > 0
        return "wpctl set-volume " + (up ? "-l 1.0 " : "") + "@DEFAULT_AUDIO_SINK@ " + amount + "%" + (up ? "+" : "-") + " || " +
            "pamixer " + (up ? "--increase " : "--decrease ") + amount
    }

    function runPendingVolumeCommand() {
        if (volumeRunner.running || pendingVolumeSteps === 0) return
        var steps = pendingVolumeSteps
        pendingVolumeSteps = 0
        volumeRunner.action = steps > 0 ? "Volume up" : "Volume down"
        volumeRunner.command = ["bash", "-c", volumeCommand(steps)]
        volumeRunner.running = true
    }

    function queueVolumeStep(step) {
        pendingVolumeSteps += step
        runPendingVolumeCommand()
    }

    function notifyAudioError(action, exitCode) {
        if (exitCode === 0 || audioErrorNotified) return
        audioErrorNotified = true
        audioErrNotify.command = ["bash", "-c",
            "notify-send -a 'QS-Shell' 'Audio command failed' '" + action + " failed; audio backend unavailable.' 2>/dev/null || true"]
        audioErrNotify.running = false
        audioErrNotify.running = true
    }

    Process { id: audioErrNotify }
    Process {
        id: muteRunner
        command: ["bash", "-c", rootMod.muteCommand]
        onExited: (code) => {
            rootMod.notifyAudioError("Mute", code)
            audio.refresh()
        }
    }
    Process {
        id: volumeRunner
        property string action: ""
        onExited: (code) => {
            rootMod.notifyAudioError(action, code)
            audio.refresh()
            rootMod.runPendingVolumeCommand()
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited: { tip.hide() }
        onWheel: (e) => {
            rootMod.queueVolumeStep(e.angleDelta.y > 0 ? 1 : -1)
        }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) { if (!muteRunner.running) muteRunner.running = true }
            else                             { root.volVisible = !root.volVisible }
        }
    }
}
