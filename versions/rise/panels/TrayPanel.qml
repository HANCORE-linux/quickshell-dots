import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: trayPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tray"
    mask: Region { item: card }

    readonly property int barBottom: 37
    readonly property int gap: 8
    readonly property int popupW: 56

    visible: root.trayVisible
    WlrLayershell.keyboardFocus: root.trayVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // auto-close when there are no hidden (unpinned) items left to show
    readonly property int hiddenCount: {
        var n = 0, vals = SystemTray.items.values
        for (var i = 0; i < vals.length; i++)
            if (root.trayPinned.indexOf(vals[i].id) < 0) n++
        return n
    }
    onHiddenCountChanged: if (root.trayVisible && hiddenCount === 0) root.trayVisible = false

    QsMenuAnchor {
        id: ctxMenu
        anchor.window: trayPanel
    }

    Rectangle {
        id: card
        width: popupW
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: Math.max(6, root.trayBarX)
        y: barBottom + gap
        focus: root.trayVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.trayVisible = false
                event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            Item {
                width: parent.width
                implicitHeight: 18
                height: 18
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    anchors.centerIn: parent
                    text: "Esc"
                    color: root.sumi
                    font.family: root.mono
                    font.pixelSize: 9
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.trayVisible = false
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    required property SystemTrayItem modelData
                    required property int index

                    width: parent.width
                    height: 28
                    visible: root.trayPinned.indexOf(modelData.id) < 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: ma.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"
                    }

                    Row {
                        anchors.centerIn: parent

                        Image {
                            source: modelData.icon
                            sourceSize.width: 16
                            sourceSize.height: 16
                            width: 16
                            height: 16
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (e) => {
                            if (e.button === Qt.LeftButton) {
                                modelData.activate()
                            } else if (e.button === Qt.RightButton) {
                                root.trayToggleHide(modelData)
                            } else if (e.button === Qt.MiddleButton) {
                                if (modelData.hasMenu) {
                                    ctxMenu.anchor.item = ma
                                    ctxMenu.anchor.rect = Qt.rect(0, ma.height, ma.width, 1)
                                    ctxMenu.anchor.edges = Edges.Top
                                    ctxMenu.anchor.gravity = Edges.Top
                                    ctxMenu.menu = modelData.menu
                                    ctxMenu.open()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
