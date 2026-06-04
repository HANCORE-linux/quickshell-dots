import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris

PanelWindow {
    id: mprisPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-mpris"

    readonly property int barBottom: 37
    readonly property int gap: 8

    readonly property var player: {
        var vals = Mpris.players.values
        var paused = null
        for (var i = 0; i < vals.length; i++) {
            var p = vals[i]
            if (p.playbackState === MprisPlaybackState.Playing) return p
            if (p.playbackState === MprisPlaybackState.Paused && paused === null) paused = p
        }
        return paused
    }
    readonly property bool active:  player !== null
    readonly property bool playing: active && player.playbackState === MprisPlaybackState.Playing

    property real reveal: root.mprisVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.mprisVisible ? 160 : 120
            easing.type: root.mprisVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.mprisVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.mprisVisible = false }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: parent.width - width - 6
        y: barBottom + gap
        opacity: mprisPanel.reveal
        focus: root.mprisVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.mprisVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Now Playing"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: root.sumi; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.mprisVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── track info ──
            Column {
                width: parent.width
                spacing: 3
                visible: mprisPanel.active
                Text {
                    width: parent.width
                    text: mprisPanel.active ? (mprisPanel.player.trackTitle || "Unknown") : ""
                    color: root.ink; font.family: root.mono; font.pixelSize: 12; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: mprisPanel.active ? (mprisPanel.player.trackArtist || "") : ""
                    color: root.sumi; font.family: root.mono; font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text !== ""
                }
                Text {
                    width: parent.width
                    text: mprisPanel.active ? (mprisPanel.player.trackAlbum || "") : ""
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
                    font.family: root.mono; font.pixelSize: 10
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }

            Text {
                visible: !mprisPanel.active
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Nothing playing"
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                font.family: root.mono; font.pixelSize: 11
            }

            // ── controls ──
            Row {
                visible: mprisPanel.active
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                Text {
                    text: "\uE045"
                    font.family: "Material Symbols Rounded"; font.pixelSize: 20
                    color: (mprisPanel.active && mprisPanel.player.canGoPrevious) ? root.ink : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mprisPanel.player) mprisPanel.player.previous() }
                }
                Text {
                    text: mprisPanel.playing ? "\uE034" : "\uE037"
                    font.family: "Material Symbols Rounded"; font.pixelSize: 24
                    color: root.seal
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mprisPanel.player) mprisPanel.player.togglePlaying() }
                }
                Text {
                    text: "\uE044"
                    font.family: "Material Symbols Rounded"; font.pixelSize: 20
                    color: (mprisPanel.active && mprisPanel.player.canGoNext) ? root.ink : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (mprisPanel.player) mprisPanel.player.next() }
                }
            }
        }
    }
}
