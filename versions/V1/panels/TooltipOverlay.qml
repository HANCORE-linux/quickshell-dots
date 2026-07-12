import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules"

PanelWindow {
    id: overlay
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    // "quickshell" (not "omarchy-tooltip") so the theme's match:namespace quickshell
    // blur rule frosts the tooltip too — same ride-the-theme mechanism as the bar.
    WlrLayershell.namespace: "quickshell"
    mask: Region {}

    readonly property int barBottom: 35
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

        width: Math.min(parent.width - 8, tipLabel.implicitWidth + padH * 2)
        height: tipLabel.implicitHeight + padV * 2

        x: {
            var cx = root.tooltipX;
            return Math.max(4, Math.min(parent.width - width - 4, cx - width / 2));
        }
        y: {
            var cy = root.tooltipY;
            return Math.max(4, Math.min(parent.height - height - 4, cy - height / 2));
        }

        color: root.barBg   // frosts with the bar's Frost toggle (0.68 ⇄ 0.94)
        border.color: root.pillBorder
        border.width: root.pillBorderW
        radius: 6
        opacity: overlay.reveal

        // border-less style → drop the border, drop a dark shadow (same as pills)
        PillShadow { theme: root }

        UiText {
            id: tipLabel
            anchors.centerIn: parent
            text: root.tooltipText
            color: root.ink
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 1
            width: parent.width - tip.padH * 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
