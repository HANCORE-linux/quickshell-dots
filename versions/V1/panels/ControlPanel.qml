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

    readonly property int barBottom: 35
    readonly property int gap: 8

    // power sub-menu starts CLOSED — no destructive tile is ever pre-shown
    property bool powerOpen: false
    property bool wsOpen: false   // Workspaces collapsible inside the WW fly-out
    property bool compactOpen: false
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
    onRevealChanged: if (reveal < 0.01) { powerOpen = false; wsOpen = false; compactOpen = false; root.splitsSubVisible = false; root.wwSubVisible = false }  // reset when closed
    WlrLayershell.keyboardFocus: root.controlVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── reusable tile: neutral by default, highlights only on hover ──
    component Tile: Rectangle {
        property string label
        property color accent: root.seal
        property bool active: false
        signal activated()
        height: 25
        radius: root.tileRadius
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

    component CompactToggle: Item {
        property string label
        property bool active: false
        signal toggled()

        height: 20
        UiText {
            id: toggleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent.active || toggleMa.containsMouse ? root.seal : root.ink
            font.family: root.mono
            font.pixelSize: 11
            font.weight: parent.active ? Font.Medium : Font.Normal
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 16
            radius: 8
            color: parent.active ? root.fillActive : toggleMa.containsMouse ? root.fillHover : root.fillIdle
            border.color: (parent.active || toggleMa.containsMouse) ? root.seal : root.sep
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 10
                height: 10
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                x: parent.parent.active ? parent.width - width - 3 : 3
                color: parent.parent.active ? root.seal : root.sumi
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
        MouseArea {
            id: toggleMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.toggled()
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.controlVisible = false }

    Rectangle {
        id: card
        width: 240
        height: col.implicitHeight + 24
        radius: ctrlPanel.reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.launcherBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
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
                    active: root.variantHost ? root.variantHost.runningVariant === "v1" : true
                    enabled: root.variantHost ? !root.variantHost.switching && root.variantHost.runningVariant !== "v1" : false
                    opacity: active ? 1.0 : (enabled ? 1.0 : 0.4)
                    onActivated: ctrlPanel.switchBar("v1")
                }
                Tile {
                    width: root.evenW((col.width - 12) / 3)
                    label: "V2"
                    active: root.variantHost ? root.variantHost.runningVariant === "v2" : false
                    enabled: root.variantHost ? !root.variantHost.switching && root.variantHost.runningVariant !== "v2" : true
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
                        radius: root.tileRadius
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

            // ── SPLITS (opens the fly-out sub-panel) ──
            UiText {
                text: "SPLITS"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Tile {
                width: parent.width
                label: root.splitsSubVisible ? "Splits  ◂" : "Splits  ▸"
                active: root.splitsSubVisible
                accent: root.seal
                onActivated: root.splitsSubVisible = !root.splitsSubVisible
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
                        height: 25; radius: root.tileRadius
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

    // ── SPLITS sub-panel (fly-out right of the ControlPanel) ──
    Rectangle {
        id: splitCard
        visible: root.controlVisible && root.splitsSubVisible
        width: 248
        height: splitCol.implicitHeight + 24
        radius: (root.controlVisible && root.splitsSubVisible) ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }
        // open to the right of the card, or to the left if there's no room
        x: (card.x + card.width + ctrlPanel.gap + width <= parent.width - 6)
           ? card.x + card.width + ctrlPanel.gap
           : card.x - ctrlPanel.gap - width
        // bottom mode → bottom-align so a tall flyout grows UP, not into the bar
        y: root.barPosition === "bottom" ? (card.y + card.height - height) : card.y
        opacity: ctrlPanel.reveal

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: splitCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            UiText {
                text: "SPLITS"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Tile { width: parent.width; label: "Split all";      accent: root.seal;   onActivated: { if (root.fnSplitAll) root.fnSplitAll() } }
            Tile { width: parent.width; label: "Merge all";                            onActivated: { if (root.fnMergeAll) root.fnMergeAll() } }
            Tile { width: parent.width; label: "Default layout"; accent: root.seal;   onActivated: { if (root.fnDefaultLayout) root.fnDefaultLayout() } }

            Rectangle { width: parent.width; height: 1; color: root.sep }
            UiText {
                text: "GAP ANIM"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                id: animRow
                width: parent.width
                spacing: 4
                // every tile cycles base → "<label> 2" (alt mode) → off
                readonly property var opts: [
                    { label: "Stream", mode: 1, alt: 5 },
                    { label: "Surge",  mode: 2, alt: 6 },
                    { label: "Bolt",   mode: 3, alt: 4 }
                ]
                Repeater {
                    model: animRow.opts
                    delegate: Rectangle {
                        id: animTile
                        required property var modelData
                        readonly property bool on:      root.barAnim === modelData.mode || root.barAnim === modelData.alt
                        readonly property bool hovered: animMa.containsMouse
                        width: root.evenW((animRow.width - animRow.spacing * (animRow.opts.length - 1)) / animRow.opts.length)
                        height: 25; radius: root.tileRadius
                        color: on ? root.fillActive : hovered ? root.fillHover : root.fillIdle
                        border.color: (on || hovered) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: root.barAnim === animTile.modelData.alt ? animTile.modelData.label + " 2"
                                                                          : animTile.modelData.label
                            color: (animTile.on || animTile.hovered) ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 11
                            font.weight: animTile.on ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            id: animMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var n = root.barAnim                           // base → alt → off
                                root.barAnim = (n === animTile.modelData.mode ? animTile.modelData.alt
                                              : n === animTile.modelData.alt  ? 0
                                              : animTile.modelData.mode)
                            }
                        }
                    }
                }
            }
            Tile {
                width: parent.width
                // Separate event-reactor mode; not part of the Surge 1→2 cycle.
                label: "Reactor"
                active: root.barAnim === 7
                onActivated: root.barAnim = root.barAnim === 7 ? 0 : 7
            }
            Tile {
                width: parent.width
                label: "Quotes"
                active: root.barAnim === 8
                onActivated: root.barAnim = root.barAnim === 8 ? 0 : 8
            }
        }
    }

    // ── WIDGETS & WORKSPACES sub-panel (fly-out; stacks below SPLITS if both open) ──
    Rectangle {
        id: wwCard
        visible: root.controlVisible && root.wwSubVisible
        width: 248
        height: wwCol.implicitHeight + 24
        radius: (root.controlVisible && root.wwSubVisible) ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }
        // same side as splitCard; if SPLITS is also open, stack below it
        x: (card.x + card.width + ctrlPanel.gap + width <= parent.width - 6)
           ? card.x + card.width + ctrlPanel.gap
           : card.x - ctrlPanel.gap - width
        y: (root.controlVisible && root.splitsSubVisible)
           ? (root.barPosition === "bottom" ? splitCard.y - ctrlPanel.gap - height
                                            : splitCard.y + splitCard.height + ctrlPanel.gap)
           : (root.barPosition === "bottom" ? card.y + card.height - height : card.y)
        opacity: ctrlPanel.reveal

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: wwCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── WIDGETS toggle grid (moved here from the main card) ──
            UiText {
                text: "WIDGETS"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Memory";      active: root.modMemory;    onActivated: root.modMemory = !root.modMemory }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Brightness";  visible: root.hasBacklight; active: root.modBrightness; onActivated: root.modBrightness = !root.modBrightness }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "AI usage";    active: root.modClaude;    onActivated: root.modClaude = !root.modClaude }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Power Prof."; active: root.modPower;     onActivated: root.modPower = !root.modPower }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Bluetooth";   active: root.modBluetooth; onActivated: root.modBluetooth = !root.modBluetooth }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Network";     active: root.modNetwork; enabled: root.networkMode !== "wifi"; onActivated: root.modNetwork = !root.modNetwork }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Quick tools"; active: root.modQuick;   onActivated: root.modQuick = !root.modQuick }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Status";      active: root.modStatus;  onActivated: root.modStatus = !root.modStatus }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "CPU";         active: root.modCpu;     onActivated: root.modCpu = !root.modCpu }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Volume";      active: root.modVolume;  onActivated: root.modVolume = !root.modVolume }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Now playing"; active: root.modMpris;   onActivated: root.modMpris = !root.modMpris }
                Tile { width: root.evenW((wwCol.width - 8) / 2); label: "Battery";     visible: root.hasBattery; active: true; enabled: false }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Tile {
                width: parent.width
                label: ctrlPanel.compactOpen ? "Compact Display  ▾" : "Compact Display  ▸"
                active: ctrlPanel.compactOpen
                onActivated: ctrlPanel.compactOpen = !ctrlPanel.compactOpen
            }
            Grid {
                visible: ctrlPanel.compactOpen
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 6
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Network";    active: root.compactNetwork;    onToggled: root.compactNetwork = !root.compactNetwork }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Battery";    visible: root.hasBattery; active: root.compactBattery;    onToggled: root.compactBattery = !root.compactBattery }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Brightness"; visible: root.hasBacklight; active: root.compactBrightness; onToggled: root.compactBrightness = !root.compactBrightness }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Bluetooth";  active: root.compactBluetooth;  onToggled: root.compactBluetooth = !root.compactBluetooth }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Power";      active: root.compactPower;      onToggled: root.compactPower = !root.compactPower }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "CPU";        active: root.compactCpu;        onToggled: root.compactCpu = !root.compactCpu }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Memory";     active: root.compactMemory;     onToggled: root.compactMemory = !root.compactMemory }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Volume";     active: root.compactVolume;     onToggled: root.compactVolume = !root.compactVolume }
                CompactToggle { width: root.evenW((wwCol.width - 8) / 2); label: "Now playing"; active: root.compactMpris;      onToggled: root.compactMpris = !root.compactMpris }
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
                            height: 25; radius: root.tileRadius
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

                // display style: default / numbers / magic
                Row {
                    id: wsStyleRow
                    width: parent.width
                    spacing: 4
                    readonly property var opts: [
                        { label: "Default", mode: "default" },
                        { label: "Numbers", mode: "numbers" },
                        { label: "Magic",   mode: "magic"   }
                    ]
                    Repeater {
                        model: wsStyleRow.opts
                        delegate: Rectangle {
                            id: wssTile
                            required property var modelData
                            readonly property bool on:      root.workspaceStyle === modelData.mode
                            readonly property bool hovered: wssMa.containsMouse
                            width: root.evenW((wsStyleRow.width - wsStyleRow.spacing * (wsStyleRow.opts.length - 1)) / wsStyleRow.opts.length)
                            height: 25; radius: root.tileRadius
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

            // ── STYLE (bar pill style; paint-only, width-invariant) ──
            UiText {
                text: "STYLE"
                color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Row {
                width: parent.width; spacing: 4
                // independent toggles: each highlights when ON, click flips it (Border+Frost+Shadow combinable)
                Tile { width: root.evenW((wwCol.width - 8) / 3); label: "Border"; active: root.styleBorder; onActivated: root.styleBorder = !root.styleBorder }
                Tile { width: root.evenW((wwCol.width - 8) / 3); label: "Frost";  active: root.styleFrost;  onActivated: root.styleFrost = !root.styleFrost }
                Tile { width: root.evenW((wwCol.width - 8) / 3); label: "Shadow"; active: root.styleShadow; onActivated: root.styleShadow = !root.styleShadow }
            }
            Row {
                width: parent.width; spacing: 4
                Tile { width: root.evenW((wwCol.width - 4) / 2); label: "Radius 12"; active: !root.styleRadiusSmall; onActivated: root.styleRadiusSmall = false }
                Tile { width: root.evenW((wwCol.width - 4) / 2); label: "Radius 6";  active: root.styleRadiusSmall;  onActivated: root.styleRadiusSmall = true }
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
