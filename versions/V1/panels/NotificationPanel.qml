import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: notifPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-notifications"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property var recent: []   // last 3 parsed notifications
    property int activeCount: 0

    // keep root count in sync
    Binding { target: root; property: "notifCount"; value: notifPanel.activeCount }

    property real reveal: root.notifVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.notifVisible ? 160 : 120
            easing.type: root.notifVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.notifVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.notifVisible = false
    }

    // ── parse makoctl history ──
    Process {
        id: historyProc
        command: ["bash", "-c", "makoctl history 2>/dev/null | head -30"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split('\n')
                var list = [], cur = null
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i]
                    var m = l.match(/^Notification (\d+): (.+)/)
                    if (m) {
                        if (cur) list.push(cur)
                        cur = { id: m[1], summary: m[2].trim(), appName: '', body: '' }
                    } else if (cur) {
                        var a = l.match(/^\s+App name:\s+(.+)/)
                        if (a) { cur.appName = a[1].trim(); continue }
                        var b = l.match(/^\s+Body:\s+(.+)/)
                        if (b) cur.body = b[1].trim()
                    }
                }
                if (cur) list.push(cur)
                notifPanel.recent = list.slice(0, 3)
            }
        }
    }

    // ── count active notifications ──
    Process {
        id: countProc
        command: ["bash", "-c", "makoctl list 2>/dev/null | grep -c '^Notification' || echo 0"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                notifPanel.activeCount = parseInt(this.text.trim()) || 0
            }
        }
    }

    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            countProc.running = false; countProc.running = true
        }
    }

    onVisibleChanged: {
        if (visible) {
            historyProc.running = false; historyProc.running = true
            countProc.running = false;   countProc.running = true
        }
    }

    Process { id: dismissAll;   command: ["bash", "-c", "makoctl dismiss --all 2>/dev/null"] }
    Process { id: invokeRunner; command: ["bash", "-c", "true"] }
    function openNotification(id) {
        // invoke the default action (focuses the sending app for active notifications)
        invokeRunner.command = ["bash", "-c", "makoctl invoke -n " + id + " 2>/dev/null || makoctl restore 2>/dev/null"]
        invokeRunner.running = false; invokeRunner.running = true
        root.notifVisible = false
    }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: Math.max(6, root.notifBarX)
        y: barBottom + gap
        opacity: notifPanel.reveal
        focus: root.notifVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.notifVisible = false
                event.accepted = true
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
                    text: "Notifications"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: root.sumi
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.notifVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── notification list ──
            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: notifPanel.recent

                    delegate: Rectangle {
                        required property var modelData
                        width: col.width
                        height: entryCol.implicitHeight + 16
                        radius: 4
                        color: entryMa.containsMouse
                            ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
                            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.color: root.sep
                        border.width: 1

                        Column {
                            id: entryCol
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 8
                            anchors.topMargin: 8
                            spacing: 3

                            Text {
                                text: modelData.appName || "App"
                                color: root.sumi
                                font.family: root.mono
                                font.pixelSize: 10
                                font.letterSpacing: 0.5
                                width: parent.width
                                elide: Text.ElideRight
                            }

                            Text {
                                text: modelData.summary || ""
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 11
                                width: parent.width
                                elide: Text.ElideRight
                                visible: text !== ""
                            }

                            Text {
                                text: modelData.body || ""
                                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                                font.family: root.mono
                                font.pixelSize: 10
                                width: parent.width
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }

                        MouseArea {
                            id: entryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notifPanel.openNotification(modelData.id)
                        }
                    }
                }

                Text {
                    visible: notifPanel.recent.length === 0
                    width: col.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "No notifications"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                    font.family: root.mono
                    font.pixelSize: 11
                }
            }

            // ── dismiss active ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                visible: notifPanel.activeCount > 0
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: root.sep; border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "Dismiss active"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dismissAll.running = false
                        dismissAll.running = true
                        Qt.callLater(function() {
                            countProc.running = false; countProc.running = true
                        })
                    }
                }
            }
        }
    }
}
