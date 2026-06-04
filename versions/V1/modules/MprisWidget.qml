import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: rootMod
    required property var root

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

    readonly property string trackLabel: {
        if (!active) return ""
        var t = player.trackTitle  || ""
        var a = player.trackArtist || ""
        return a ? t + "  ·  " + a : t
    }

    // ── equalizer bar heights (0.0 – 1.0) ──
    property real barH1: 0.08
    property real barH2: 0.08
    property real barH3: 0.08

    // bounce sequences — regular animations with explicit target, no PVS conflict
    SequentialAnimation {
        id: anim1
        running: rootMod.playing; loops: Animation.Infinite
        NumberAnimation { target: rootMod; property: "barH1"; to: 0.85; duration: 220; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH1"; to: 0.18; duration: 300; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH1"; to: 0.70; duration: 260; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH1"; to: 0.10; duration: 280; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: anim2
        running: rootMod.playing; loops: Animation.Infinite
        NumberAnimation { target: rootMod; property: "barH2"; to: 0.45; duration: 310; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH2"; to: 0.92; duration: 280; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH2"; to: 0.28; duration: 340; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH2"; to: 0.65; duration: 290; easing.type: Easing.InOutSine }
    }
    SequentialAnimation {
        id: anim3
        running: rootMod.playing; loops: Animation.Infinite
        NumberAnimation { target: rootMod; property: "barH3"; to: 0.60; duration: 380; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH3"; to: 0.12; duration: 320; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH3"; to: 0.95; duration: 350; easing.type: Easing.InOutSine }
        NumberAnimation { target: rootMod; property: "barH3"; to: 0.32; duration: 400; easing.type: Easing.InOutSine }
    }

    // drop bars to rest when paused
    ParallelAnimation {
        id: dropAnim
        NumberAnimation { target: rootMod; property: "barH1"; to: 0.08; duration: 380; easing.type: Easing.OutCubic }
        NumberAnimation { target: rootMod; property: "barH2"; to: 0.08; duration: 430; easing.type: Easing.OutCubic }
        NumberAnimation { target: rootMod; property: "barH3"; to: 0.08; duration: 480; easing.type: Easing.OutCubic }
    }
    onPlayingChanged: { if (!playing) dropAnim.restart() }

    implicitWidth: active ? (row.implicitWidth + 18) : 0
    implicitHeight: 28
    clip: true

    Behavior on implicitWidth {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.centerIn: row
        width: row.implicitWidth + 18
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        // ── prev ──
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: "Material Symbols Rounded"
            font.pixelSize: 13
            color: (rootMod.active && rootMod.player.canGoPrevious)
                ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: if (rootMod.player) rootMod.player.previous()
            }
        }

        // ── play / pause ──
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.playing ? "" : ""
            font.family: "Material Symbols Rounded"
            font.pixelSize: 13
            color: root.seal
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: if (rootMod.player) rootMod.player.togglePlaying()
            }
        }

        // ── next ──
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: "Material Symbols Rounded"
            font.pixelSize: 13
            color: (rootMod.active && rootMod.player.canGoNext)
                ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)
            Behavior on color { ColorAnimation { duration: 150 } }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: if (rootMod.player) rootMod.player.next()
            }
        }

        // ── marquee title ──
        Item {
            id: marqueeClip
            implicitWidth: 88
            width: 88
            height: 28
            clip: true
            anchors.verticalCenter: parent.verticalCenter

            Text {
                id: marqueeText
                anchors.verticalCenter: parent.verticalCenter
                text: rootMod.trackLabel
                color: rootMod.playing
                    ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
                font.family: root.mono
                font.pixelSize: 12
                x: 0
                Behavior on color { ColorAnimation { duration: 200 } }
                onTextChanged: marqueeClip.resetMarquee()
            }

            function resetMarquee() {
                marqueeAnim.stop()
                marqueeText.x = 0
                if (rootMod.playing && marqueeText.implicitWidth > marqueeClip.width)
                    marqueeAnim.start()
            }

            Connections {
                target: rootMod
                function onPlayingChanged() { marqueeClip.resetMarquee() }
            }

            SequentialAnimation {
                id: marqueeAnim
                loops: Animation.Infinite
                PauseAnimation  { duration: 2000 }
                NumberAnimation {
                    target: marqueeText; property: "x"
                    to: -(marqueeText.implicitWidth - marqueeClip.width + 4)
                    duration: Math.max(100, marqueeText.implicitWidth - marqueeClip.width + 4) * 20
                    easing.type: Easing.Linear
                }
                PauseAnimation  { duration: 900 }
                NumberAnimation { target: marqueeText; property: "x"; to: 0; duration: 0 }
            }
        }

        // ── equalizer canvas ──
        Canvas {
            id: eqCanvas
            implicitWidth: 16
            width: 16
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var bars   = [rootMod.barH1, rootMod.barH2, rootMod.barH3]
                var bw     = 3
                var gap    = 2
                var totalW = bars.length * bw + (bars.length - 1) * gap
                var startX = (width - totalW) / 2
                var maxH   = height - 1
                var r      = bw / 2

                ctx.fillStyle = root.seal.toString()

                for (var i = 0; i < bars.length; i++) {
                    var bh = Math.max(r * 2, bars[i] * maxH)
                    var x  = startX + i * (bw + gap)
                    var y  = height - bh

                    ctx.beginPath()
                    ctx.moveTo(x + r, y)
                    ctx.lineTo(x + bw - r, y)
                    ctx.arcTo(x + bw, y,      x + bw, y + r,      r)
                    ctx.lineTo(x + bw, y + bh - r)
                    ctx.arcTo(x + bw, y + bh, x + bw - r, y + bh, r)
                    ctx.lineTo(x + r,  y + bh)
                    ctx.arcTo(x,       y + bh, x, y + bh - r,      r)
                    ctx.lineTo(x, y + r)
                    ctx.arcTo(x, y,    x + r,  y,                   r)
                    ctx.closePath()
                    ctx.fill()
                }
            }

            Connections {
                target: rootMod
                function onBarH1Changed() { eqCanvas.requestPaint() }
                function onBarH2Changed() { eqCanvas.requestPaint() }
                function onBarH3Changed() { eqCanvas.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }

    readonly property string tooltipText: active
        ? (player.trackArtist ? player.trackArtist + " — " + player.trackTitle : player.trackTitle)
        : ""

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            if (!rootMod.tooltipText) return
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.RightButton
        onEntered: { if (rootMod.tooltipText) tipDelay.restart() }
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: { tipDelay.stop(); root.hideTooltip(rootMod); root.mprisVisible = !root.mprisVisible }
    }
}
