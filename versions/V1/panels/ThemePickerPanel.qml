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
    WlrLayershell.namespace: "omarchy-theme-picker"
    WlrLayershell.keyboardFocus: root.themePickerVisible
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real reveal: root.themePickerVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.themePickerVisible ? 160 : 120
            easing.type: root.themePickerVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001

    property var    themes:        []
    property string currentTheme:  ""
    property int    selectedIndex: 0
    property string applying:      ""
    property real   scrollOffset:  0

    Process {
        id: listProc
        command: ["bash", "-c", "omarchy-theme-list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n").filter(function(l){ return l.trim() !== "" })
                panel.themes = lines
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].toLowerCase().replace(/ /g, "-") === panel.currentTheme) {
                        panel.selectedIndex = i; break
                    }
                }
                panel.scrollOffset = Math.max(0, panel.selectedIndex * 34 - 150)
            }
        }
    }
    Process {
        id: currentProc
        command: ["bash", "-c", "omarchy-theme-current"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = this.text.trim().toLowerCase().replace(/ /g, "-")
                panel.currentTheme = raw
                listProc.running = false; listProc.running = true
            }
        }
    }
    Process {
        id: applyProc
        command: []
        stdout: StdioCollector { onStreamFinished: { panel.applying = "" } }
    }

    onRevealChanged: {
        if (reveal > 0.5) {
            currentProc.running = false; currentProc.running = true
            Qt.callLater(function() { searchInput.forceActiveFocus() })
        }
    }

    property string query: ""
    readonly property var filteredThemes: {
        var q = query.toLowerCase().trim()
        if (!q) return themes
        return themes.filter(function(t){ return t.toLowerCase().indexOf(q) >= 0 })
    }

    function applyTheme(name) {
        if (applying !== "") return
        applying = name
        applyProc.command = ["bash", "-c", "omarchy-theme-set '" + name.replace(/'/g, "'\\''") + "'"]
        applyProc.running = false; applyProc.running = true
        root.themePickerVisible = false
    }

    // backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: root.themePickerVisible = false
    }

    // card
    Rectangle {
        width: 240
        height: Math.min(cardCol.implicitHeight + 20, 480)
        x: Math.max(4, root.quickActionsBarX - 120)
        y: 43
        opacity: panel.reveal
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1
        clip: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6

            // header
            Item {
                width: parent.width; height: 26
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Theme"
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
                        onClicked: root.themePickerVisible = false
                    }
                }
            }

            // search
            Item {
                width: parent.width; height: 32
                Rectangle {
                    anchors.fill: parent; radius: 5
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                    border.color: searchInput.activeFocus
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.6) : root.sep
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 100 } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10
                    text: "Search…"; color: root.sumi; font.family: root.mono; font.pixelSize: 12
                    visible: searchInput.text.length === 0
                }
                TextInput {
                    id: searchInput
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                    color: root.ink; font.family: root.mono; font.pixelSize: 12; selectByMouse: true
                    onTextChanged: { panel.query = text; panel.scrollOffset = 0 }
                    Keys.onEscapePressed: { if (text.length > 0) { text = ""; panel.query = "" } else root.themePickerVisible = false }
                    Keys.onReturnPressed: { if (panel.filteredThemes.length > 0) panel.applyTheme(panel.filteredThemes[0]) }
                }
            }

            // list
            Item {
                id: listArea
                width: parent.width
                height: Math.min(panel.filteredThemes.length * 34, 380)
                clip: true

                property real scrollOffset: panel.scrollOffset

                MouseArea {
                    anchors.fill: parent; z: 2; acceptedButtons: Qt.NoButton
                    onWheel: function(w) {
                        var max = Math.max(0, panel.filteredThemes.length * 34 - listArea.height)
                        panel.scrollOffset = Math.max(0, Math.min(panel.scrollOffset - w.angleDelta.y / 2, max))
                    }
                }

                Column {
                    width: listArea.width
                    y: -listArea.scrollOffset
                    spacing: 0

                    Repeater {
                        model: panel.filteredThemes
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: listArea.width; height: 34

                            readonly property bool isCurrent: modelData.toLowerCase().replace(/ /g,"-") === panel.currentTheme
                            readonly property bool isApplying: panel.applying === modelData

                            Rectangle {
                                anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                radius: 4
                                color: isCurrent
                                    ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.14)
                                    : (rowMa.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent")
                                Behavior on color { ColorAnimation { duration: 80 } }

                                MouseArea {
                                    id: rowMa; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.applyTheme(modelData)
                                }

                                Text {
                                    anchors.left: parent.left; anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                    color: isCurrent ? root.seal : root.ink
                                    font.family: root.mono; font.pixelSize: 12
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }

                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: isApplying ? "…" : (isCurrent ? "✓" : "")
                                    color: root.seal; font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
