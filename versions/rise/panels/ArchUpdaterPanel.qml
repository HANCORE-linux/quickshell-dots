import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: archPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-arch-updater"

    readonly property int barBottom: 37
    readonly property int gap: 8

    Process {
        id: panelUpdateRunner
        command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation 'paru'"]
    }

    property real reveal: root.archVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.archVisible ? 160 : 120
            easing.type: root.archVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.archVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.archVisible = false
    }

    Rectangle {
        id: card
        width: 520
        height: Math.min(col.implicitHeight + 24, 460)
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: 6
        y: barBottom + gap
        opacity: archPanel.reveal
        focus: root.archVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.archVisible = false;
                event.accepted = true;
            }
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
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Updates"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: root.sumi
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.archVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── column headers ──
            Row {
                width: parent.width
                spacing: 4
                Text {
                    width: parent.width * 0.4
                    text: "Package"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Text {
                    width: parent.width * 0.3
                    text: "Installed"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Text {
                    width: parent.width * 0.3
                    text: "Available"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
            }

            // ── update list ──
            Flickable {
                width: parent.width
                height: Math.min(updatesCol.implicitHeight, 280)
                contentHeight: updatesCol.implicitHeight
                clip: true
                interactive: updatesCol.implicitHeight > 280

                Column {
                    id: updatesCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.archUpdates

                        delegate: Item {
                            required property var modelData
                            required property int index

                            readonly property color srcColor: {
                                if (modelData.source === "system") return root.seal;
                                if (modelData.source === "aur") return root.indigo;
                                return root.sumi;
                            }

                            width: parent.width
                            height: 22

                            Row {
                                width: parent.width
                                spacing: 4
                                Text {
                                    width: parent.width * 0.4
                                    text: modelData.name
                                    color: srcColor
                                    font.family: root.mono; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width * 0.3
                                    text: modelData.oldVer
                                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                                    font.family: root.mono; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width * 0.3
                                    text: modelData.newVer
                                    color: srcColor
                                    font.family: root.mono; font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 1
                                color: root.sep
                                visible: index < root.archUpdates.length - 1
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.archUpdates.length === 0
                        text: "No updates available"
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                        font.family: root.mono; font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 20
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── buttons ──
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 28; radius: 4
                    color: root.sep
                    border.color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "Refresh"
                        color: root.ink
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.archRefreshTick++;
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 28; radius: 4
                    color: root.seal
                    border.color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "Update"
                        color: root.paper
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.archVisible = false;
                            panelUpdateRunner.running = false;
                            panelUpdateRunner.running = true;
                        }
                    }
                }
            }
        }
    }
}
