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

    property bool wsOpen: false        // Workspaces collapsible (Widgets tab)
    property bool compactOpen: false   // Compact Display collapsible (Widgets tab)
    // pestaña activa del rediseño: System · Barra · Widgets · Pickers
    property string tab: "system"

    property real reveal: root.controlVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.controlVisible ? 200 : 140
            easing.type: root.controlVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    // receta popover macOS: el MOVIMIENTO va en reloj aparte y más largo que el
    // fade (320 vs 200ms) — la card entra deslizando desde la barra con una
    // escala sutil desde el ancla; el fade termina antes y el asentamiento del
    // movimiento es lo que se percibe como "suave"
    property real slide: root.controlVisible ? 1 : 0
    Behavior on slide {
        NumberAnimation {
            duration: root.controlVisible ? 320 : 140
            easing.type: root.controlVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    onRevealChanged: if (reveal < 0.01) {   // reset when closed
        wsOpen = false; compactOpen = false; tab = "system"
        root.splitsSubVisible = false; root.wwSubVisible = false
        omView.resetToRoot()
    }
    WlrLayershell.keyboardFocus: root.controlVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // enfoca el buscador Omarchy cuando la pestaña System está activa
    Timer {
        id: sysFocusTimer
        interval: 80
        onTriggered: if (ctrlPanel.reveal > 0.5 && ctrlPanel.tab === "system") omView.searchInput.forceActiveFocus()
    }
    onTabChanged: {
        if (tab === "system") sysFocusTimer.restart()
        else card.forceActiveFocus()
    }
    Connections {
        target: root
        function onControlVisibleChanged() {
            if (root.controlVisible) {
                // Super+Escape pide abrir en un submenú Omarchy (p.ej. "system")
                if (root.controlOpenSubmenu !== "") {
                    ctrlPanel.tab = "system"
                    omView.navStack = [root.controlOpenSubmenu]
                    root.controlOpenSubmenu = ""
                }
                if (ctrlPanel.tab === "system") sysFocusTimer.restart()
            }
        }
    }

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
        UiText {
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
            anchors.right: parent.right
            anchors.rightMargin: 36
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            elide: Text.ElideRight
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

    // ── segmented-tab button (System · Barra · Widgets · Pickers) ──
    component TabButton: Rectangle {
        property string tabId
        property string label
        readonly property bool on: ctrlPanel.tab === tabId
        height: parent.height
        radius: root.tileRadius - 3
        color: on ? root.fillActive : _tma.containsMouse ? root.fillHover : "transparent"
        border.color: on ? root.seal : "transparent"
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        UiText {
            anchors.centerIn: parent
            text: parent.label
            color: parent.on ? root.seal : _tma.containsMouse ? root.ink : root.sumi
            font.family: root.mono; font.pixelSize: 10
            font.weight: parent.on ? Font.Medium : Font.Normal
        }
        MouseArea {
            id: _tma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ctrlPanel.tab = parent.tabId
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
        // entra desde la barra (10px) + escala desde el ancla, estilo NSPopover
        transform: Translate { y: (1 - ctrlPanel.slide) * (ctrlPanel.root.barPosition === "bottom" ? 10 : -10) }
        scale: 0.97 + 0.03 * ctrlPanel.slide
        transformOrigin: ctrlPanel.root.barPosition === "bottom" ? Item.Bottom : Item.Top
        // el buscador Omarchy toma el foco en la pestaña System; en el resto lo toma la card (ESC)
        focus: root.controlVisible && ctrlPanel.tab !== "system"

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
            }

            // ── tabs ──
            Rectangle {
                width: parent.width
                height: 26
                radius: root.tileRadius
                color: root.fillIdle
                border.color: root.sep
                border.width: 1
                Row {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 3
                    TabButton { width: root.evenW((parent.width - 3 * 3) / 4); tabId: "system";  label: "Omarchy" }
                    TabButton { width: root.evenW((parent.width - 3 * 3) / 4); tabId: "barra";   label: "Bar"   }
                    TabButton { width: root.evenW((parent.width - 3 * 3) / 4); tabId: "widgets"; label: "Widgets" }
                    TabButton { width: root.evenW((parent.width - 3 * 3) / 4); tabId: "pickers"; label: "Pickers" }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ══════════════════ TAB: SYSTEM ══════════════════
            Column {
                width: col.width
                spacing: 8
                visible: ctrlPanel.tab === "system"

                // ── menú Omarchy (idéntico al standalone, empotrado; mismos endpoints) ──
                OmarchyMenuView {
                    id: omView
                    theme: root
                    width: parent.width
                    maxListHeight: 420
                    onCloseRequested: root.controlVisible = false
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── ACTIONS ──
                UiText {
                    text: "ACTIONS"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Tile {
                    width: parent.width
                    label: "Reload QS"
                    onActivated: { root.controlVisible = false; Quickshell.reload(false) }
                }
            }

            // ══════════════════ TAB: BARRA ══════════════════
            Column {
                width: col.width
                spacing: 8
                visible: ctrlPanel.tab === "barra"

                // ── BAR-COLOR: seal color source ──
                UiText {
                    text: "BAR COLOR"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Grid {
                    width: parent.width; columns: 2; columnSpacing: 8; rowSpacing: 8
                    Repeater {
                        model: root.barColorOptions
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool on:      root.barColor === modelData
                            readonly property bool hovered: _cma.containsMouse
                            width: root.evenW((col.width - 8) / 2); height: 25; radius: root.tileRadius
                            color: on ? root.fillActive : hovered ? root.fillHover : root.fillIdle
                            border.color: (on || hovered) ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            UiText {
                                anchors.centerIn: parent
                                text: root.barColorLabel(modelData)
                                color: (parent.on || parent.hovered) ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 11
                                font.weight: parent.on ? Font.Medium : Font.Normal
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

                // ── STYLE (bar pill style; paint-only, width-invariant) ──
                UiText {
                    text: "STYLE"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Row {
                    width: parent.width; spacing: 4
                    // independent toggles: each highlights when ON, click flips it (Border+Frost+Shadow combinable)
                    Tile { width: root.evenW((col.width - 8) / 3); label: "Border";   active: root.styleBorder; onActivated: root.styleBorder = !root.styleBorder }
                    Tile { width: root.evenW((col.width - 8) / 3); label: "Frost"; active: root.styleFrost;  onActivated: root.styleFrost = !root.styleFrost }
                    Tile { width: root.evenW((col.width - 8) / 3); label: "Shadow";  active: root.styleShadow; onActivated: root.styleShadow = !root.styleShadow }
                }
                Row {
                    width: parent.width; spacing: 4
                    Tile { width: root.evenW((col.width - 4) / 2); label: "Radius 12"; active: !root.styleRadiusSmall; onActivated: root.styleRadiusSmall = false }
                    Tile { width: root.evenW((col.width - 4) / 2); label: "Radius 6";  active: root.styleRadiusSmall;  onActivated: root.styleRadiusSmall = true }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── POSITION (bar on top or bottom edge) ──
                UiText {
                    text: "POSITION"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Row {
                    width: parent.width; spacing: 4
                    Tile { width: root.evenW((col.width - 4) / 2); label: "Top"; active: root.barPosition === "top";    onActivated: root.barPosition = "top" }
                    Tile { width: root.evenW((col.width - 4) / 2); label: "Bottom"; active: root.barPosition === "bottom"; onActivated: root.barPosition = "bottom" }
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
                        width: root.evenW((col.width - 4) / 2)
                        label: root.launcherLogoLabel(root.launcherLogoText)
                        active: root.launcherLogoMode === "text"
                        onActivated: {
                            if (root.launcherLogoMode === "text") root.nextLauncherLogoText()
                            else root.launcherLogoMode = "text"
                        }
                    }
                    Tile {
                        width: root.evenW((col.width - 4) / 2)
                        label: root.launcherLogoLabel(root.launcherLogoIcon)
                        active: root.launcherLogoMode === "icon"
                        onActivated: {
                            if (root.launcherLogoMode === "icon") root.nextLauncherLogoIcon()
                            else root.launcherLogoMode = "icon"
                        }
                    }
                }
            }

            // ══════════════════ TAB: WIDGETS ══════════════════
            Column {
                width: col.width
                spacing: 8
                visible: ctrlPanel.tab === "widgets"

                // ── WIDGETS toggle grid ──
                UiText {
                    text: "WIDGETS"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    Tile { width: root.evenW((col.width - 8) / 2); label: "RAM";         active: root.modMemory;    onActivated: root.modMemory = !root.modMemory }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Brightness";      visible: root.hasBacklight; active: root.modBrightness; onActivated: root.modBrightness = !root.modBrightness }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "AI usage"; active: root.modClaude;    onActivated: root.modClaude = !root.modClaude }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Power profile"; active: root.modPower;     onActivated: root.modPower = !root.modPower }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Bluetooth";   active: root.modBluetooth; onActivated: root.modBluetooth = !root.modBluetooth }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Network";         active: root.modNetwork; enabled: root.networkMode !== "wifi"; onActivated: root.modNetwork = !root.modNetwork }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Controls";   active: root.modQuick;   onActivated: root.modQuick = !root.modQuick }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Indicators"; active: root.modStatus;  onActivated: root.modStatus = !root.modStatus }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "CPU";         active: root.modCpu;     onActivated: root.modCpu = !root.modCpu }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Volume";     active: root.modVolume;  onActivated: root.modVolume = !root.modVolume }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Multimedia"; active: root.modMpris;   onActivated: root.modMpris = !root.modMpris }
                    Tile { width: root.evenW((col.width - 8) / 2); label: "Battery";     visible: root.hasBattery; active: true; enabled: false }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                Tile {
                    width: parent.width
                    label: ctrlPanel.compactOpen ? "Vista compacta  ▾" : "Vista compacta  ▸"
                    active: ctrlPanel.compactOpen
                    onActivated: ctrlPanel.compactOpen = !ctrlPanel.compactOpen
                }
                Grid {
                    visible: ctrlPanel.compactOpen
                    width: parent.width
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 6
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "Network";        active: root.compactNetwork;    onToggled: root.compactNetwork = !root.compactNetwork }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "Battery";    visible: root.hasBattery; active: root.compactBattery;    onToggled: root.compactBattery = !root.compactBattery }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "Brightness";     visible: root.hasBacklight; active: root.compactBrightness; onToggled: root.compactBrightness = !root.compactBrightness }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "Bluetooth";  active: root.compactBluetooth;  onToggled: root.compactBluetooth = !root.compactBluetooth }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "Power";      active: root.compactPower;      onToggled: root.compactPower = !root.compactPower }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "CPU";        active: root.compactCpu;        onToggled: root.compactCpu = !root.compactCpu }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "RAM";        active: root.compactMemory;     onToggled: root.compactMemory = !root.compactMemory }
                    CompactToggle { width: root.evenW((col.width - 8) / 2); label: "Volume";    active: root.compactVolume;     onToggled: root.compactVolume = !root.compactVolume }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── WORKSPACES (collapsible) ──
                Tile {
                    width: parent.width
                    label: ctrlPanel.wsOpen ? "Espacios de trabajo  ▾" : "Espacios de trabajo  ▸"
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
                            { label: "Fixed 10", mode: "10"     },
                            { label: "Fixed 5",  mode: "5"      },
                            { label: "Active",  mode: "active" }
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
                            { label: "Normal",  mode: "default" },
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
            }

            // ══════════════════ TAB: PICKERS ══════════════════
            Column {
                width: col.width
                spacing: 8
                visible: ctrlPanel.tab === "pickers"

                // ── PICKER style (theme/wallpaper/screenshot/video picker visual) ──
                UiText {
                    text: "PICKERS"
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
                    // the same side padding.
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

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── SPLITS ──
                UiText {
                    text: "SPLITS"
                    color: root.sumiHi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Tile { width: parent.width; label: "Split all"; accent: root.seal;   onActivated: { if (root.fnSplitAll) root.fnSplitAll() } }
                Tile { width: parent.width; label: "Merge all";     onActivated: { if (root.fnMergeAll) root.fnMergeAll() } }
                Tile { width: parent.width; label: "Default layout"; accent: root.seal;   onActivated: { if (root.fnDefaultLayout) root.fnDefaultLayout() } }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── GAP ANIM ──
                UiText {
                    text: "GAP ANIMATION"
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
    }
}
