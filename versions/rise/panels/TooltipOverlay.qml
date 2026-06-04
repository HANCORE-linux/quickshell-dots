import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: overlay
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tooltip"
    mask: Region {}

    readonly property int barBottom: 37
    readonly property int gap: 6

    property real reveal: root.tooltipShown ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.tooltipShown ? 160 : 120
            easing.type: root.tooltipShown ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001

    Rectangle {
        id: tip
        readonly property int padH: 10
        readonly property int padV: 4

        width: tipLabel.implicitWidth + padH * 2
        height: tipLabel.implicitHeight + padV * 2

        x: {
            var cx = root.tooltipX;
            return Math.max(4, Math.min(parent.width - width - 4, cx - width / 2));
        }
        y: barBottom + gap

        color: root.bg
        border.color: root.sep
        border.width: 1
        radius: 6
        opacity: overlay.reveal

        Text {
            id: tipLabel
            anchors.centerIn: parent
            text: root.tooltipText
            color: root.ink
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 1
        }
    }
}
