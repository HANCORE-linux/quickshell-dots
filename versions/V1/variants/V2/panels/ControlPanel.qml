import QtQuick
import Quickshell
import Quickshell.Wayland
import "../modules"

PanelWindow {
    id: ctrlPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-control"
    // no mask → whole overlay is interactive (modal): click-outside + ESC work

    readonly property int barBottom: root.v2BarHeight
    readonly property int gap: 6

    // power sub-menu starts CLOSED — no destructive tile is ever pre-shown
    property bool powerOpen: false
    property bool wsOpen: false   // Workspaces collapsible inside the WW fly-out
    property string widgetColorMenuGid: ""
    property string widgetColorMenuLabel: ""
    readonly property string barctlPath: Quickshell.env("HOME") + "/.config/quickshell/bin/qs-barctl"

    function switchBar(version) {
        root.controlVisible = false
        if (root.variantHost)
            root.variantHost.requestSwitch(version)
        else
            Quickshell.execDetached([barctlPath, "switch", version])
    }

    property real reveal: root.controlVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.controlVisible ? 160 : 120
            easing.type: root.controlVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    onRevealChanged: if (reveal < 0.01) {
        powerOpen = false
        wsOpen = false
        widgetColorMenuGid = ""
        widgetColorMenuLabel = ""
        root.wwSubVisible = false
    }
    WlrLayershell.keyboardFocus: root.controlVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── reusable tile: neutral by default, highlights only on hover ──
    component Tile: Rectangle {
        property string label
        property color accent: root.seal
        property bool active: false
        signal activated()
        height: 25
        radius: root.panelButtonRadius
        opacity: enabled ? 1.0 : 0.4          // built-in `enabled` also blocks input
        color: active ? Qt.rgba(accent.r, accent.g, accent.b, root.fillActiveAlpha) : _ma.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, root.fillHoverAlpha) : root.fillIdle
        border.color: (active || _ma.containsMouse) ? accent : root.sep
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: (parent.active || _ma.containsMouse) ? parent.accent : root.ink
            font.family: root.mono; font.pixelSize: 11
        }
        MouseArea {
            id: _ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    // ── one quiet tile: body toggles visibility, trailing state toggles density ──
    component WidgetStateTile: Rectangle {
        property string gid
        property string label
        property bool shown: true
        property bool canHide: true
        property bool supportsCompact: false
        property bool compact: false
        property string modeOffLabel: "Full"
        property string modeOnLabel: "Icon"
        signal visibilityToggled()
        signal modeToggled()

        readonly property bool hovered: bodyMa.containsMouse || colorMa.containsMouse
            || eyeMa.containsMouse || modeMa.containsMouse
        readonly property bool interactive: gid !== "" || canHide || (shown && supportsCompact)

        height: 27
        radius: root.panelButtonRadius
        opacity: interactive ? 1 : 0.4
        color: root.fillIdle
        border.color: hovered ? root.seal : root.sep
        border.width: 1

        UiText {
            id: widgetLabel
            anchors.left: parent.left; anchors.leftMargin: 8
            anchors.right: stateArea.left; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent.shown ? root.ink : root.sumi
            font.family: root.mono
            font.pixelSize: 10
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Item {
            id: stateArea
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 88

            IconText {
                id: colorChip
                readonly property bool open:
                    ctrlPanel.widgetColorMenuGid === stateArea.parent.gid
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 25
                horizontalAlignment: Text.AlignHCenter
                text: "palette"
                color: root.widgetHasFill(stateArea.parent.gid)
                    ? root.widgetAssignedColor(stateArea.parent.gid)
                    : (colorMa.containsMouse || open ? root.seal : root.sumiHi)
                font.pixelSize: 15
                font.weight: Font.Normal
                scale: colorMa.containsMouse ? 1.04 : 1.0
                z: colorMa.containsMouse || open ? 1 : 0
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
            }

            IconText {
                id: eyeGlyph
                anchors.left: colorChip.right
                anchors.verticalCenter: parent.verticalCenter
                width: 25
                horizontalAlignment: Text.AlignHCenter
                text: stateArea.parent.shown ? "visibility" : "visibility_off"
                color: eyeMa.containsMouse ? root.seal : stateArea.parent.shown ? root.sumiHi : root.sumi
                font.pixelSize: 15
                opacity: stateArea.parent.canHide ? 1 : 0.4
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            UiText {
                id: modeLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                horizontalAlignment: Text.AlignHCenter
                visible: stateArea.parent.supportsCompact
                text: stateArea.parent.compact
                    ? stateArea.parent.modeOnLabel
                    : stateArea.parent.modeOffLabel
                color: modeMa.containsMouse || (stateArea.parent.shown && stateArea.parent.compact) ? root.seal : root.sumiHi
                font.family: root.mono; font.pixelSize: 10
                opacity: stateArea.parent.shown ? 1 : 0.4
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            MouseArea {
                id: colorMa
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 25
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (ctrlPanel.widgetColorMenuGid === stateArea.parent.gid) {
                        ctrlPanel.widgetColorMenuGid = ""
                        ctrlPanel.widgetColorMenuLabel = ""
                    } else {
                        ctrlPanel.widgetColorMenuGid = stateArea.parent.gid
                        ctrlPanel.widgetColorMenuLabel = stateArea.parent.label
                    }
                }
            }
            MouseArea {
                id: eyeMa
                anchors.left: colorMa.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 25
                enabled: stateArea.parent.canHide
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: stateArea.parent.visibilityToggled()
            }
            MouseArea {
                id: modeMa
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 38
                enabled: stateArea.parent.shown && stateArea.parent.supportsCompact
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: stateArea.parent.modeToggled()
            }
        }

        MouseArea {
            id: bodyMa
            anchors.left: parent.left
            anchors.right: stateArea.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            enabled: parent.canHide
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.visibilityToggled()
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.controlVisible = false }

    Rectangle {
        id: card
        width: 240
        height: col.implicitHeight + 24
        radius: ctrlPanel.reveal > 0.001 ? root.panelRadius : 0
        color: "transparent"
        border.color: root.panelOuterBorderColor
        border.width: 0
        PillShadow { theme: root }
        ConnectedPanelSurface {
            root: ctrlPanel.root
            ownerActive: ctrlPanel.root.controlVisible
            targetX: ctrlPanel.root.launcherBarX
            reveal: ctrlPanel.reveal
        }

        x: Math.round(Math.max(6, Math.min(root.launcherBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom"
            ? (parent.height - barBottom - gap - height) + 2 * (1 - ctrlPanel.reveal)
            : (barBottom + gap) - 2 * (1 - ctrlPanel.reveal)
        opacity: ctrlPanel.reveal
        focus: root.controlVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.controlVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── header ──
            Item {
                width: parent.width
                height: 24
                UiText {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Control"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                UiText {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: closeMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.controlVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── ACTIONS ──
            UiText {
                text: "ACTIONS"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Grid {
                width: parent.width
                columns: 3
                columnSpacing: 6
                Tile {
                    width: root.evenW((col.width - 12) / 3)
                    label: "Reload"
                    onActivated: { root.controlVisible = false; Quickshell.reload(false) }
                }
                Tile {
                    width: root.evenW((col.width - 12) / 3)
                    label: "V1"
                    active: root.variantHost ? root.variantHost.runningVariant === "v1" : false
                    enabled: root.variantHost ? !root.variantHost.switching && root.variantHost.runningVariant !== "v1" : true
                    opacity: active ? 1.0 : (enabled ? 1.0 : 0.4)
                    onActivated: ctrlPanel.switchBar("v1")
                }
                Tile {
                    width: root.evenW((col.width - 12) / 3)
                    label: "V2"
                    active: root.variantHost ? root.variantHost.runningVariant === "v2" : true
                    enabled: root.variantHost ? !root.variantHost.switching && root.variantHost.runningVariant !== "v2" : false
                    opacity: active ? 1.0 : (enabled ? 1.0 : 0.4)
                    onActivated: ctrlPanel.switchBar("v2")
                }
            }

            // ── POWER (collapsed sub-menu; nothing destructive pre-shown) ──
            Tile {
                width: parent.width
                label: ctrlPanel.powerOpen ? "Power  ▾" : "Power  ▸"
                accent: root.seal
                onActivated: ctrlPanel.powerOpen = !ctrlPanel.powerOpen
            }
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                visible: ctrlPanel.powerOpen
                Tile {
                    width: root.evenW((col.width - 8) / 2)
                    label: "Lock"
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["hyprlock"]) }
                }
                Tile {
                    width: root.evenW((col.width - 8) / 2)
                    label: "Suspend"
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["systemctl", "suspend"]) }
                }
                Tile {
                    width: root.evenW((col.width - 8) / 2)
                    label: "Reboot"
                    accent: root.indigo
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["systemctl", "reboot"]) }
                }
                Tile {
                    width: root.evenW((col.width - 8) / 2)
                    label: "Shutdown"
                    accent: root.seal
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["systemctl", "poweroff"]) }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── BAR COLOR: compact colors.toml palette ──
            UiText {
                text: "BAR COLOR"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Grid {
                width: parent.width
                columns: 4
                columnSpacing: 6
                rowSpacing: 6
                Repeater {
                    model: root.barColorOptions
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool on: root.barColor === modelData
                        readonly property bool hovered: _cma.containsMouse
                        width: root.evenW((col.width - 18) / 4)
                        height: 24
                        radius: root.panelButtonRadius
                        color: root.paletteColor(modelData)
                        border.color: root.sep
                        border.width: 1
                        scale: hovered ? 1.04 : 1.0
                        z: hovered ? 1 : 0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        UiText {
                            anchors.centerIn: parent
                            text: modelData === "foreground" ? "FG" : modelData.slice(-2)
                            color: root.paletteContrastColor(modelData)
                            font.family: root.mono
                            font.pixelSize: 9
                            font.weight: Font.Medium
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 18
                            height: 2
                            radius: 1
                            visible: parent.on
                            color: root.paletteContrastColor(modelData)
                        }
                        MouseArea {
                            id: _cma
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.barColor = modelData
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── BAR FUNCTIONS (opens the fly-out sub-panel) ──
            UiText {
                text: "BAR FUNCTIONS"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Tile {
                width: parent.width
                label: root.wwSubVisible ? "Bar Functions  ◂" : "Bar Functions  ▸"
                active: root.wwSubVisible
                onActivated: root.wwSubVisible = !root.wwSubVisible
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── PICKER style (theme/wallpaper/screenshot/video picker visual) ──
            UiText {
                text: "PICKER-STIL"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                id: pickerRow
                width: parent.width
                spacing: 4
                readonly property var opts: [
                    { label: "Tanzaku",     mode: "tanzaku"     },
                    { label: "Hearthstone", mode: "hearthstone" },
                    { label: "Carousel",    mode: "carousel"    }
                ]
                // Tiles are sized to their label width (mono → length × charW)
                // plus an equal share of the leftover space, so every tile gets
                // the same side padding. Fixed 1/3-each made the long "Hearthstone"
                // label touch its borders while the short labels had slack.
                TextMetrics { id: pickMetrics; font.family: root.mono; font.pixelSize: 10; text: "0" }
                readonly property real charW: pickMetrics.advanceWidth
                readonly property real sumTextW: {
                    var n = 0;
                    for (var i = 0; i < opts.length; i++) n += opts[i].label.length;
                    return n * charW;
                }
                readonly property real padEach: Math.max(0, (width - spacing * (opts.length - 1) - sumTextW) / (opts.length * 2))
                Repeater {
                    model: pickerRow.opts
                    delegate: Rectangle {
                        id: pickTile
                        required property var modelData
                        readonly property bool on:      root.pickerStyle === modelData.mode
                        readonly property bool hovered: pickMa.containsMouse
                        width: root.evenW(modelData.label.length * pickerRow.charW + pickerRow.padEach * 2)
                        height: 25; radius: root.panelButtonRadius
                        color: on ? root.fillActive : hovered ? root.fillHover : root.fillIdle
                        border.color: (on || hovered) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: pickTile.modelData.label
                            color: (pickTile.on || pickTile.hovered) ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 10
                            font.weight: pickTile.on ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            id: pickMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pickerStyle = pickTile.modelData.mode
                        }
                    }
                }
            }

        }
    }

    // ── BAR FUNCTIONS sub-panel ──
    Rectangle {
        id: wwCard
        visible: root.controlVisible && root.wwSubVisible
        width: 320
        height: wwCol.implicitHeight + 24
        radius: (root.controlVisible && root.wwSubVisible) ? root.panelRadius : 0
        color: root.bg
        border.color: root.panelOuterBorderColor
        border.width: root.panelOuterBorderW
        PillShadow { theme: root }
        // open to the right of the card, or to the left if there is no room
        x: (card.x + card.width + ctrlPanel.gap + width <= parent.width - 6)
           ? card.x + card.width + ctrlPanel.gap
           : card.x - ctrlPanel.gap - width
        y: root.barPosition === "bottom" ? card.y + card.height - height : card.y
        opacity: ctrlPanel.reveal

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: wwCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            UiText {
                text: "LAYOUT"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                width: parent.width
                spacing: 4
                Tile {
                    width: root.evenW((wwCol.width - 4) / 2)
                    label: "Edit slots"
                    accent: root.seal
                    onActivated: {
                        root.controlVisible = false
                        root.barUnlocked = true
                    }
                }
                Tile {
                    width: root.evenW((wwCol.width - 4) / 2)
                    label: "Default layout"
                    onActivated: if (root.fnDefaultLayout) root.fnDefaultLayout()
                }
            }
            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── WIDGETS: one tile per widget, two quiet interaction zones ──
            UiText {
                text: "WIDGETS"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 4
                rowSpacing: 4
                WidgetStateTile { gid: "G1";  width: root.evenW((wwCol.width - 4) / 2); label: "Launcher";      shown: true; canHide: false }
                WidgetStateTile { gid: "G2";  width: root.evenW((wwCol.width - 4) / 2); label: "Workspaces";    shown: true; canHide: false }
                WidgetStateTile { gid: "G3";  width: root.evenW((wwCol.width - 4) / 2); label: "Status";        shown: root.modStatus;          onVisibilityToggled: root.modStatus = !root.modStatus }
                WidgetStateTile { gid: "G4";  width: root.evenW((wwCol.width - 4) / 2); label: "Memory";        shown: root.modMemory;          supportsCompact: true; compact: root.iconOnly("G4");  onVisibilityToggled: root.modMemory = !root.modMemory; onModeToggled: root.toggleIconOnly("G4") }
                WidgetStateTile { gid: "G5";  width: root.evenW((wwCol.width - 4) / 2); label: "CPU";           shown: root.modCpu;             supportsCompact: true; compact: root.iconOnly("G5");  onVisibilityToggled: root.modCpu = !root.modCpu; onModeToggled: root.toggleIconOnly("G5") }
                WidgetStateTile { gid: "G6";  width: root.evenW((wwCol.width - 4) / 2); label: "Volume";        shown: root.modVolume;          supportsCompact: true; compact: root.iconOnly("G6");  onVisibilityToggled: root.modVolume = !root.modVolume; onModeToggled: root.toggleIconOnly("G6") }
                WidgetStateTile { gid: "G7";  width: root.evenW((wwCol.width - 4) / 2); label: "AI usage";      shown: root.modClaude;          supportsCompact: true; compact: root.iconOnly("G7");  onVisibilityToggled: root.modClaude = !root.modClaude; onModeToggled: root.toggleIconOnly("G7") }
                WidgetStateTile { gid: "G8";  width: root.evenW((wwCol.width - 4) / 2); label: "Clock/Weather"; shown: true; canHide: false }
                WidgetStateTile { gid: "G9";  width: root.evenW((wwCol.width - 4) / 2); label: "Now playing";   shown: root.modMpris; supportsCompact: true; compact: root.mprisBarStyle === "full"; modeOffLabel: "Def"; modeOnLabel: "Full"; onVisibilityToggled: root.modMpris = !root.modMpris; onModeToggled: root.mprisBarStyle = root.mprisBarStyle === "full" ? "default" : "full" }
                WidgetStateTile { gid: "G10"; width: root.evenW((wwCol.width - 4) / 2); label: "Quick tools";   shown: root.modQuick;           onVisibilityToggled: root.modQuick = !root.modQuick }
                WidgetStateTile { gid: "G11"; width: root.evenW((wwCol.width - 4) / 2); label: "Network";       shown: root.modNetwork || root.networkMode === "wifi"; canHide: root.networkMode !== "wifi"; supportsCompact: true; compact: root.iconOnly("G11"); onVisibilityToggled: root.modNetwork = !root.modNetwork; onModeToggled: root.toggleIconOnly("G11") }
                WidgetStateTile { gid: "G12"; width: root.evenW((wwCol.width - 4) / 2); label: "Battery";       shown: root.hasBattery; canHide: false; supportsCompact: true; compact: root.iconOnly("G12"); onModeToggled: root.toggleIconOnly("G12") }
                WidgetStateTile { gid: "G13"; width: root.evenW((wwCol.width - 4) / 2); label: "Brightness";    shown: root.hasBacklight && root.modBrightness; canHide: root.hasBacklight; supportsCompact: true; compact: root.iconOnly("G13"); onVisibilityToggled: root.modBrightness = !root.modBrightness; onModeToggled: root.toggleIconOnly("G13") }
                WidgetStateTile { gid: "G14"; width: root.evenW((wwCol.width - 4) / 2); label: "Power Prof.";   shown: root.modPower;           onVisibilityToggled: root.modPower = !root.modPower }
                WidgetStateTile { gid: "G15"; width: root.evenW((wwCol.width - 4) / 2); label: "Bluetooth";     shown: root.modBluetooth;       supportsCompact: true; compact: root.iconOnly("G15"); onVisibilityToggled: root.modBluetooth = !root.modBluetooth; onModeToggled: root.toggleIconOnly("G15") }
                WidgetStateTile { gid: "G16"; width: root.evenW((wwCol.width - 4) / 2); label: "Temperature";   shown: root.modCpuTemperature;  supportsCompact: true; compact: root.iconOnly("G16"); onVisibilityToggled: root.modCpuTemperature = !root.modCpuTemperature; onModeToggled: root.toggleIconOnly("G16") }
                WidgetStateTile { gid: "G17"; width: root.evenW((wwCol.width - 4) / 2); label: "GPU load";      shown: root.modGpu;             supportsCompact: true; compact: root.iconOnly("G17"); onVisibilityToggled: root.modGpu = !root.modGpu; onModeToggled: root.toggleIconOnly("G17") }
                WidgetStateTile { gid: "G18"; width: root.evenW((wwCol.width - 4) / 2); label: "HDD";           shown: root.modStorage;         supportsCompact: true; compact: root.iconOnly("G18"); onVisibilityToggled: root.modStorage = !root.modStorage; onModeToggled: root.toggleIconOnly("G18") }
            }

            Rectangle {
                id: widgetColorMenu
                width: parent.width
                height: widgetMenuCol.implicitHeight + 16
                radius: root.panelRadius
                visible: ctrlPanel.widgetColorMenuGid !== ""
                color: root.fillIdle
                border.color: root.sep
                border.width: 1

                Column {
                    id: widgetMenuCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 7

                    Item {
                        width: parent.width
                        height: 18
                        UiText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: ctrlPanel.widgetColorMenuLabel.toUpperCase() + " COLOR"
                            color: root.sumiHi
                            font.family: root.mono
                            font.pixelSize: 9
                            font.letterSpacing: 0.7
                        }
                        UiText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.widgetPaletteId(ctrlPanel.widgetColorMenuGid) === "inherit" ? "INHERIT" : "RESET"
                            color: resetColorMa.containsMouse ? root.seal : root.sumiHi
                            font.family: root.mono
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: resetColorMa
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 48
                            height: parent.height
                            enabled: root.widgetPaletteId(ctrlPanel.widgetColorMenuGid) !== "inherit"
                            hoverEnabled: enabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.resetWidgetColor(ctrlPanel.widgetColorMenuGid)
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 8
                        columnSpacing: 4
                        Repeater {
                            model: root.barColorOptions
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool selected:
                                    root.widgetPaletteId(ctrlPanel.widgetColorMenuGid) === modelData
                                width: root.evenW((widgetMenuCol.width - 28) / 8)
                                height: 22
                                radius: root.panelButtonRadius
                                color: root.paletteColor(modelData)
                                border.color: root.sep
                                border.width: 1
                                scale: widgetSwatchMa.containsMouse ? 1.04 : 1.0
                                z: widgetSwatchMa.containsMouse ? 1 : 0
                                Behavior on scale {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }
                                UiText {
                                    anchors.centerIn: parent
                                    text: modelData === "foreground" ? "F" : modelData.slice(-1)
                                    color: root.paletteContrastColor(modelData)
                                    font.family: root.mono
                                    font.pixelSize: 8
                                    font.weight: Font.Medium
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    width: 12
                                    height: 2
                                    radius: 1
                                    visible: parent.selected
                                    color: root.paletteContrastColor(modelData)
                                }
                                MouseArea {
                                    id: widgetSwatchMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (parent.selected)
                                            root.resetWidgetColor(ctrlPanel.widgetColorMenuGid)
                                        else
                                            root.setWidgetPaletteColor(ctrlPanel.widgetColorMenuGid, modelData)
                                    }
                                }
                            }
                        }
                    }

                    Tile {
                        width: parent.width
                        height: 23
                        label: "Border"
                        active: root.widgetHasBorder(ctrlPanel.widgetColorMenuGid)
                        onActivated: root.setWidgetBorderEnabled(
                            ctrlPanel.widgetColorMenuGid,
                            !root.widgetHasBorder(ctrlPanel.widgetColorMenuGid))
                    }

                    Row {
                        width: parent.width
                        spacing: 4
                        visible: root.widgetHasFill(ctrlPanel.widgetColorMenuGid)
                        Repeater {
                            model: [
                                { id: "auto", label: "Auto" },
                                { id: "background", label: "BG" },
                                { id: "foreground", label: "FG" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected:
                                    root.widgetTone(ctrlPanel.widgetColorMenuGid) === modelData.id
                                width: root.evenW((widgetMenuCol.width - 8) / 3)
                                height: 23
                                radius: root.panelButtonRadius
                                color: selected ? root.fillActive : toneColorMa.containsMouse ? root.fillHover : "transparent"
                                border.color: selected || toneColorMa.containsMouse ? root.seal : root.sep
                                border.width: 1
                                UiText {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: selected ? root.seal : root.ink
                                    font.family: root.mono
                                    font.pixelSize: 9
                                }
                                MouseArea {
                                    id: toneColorMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setWidgetTone(ctrlPanel.widgetColorMenuGid, modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── WORKSPACES (collapsible, like the old widgets group) ──
            Tile {
                width: parent.width
                label: ctrlPanel.wsOpen ? "Workspaces  ▾" : "Workspaces  ▸"
                onActivated: ctrlPanel.wsOpen = !ctrlPanel.wsOpen
            }
            Column {
                width: parent.width
                spacing: 8
                visible: ctrlPanel.wsOpen

                // display mode: persist 10 / persist 5 / active
                Row {
                    id: wsModeRow
                    width: parent.width
                    spacing: 4
                    readonly property var opts: [
                        { label: "Persist 10", mode: "10"     },
                        { label: "Persist 5",  mode: "5"      },
                        { label: "Active",     mode: "active" }
                    ]
                    Repeater {
                        model: wsModeRow.opts
                        delegate: Rectangle {
                            id: wsmTile
                            required property var modelData
                            readonly property bool on:      root.workspaceMode === modelData.mode
                            readonly property bool hovered: wsmMa.containsMouse
                            width: root.evenW((wsModeRow.width - wsModeRow.spacing * (wsModeRow.opts.length - 1)) / wsModeRow.opts.length)
                            height: 25; radius: root.panelButtonRadius
                            color: on ? root.fillActive : hovered ? root.fillHover : root.fillIdle
                            border.color: (on || hovered) ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            UiText {
                                anchors.centerIn: parent
                                text: wsmTile.modelData.label
                                color: (wsmTile.on || wsmTile.hovered) ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 10
                                font.weight: wsmTile.on ? Font.Medium : Font.Normal
                            }
                            MouseArea { id: wsmMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.workspaceMode = wsmTile.modelData.mode }
                        }
                    }
                }

                // Six compact workspace treatments; three columns keep every
                // label legible without widening the control fly-out.
                Grid {
                    id: wsStyleRow
                    width: parent.width
                    columns: 3
                    spacing: 4
                    readonly property var opts: [
                        { label: "Default", mode: "default" },
                        { label: "Numbers", mode: "numbers" },
                        { label: "Magic",   mode: "magic"   },
                        { label: "Kanji",   mode: "kanji"   },
                        { label: "Frame",   mode: "rings"   },
                        { label: "Aurora",  mode: "aurora"  }
                    ]
                    Repeater {
                        model: wsStyleRow.opts
                        delegate: Rectangle {
                            id: wssTile
                            required property var modelData
                            readonly property bool on:      root.workspaceStyle === modelData.mode
                            readonly property bool hovered: wssMa.containsMouse
                            width: root.evenW((wsStyleRow.width
                                - wsStyleRow.spacing * (wsStyleRow.columns - 1))
                                / wsStyleRow.columns)
                            height: 25; radius: root.panelButtonRadius
                            color: on ? root.fillActive : hovered ? root.fillHover : root.fillIdle
                            border.color: (on || hovered) ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            UiText {
                                anchors.centerIn: parent
                                text: wssTile.modelData.label
                                color: (wssTile.on || wssTile.hovered) ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 10
                                font.weight: wssTile.on ? Font.Medium : Font.Normal
                            }
                            MouseArea { id: wssMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.workspaceStyle = wssTile.modelData.mode }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── BAR SHELL (full-width / floating / attached / winged notch) ──
            UiText {
                text: "BAR STYLE"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                id: barStyleRow
                width: parent.width
                spacing: 4
                readonly property var opts: [
                    { label: "Full",  mode: "full"  },
                    { label: "Fit",   mode: "fit"   },
                    { label: "Dock",  mode: "dock"  },
                    { label: "Notch", mode: "notch" }
                ]
                Repeater {
                    model: barStyleRow.opts
                    delegate: Tile {
                        required property var modelData
                        width: root.evenW((barStyleRow.width
                            - barStyleRow.spacing * (barStyleRow.opts.length - 1))
                            / barStyleRow.opts.length)
                        label: modelData.label
                        active: root.barShellStyle === modelData.mode
                        onActivated: root.barShellStyle = modelData.mode
                    }
                }
            }
            Tile {
                width: parent.width
                label: "Bar Border"
                active: root.barBorderEnabled
                onActivated: root.barBorderEnabled = !root.barBorderEnabled
            }
            Tile {
                width: parent.width
                label: "Panel & Tooltip Border"
                active: root.panelTooltipBorderEnabled
                onActivated: root.panelTooltipBorderEnabled = !root.panelTooltipBorderEnabled
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── POSITION (bar on top or bottom edge) ──
            UiText {
                text: "POSITION"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                width: parent.width; spacing: 4
                Tile { width: root.evenW((wwCol.width - 4) / 2); label: "Top";    active: root.barPosition === "top";    onActivated: root.barPosition = "top" }
                Tile { width: root.evenW((wwCol.width - 4) / 2); label: "Bottom"; active: root.barPosition === "bottom"; onActivated: root.barPosition = "bottom" }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── LOGO (launcher text/icon variant) ──
            UiText {
                text: "LOGO"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                width: parent.width
                spacing: 4
                Tile {
                    width: root.evenW((wwCol.width - 4) / 2)
                    label: root.launcherLogoLabel(root.launcherLogoText)
                    active: root.launcherLogoMode === "text"
                    onActivated: {
                        if (root.launcherLogoMode === "text") root.nextLauncherLogoText()
                        else root.launcherLogoMode = "text"
                    }
                }
                Tile {
                    width: root.evenW((wwCol.width - 4) / 2)
                    label: root.launcherLogoLabel(root.launcherLogoIcon)
                    active: root.launcherLogoMode === "icon"
                    onActivated: {
                        if (root.launcherLogoMode === "icon") root.nextLauncherLogoIcon()
                        else root.launcherLogoMode = "icon"
                    }
                }
            }
        }
    }
}
