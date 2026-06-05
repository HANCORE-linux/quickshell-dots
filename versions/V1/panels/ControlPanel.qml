import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: ctrlPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-control"
    // no mask → whole overlay is interactive (modal): click-outside + ESC work

    readonly property int barBottom: 35
    readonly property int gap: 8

    readonly property var splits: [
        { key: "splitArch",   label: "Status" },
        { key: "splitMon",    label: "Left" },
        { key: "splitMprisL", label: "Right" },
        { key: "splitNet",    label: "Network" }
    ]
    readonly property bool anySplit: root.splitArch || root.splitMon
                                  || root.splitNet || root.splitMprisL

    // power sub-menu starts CLOSED — no destructive tile is ever pre-shown
    property bool powerOpen: false

    property real reveal: root.controlVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.controlVisible ? 160 : 120
            easing.type: root.controlVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    onRevealChanged: if (reveal < 0.01) powerOpen = false   // reset when closed
    WlrLayershell.keyboardFocus: root.controlVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── reusable tile: neutral by default, highlights only on hover ──
    component Tile: Rectangle {
        property string label
        property color accent: root.seal
        signal activated()
        height: 30
        radius: 4
        color: _ma.containsMouse ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
                                 : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
        border.color: _ma.containsMouse ? accent : root.sep
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: parent.label
            color: _ma.containsMouse ? parent.accent : root.ink
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

    MouseArea { anchors.fill: parent; onClicked: root.controlVisible = false }

    Rectangle {
        id: card
        width: 240
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: 6
        y: barBottom + gap
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
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Control"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: root.sumi; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.controlVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── ACTIONS ──
            Text {
                text: "ACTIONS"
                color: root.sumi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Tile {
                width: parent.width
                label: "Reload QS-Config"
                onActivated: { root.controlVisible = false; Quickshell.reload(false) }
            }
            Tile {
                width: parent.width
                label: "Open Omarchy Menu"
                onActivated: { root.controlVisible = false; Quickshell.execDetached(["omarchy-menu"]) }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

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
                    width: (col.width - 8) / 2
                    label: "Lock"
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["hyprlock"]) }
                }
                Tile {
                    width: (col.width - 8) / 2
                    label: "Suspend"
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["systemctl", "suspend"]) }
                }
                Tile {
                    width: (col.width - 8) / 2
                    label: "Reboot"
                    accent: root.indigo
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["systemctl", "reboot"]) }
                }
                Tile {
                    width: (col.width - 8) / 2
                    label: "Shutdown"
                    accent: root.seal
                    onActivated: { root.controlVisible = false; Quickshell.execDetached(["systemctl", "poweroff"]) }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── SPLITS ──
            Text {
                text: "SPLITS"
                color: root.sumi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ctrlPanel.splits
                    delegate: Rectangle {
                        id: splitTile
                        required property var modelData
                        readonly property bool active: root[modelData.key] === true
                        readonly property bool hovered: splitMa.containsMouse
                        width: (col.width - 8) / 2
                        height: 30
                        radius: 4
                        color: active ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                                      : hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
                                                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                        border.color: (active || hovered) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: splitTile.modelData.label
                            color: (splitTile.active || splitTile.hovered) ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 11
                            font.weight: splitTile.active ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            id: splitMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root[splitTile.modelData.key] = !root[splitTile.modelData.key]
                        }
                    }
                }
            }

            // ── merge all ──
            Rectangle {
                id: mergeBtn
                readonly property bool hovered: mergeMa.containsMouse && ctrlPanel.anySplit
                width: parent.width
                height: 28; radius: 4
                color: ctrlPanel.anySplit ? root.seal : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: ctrlPanel.anySplit ? root.seal : root.sep
                border.width: 1
                opacity: hovered ? 0.88 : 1.0
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "Merge all"
                    color: ctrlPanel.anySplit ? root.paper : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: mergeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: ctrlPanel.anySplit ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: ctrlPanel.anySplit
                    onClicked: root.mergeAllSplits()
                }
            }
        }
    }
}
