import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: rootMod
    required property var root

    implicitWidth: logoContentWidth + logoPadding
    implicitHeight: 28

    readonly property string tooltipText: "Control center"
    readonly property bool logoIconMode: root.launcherLogoMode === "icon"
    readonly property bool hyprlandLogo: !logoIconMode && root.launcherLogoText === "hyprland"
    readonly property bool archTextLogo: !logoIconMode && root.launcherLogoText === "arch"
    readonly property bool omacomTextLogo: !logoIconMode && root.launcherLogoText === "omacom"
    readonly property url logoSource: omacomTextLogo ? Qt.resolvedUrl("../assets/omacom-text.png") : hyprlandLogo ? Qt.resolvedUrl("../assets/bob3.png") : Qt.resolvedUrl("../assets/bob2.png")
    readonly property real logoAspect: omacomTextLogo ? (550 / 112) : archTextLogo ? (86 / 17) : hyprlandLogo ? (948 / 154) : (656 / 192)
    readonly property real logoHeight: logoIconMode ? 18 : hyprlandLogo ? 16 : omacomTextLogo ? 14 : archTextLogo ? 17 : 20
    readonly property real logoPadding: logoIconMode ? 8 : hyprlandLogo ? 10 : omacomTextLogo ? 12 : archTextLogo ? 8 : 12
    readonly property real archWordHeight: 13
    readonly property real archWordLogoWidth: 15
    readonly property real archWordLeftPad: 1
    readonly property real archWordRightPad: 3
    readonly property real archWordGap: 3
    readonly property real archWordJoinGap: 3
    readonly property real archWordArchWidth: Math.round(archWordHeight * 605 / 231)
    readonly property real archWordLinuxWidth: Math.round(archWordHeight * 549 / 230)
    readonly property real archWordmarkWidth: archWordLeftPad + archWordRightPad + archWordLogoWidth + archWordGap + archWordArchWidth + archWordJoinGap + archWordLinuxWidth
    readonly property real logoImageWidth: archTextLogo ? archWordmarkWidth : Math.round(logoHeight * logoAspect)
    readonly property real logoIconSlotWidth: 16
    readonly property real logoContentWidth: logoIconMode ? logoIconSlotWidth : logoImageWidth
    readonly property color contentColor: root.widgetContentColor("G1", root.seal)
    readonly property color archBrandTextColor: root.widgetHasFill("G1")
        ? contentColor
        : root.barColorIsAccent ? root.sealRaw : root.accentHint

    // animated wave phase
    property real phase: 0
    NumberAnimation on phase {
        from: 0; to: 2 * Math.PI
        duration: 2600; loops: Animation.Infinite
        // gate: only animate while hovered or control panel open — otherwise the
        // Canvas repainted 24/7 via onPhaseChanged even when nobody looks
        running: ma.containsMouse || root.controlVisible
    }

    // ── hover-wave container (invisible surface, clips the wave to the logo area) ──
    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: rootMod.logoContentWidth + rootMod.logoPadding
        height: root.pillH
        color: "transparent"
        border.width: 0
        clip: true

        Canvas {
            id: wave
            anchors.fill: parent
            // only present while active (hovered or control panel open); fully
            // gone when idle. Fades so it appears/disappears smoothly.
            opacity: (ma.containsMouse || root.controlVisible) ? 0.55 : 0
            visible: opacity > 0.001
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var cy = height / 2
                var amp = 3.0
                var k = (2 * Math.PI) / width * 2   // two cycles across the width

                function drawWave(phaseOff, alpha) {
                    ctx.beginPath()
                    for (var x = 0; x <= width; x += 2) {
                        var y = cy + Math.sin(x * k + rootMod.phase + phaseOff) * amp
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.strokeStyle = Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, alpha)
                    ctx.lineWidth = 1.5
                    ctx.lineCap = "round"
                    ctx.stroke()
                }

                drawWave(0,       0.45)
                drawWave(Math.PI, 0.22)
            }

            Connections {
                target: rootMod
                function onPhaseChanged() { wave.requestPaint() }
            }
            Connections {
                target: root
                function onSealChanged() { wave.requestPaint() }
                function onWidgetColorStylesChanged() { wave.requestPaint() }
            }
            Component.onCompleted: requestPaint()
        }
    }

    // ── launcher logo: flat-color tint shader — exact seal color, keeps alpha ──
    Item {
        id: logoStack
        visible: !rootMod.logoIconMode
        anchors.centerIn: parent
        width: rootMod.logoImageWidth
        height: rootMod.logoHeight

        Item {
            id: archBrand
            visible: rootMod.archTextLogo
            anchors.centerIn: parent
            width: parent.width
            height: parent.height

            UiText {
                id: archBrandLogo
                anchors.left: parent.left
                anchors.leftMargin: rootMod.archWordLeftPad
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 0.5
                width: rootMod.archWordLogoWidth
                horizontalAlignment: Text.AlignHCenter
                text: ""
                color: rootMod.contentColor
                renderType: Text.QtRendering
                font.family: root.mono
                font.pixelSize: 15
            }

            Image {
                id: archBrandArch
                anchors.left: archBrandLogo.right
                anchors.leftMargin: rootMod.archWordGap
                anchors.verticalCenter: parent.verticalCenter
                width: rootMod.archWordArchWidth
                height: rootMod.archWordHeight
                source: Qt.resolvedUrl("../assets/arch-header-arch.png")
                fillMode: Image.PreserveAspectFit
                cache: false
                smooth: true
                mipmap: true
                layer.enabled: visible
                layer.smooth: true
                layer.textureSize: Qt.size(Math.max(1, Math.round(width * 3)), Math.max(1, Math.round(height * 3)))
                layer.effect: ShaderEffect {
                    property color tintColor: rootMod.archBrandTextColor
                    fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
                }
            }

            Image {
                anchors.left: archBrandArch.right
                anchors.leftMargin: rootMod.archWordJoinGap
                anchors.verticalCenter: parent.verticalCenter
                width: rootMod.archWordLinuxWidth
                height: rootMod.archWordHeight
                source: Qt.resolvedUrl("../assets/arch-header-linux.png")
                fillMode: Image.PreserveAspectFit
                cache: false
                smooth: true
                mipmap: true
                layer.enabled: visible
                layer.smooth: true
                layer.textureSize: Qt.size(Math.max(1, Math.round(width * 3)), Math.max(1, Math.round(height * 3)))
                layer.effect: ShaderEffect {
                    property color tintColor: rootMod.contentColor
                    fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
                }
            }
        }

        Image {
            id: logo
            visible: !rootMod.archTextLogo
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            source: rootMod.logoSource
            fillMode: Image.PreserveAspectFit
            cache: false
            smooth: true
            mipmap: true
            layer.enabled: !rootMod.logoIconMode
            layer.smooth: true
            layer.textureSize: Qt.size(Math.max(1, Math.round(width * 3)), Math.max(1, Math.round(height * 3)))   // supersample → crisp
            layer.effect: ShaderEffect {
                property color tintColor: rootMod.contentColor
                fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
            }
        }
    }

    Item {
        id: logoIconSlot
        visible: rootMod.logoIconMode
        anchors.centerIn: parent
        width: rootMod.logoIconSlotWidth
        height: root.pillH

        UiText {
            id: logoIcon
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.launcherLogoIconXOffset(root.launcherLogoIcon)
            anchors.verticalCenterOffset: root.launcherLogoIconYOffset(root.launcherLogoIcon)
            text: root.launcherLogoIconGlyph(root.launcherLogoIcon)
            color: rootMod.contentColor
            renderType: Text.QtRendering
            font.family: root.launcherLogoIconFont(root.launcherLogoIcon)
            font.pixelSize: root.launcherLogoIconSize(root.launcherLogoIcon)
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: {
            tip.hide()
            root.controlVisible = !root.controlVisible
        }
    }
}
