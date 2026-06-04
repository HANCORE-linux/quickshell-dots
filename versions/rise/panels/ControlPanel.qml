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

    readonly property int barBottom: 37
    readonly property int gap: 8

    readonly property var splits: [
        { key: "splitArch",   label: "Status" },
        { key: "splitMon",    label: "Left" },
        { key: "splitMprisL", label: "Right" },
        { key: "splitNet",    label: "Network" }
    ]
    readonly property bool anySplit: root.splitArch || root.splitMon
                                  || root.splitNet || root.splitMprisL

    property real reveal: root.controlVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.controlVisible ? 160 : 120
            easing.type: root.controlVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.controlVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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

            Text {
                text: "SPLITS"
                color: root.sumi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            }

            // ── split toggle grid (2 columns) ──
            Grid {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ctrlPanel.splits
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: root[modelData.key] === true
                        width: (col.width - 8) / 2
                        height: 30
                        radius: 4
                        color: active ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                                      : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                        border.color: active ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 11
                            font.weight: active ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root[modelData.key] = !root[modelData.key]
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── merge all ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: ctrlPanel.anySplit ? root.seal : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: ctrlPanel.anySplit ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "Merge all"
                    color: ctrlPanel.anySplit ? root.paper : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: ctrlPanel.anySplit
                    onClicked: root.mergeAllSplits()
                }
            }
        }
    }
}
