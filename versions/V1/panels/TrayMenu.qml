import QtQuick
import Quickshell
import Quickshell.Wayland

// Themed system-tray context menu, rendered from the DBusMenu model so it
// matches the bar (QsMenuAnchor draws its own unthemeable native popup).
PanelWindow {
    id: trayMenu
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-traymenu"

    readonly property int barBottom: 35
    readonly property int gap: 8

    // drill-down stack of menu handles (root menu + any opened submenus)
    property var menuStack: []
    readonly property var currentHandle: menuStack.length > 0 ? menuStack[menuStack.length - 1] : null

    function strip(t) { return (t || "").replace(/_([^_])/, "$1") }   // drop GTK mnemonic underscore

    Connections {
        target: root
        function onTrayMenuVisibleChanged() {
            trayMenu.menuStack = root.trayMenuVisible && root.trayMenuHandle ? [root.trayMenuHandle] : []
        }
    }

    QsMenuOpener {
        id: opener
        menu: trayMenu.currentHandle
    }

    property real reveal: root.trayMenuVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation { duration: root.trayMenuVisible ? 140 : 100; easing.type: Easing.OutCubic }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.trayMenuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.trayMenuVisible = false }

    Rectangle {
        id: card
        width: 220
        height: col.implicitHeight + 16
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: parent ? Math.max(6, Math.min(root.trayMenuX, parent.width - width - 6)) : 6
        y: barBottom + gap
        opacity: trayMenu.reveal
        focus: root.trayMenuVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.trayMenuVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 8
            spacing: 1

            // back row (only when inside a submenu)
            Rectangle {
                width: parent.width; height: 24; radius: 4
                visible: trayMenu.menuStack.length > 1
                color: backMa.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10) : "transparent"
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹  back"; color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: backMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: trayMenu.menuStack = trayMenu.menuStack.slice(0, -1)
                }
            }
            Rectangle {
                width: parent.width; height: 1; color: root.sep
                visible: trayMenu.menuStack.length > 1
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: entry
                    required property var modelData
                    width: col.width
                    height: modelData.isSeparator ? 7 : 26

                    // separator
                    Rectangle {
                        visible: entry.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 1
                        color: root.sep
                    }

                    // entry row
                    Rectangle {
                        visible: !entry.modelData.isSeparator
                        anchors.fill: parent
                        radius: 4
                        color: (entryMa.containsMouse && entry.modelData.enabled)
                            ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.16) : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // check / radio indicator
                        Text {
                            id: check
                            anchors.left: parent.left; anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            text: entry.modelData.checkState === Qt.Checked ? "✓" : ""
                            color: root.seal
                            font.family: root.mono; font.pixelSize: 11
                        }

                        Image {
                            id: entryIcon
                            anchors.left: check.right; anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            visible: (entry.modelData.icon || "") !== ""
                            source: entry.modelData.icon || ""
                            sourceSize.width: 14; sourceSize.height: 14
                            width: visible ? 14 : 0; height: 14
                            fillMode: Image.PreserveAspectFit; smooth: true
                        }

                        Text {
                            anchors.left: entryIcon.right; anchors.leftMargin: 6
                            anchors.right: arrow.left; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: trayMenu.strip(entry.modelData.text)
                            color: entry.modelData.enabled ? root.ink
                                 : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
                            font.family: root.mono; font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        // submenu arrow
                        Text {
                            id: arrow
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: entry.modelData.hasChildren
                            text: "›"; color: root.sumi
                            font.family: root.mono; font.pixelSize: 13
                        }

                        MouseArea {
                            id: entryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: entry.modelData.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (entry.modelData.hasChildren) {
                                    trayMenu.menuStack = trayMenu.menuStack.concat([entry.modelData])
                                } else {
                                    entry.modelData.triggered()
                                    root.trayMenuVisible = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
