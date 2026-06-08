import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: panel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-wallpaper-picker"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property real reveal: root.wallpaperPickerVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.wallpaperPickerVisible ? 160 : 120
            easing.type: root.wallpaperPickerVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001

    property var    wallpapers:   []
    property string currentBg:    ""
    property real   scrollOffset: 0

    readonly property string bgDir: Quickshell.env("HOME") + "/.config/omarchy/current/theme/backgrounds"

    Process {
        id: listProc
        command: ["bash", "-c",
            "find '" + panel.bgDir + "' -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.webp' -o -name '*.jpeg' \\) | sort"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                panel.wallpapers = this.text.trim().split("\n").filter(function(l){ return l.trim() !== "" })
            }
        }
    }
    Process {
        id: currentBgProc
        command: ["bash", "-c", "readlink -f '" + Quickshell.env("HOME") + "/.config/omarchy/current/background' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: { panel.currentBg = this.text.trim() }
        }
    }
    Process { id: applyProc; command: [] }

    onRevealChanged: {
        if (reveal > 0.5) {
            currentBgProc.running = false; currentBgProc.running = true
            listProc.running = false; listProc.running = true
        }
    }

    function applyWallpaper(path) {
        applyProc.command = ["bash", "-c", "omarchy-theme-bg-set '" + path.replace(/'/g, "'\\''") + "'"]
        applyProc.running = false; applyProc.running = true
        panel.currentBg = path
        root.wallpaperPickerVisible = false
    }

    // backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: root.wallpaperPickerVisible = false
    }

    // card
    Rectangle {
        width: 280
        height: Math.min(cardContent.implicitHeight + 20, 500)
        x: Math.max(4, root.quickActionsBarX - 140)
        y: 43
        opacity: panel.reveal
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1
        clip: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: cardContent
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6

            // header
            Item {
                width: parent.width; height: 26
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Wallpaper"
                    color: root.ink; font.family: root.mono
                    font.pixelSize: 12; font.letterSpacing: 1; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: closeMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea {
                        id: closeMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.wallpaperPickerVisible = false
                    }
                }
            }

            // thumbnail grid
            Item {
                id: gridArea
                width: parent.width
                height: Math.min(Math.ceil(panel.wallpapers.length / 2) * 94, 440)
                clip: true

                property real scrollOffset: panel.scrollOffset

                MouseArea {
                    anchors.fill: parent; z: 2; acceptedButtons: Qt.NoButton
                    onWheel: function(w) {
                        var rows = Math.ceil(panel.wallpapers.length / 2)
                        var max = Math.max(0, rows * 94 - gridArea.height)
                        panel.scrollOffset = Math.max(0, Math.min(panel.scrollOffset - w.angleDelta.y / 2, max))
                    }
                }

                Grid {
                    width: gridArea.width
                    y: -gridArea.scrollOffset
                    columns: 2
                    spacing: 6

                    Repeater {
                        model: panel.wallpapers
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: (gridArea.width - 6) / 2
                            height: 88

                            readonly property bool isCurrent: modelData === panel.currentBg
                            readonly property string fname: modelData.split("/").pop()

                            Rectangle {
                                anchors.fill: parent; radius: 5
                                border.color: isCurrent ? root.seal : (imgMa.containsMouse ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.5) : root.sep)
                                border.width: isCurrent ? 2 : 1
                                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                Image {
                                    anchors { fill: parent; margins: 3 }
                                    source: "file://" + modelData
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true; mipmap: true; asynchronous: true
                                    clip: true
                                    layer.enabled: true
                                    layer.effect: Item {
                                        // rounded clip via layer
                                    }
                                }

                                // name overlay at bottom
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 3 }
                                    height: 18; radius: 3
                                    color: Qt.rgba(0, 0, 0, 0.55)
                                    Text {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 5; rightMargin: 5 }
                                        text: fname.replace(/\.[^/.]+$/, "")
                                        color: "white"; font.family: root.mono; font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }

                                // current checkmark
                                Rectangle {
                                    visible: isCurrent
                                    anchors { top: parent.top; right: parent.right; topMargin: 5; rightMargin: 5 }
                                    width: 16; height: 16; radius: 8; color: root.seal
                                    Text { anchors.centerIn: parent; text: "✓"; color: root.paper; font.pixelSize: 9 }
                                }

                                MouseArea {
                                    id: imgMa; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.applyWallpaper(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
