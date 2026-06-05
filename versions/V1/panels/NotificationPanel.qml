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

    readonly property int barBottom: 35
    readonly property int gap: 8

    // all parsed notifications (active popups + mako history), deduped by id
    property var recent: []
    // set of ids the user has dismissed in the panel (persisted)
    property var dismissedIds: ({})

    // pending = not yet dismissed → drives both the list and the badge
    readonly property var pending: {
        var out = []
        for (var i = 0; i < recent.length; i++) {
            var id = parseInt(recent[i].id) || 0
            if (!dismissedIds[id]) out.push(recent[i])
        }
        return out
    }
    readonly property int unreadCount: pending.length
    readonly property int maxShown: 6
    readonly property var shownNotifs: pending.slice(0, maxShown)

    readonly property string dismPath: "${XDG_CACHE_HOME:-$HOME/.cache}/qs-rise-notif-dismissed"

    Binding { target: root; property: "notifCount"; value: notifPanel.unreadCount }

    Component.onCompleted: loadDism.running = true

    // load the persisted dismissed-id set, then do a first parse
    Process {
        id: loadDism
        command: ["bash", "-c", "cat \"" + notifPanel.dismPath + "\" 2>/dev/null || echo ''"]
        stdout: StdioCollector { onStreamFinished: {
            var d = {}
            var parts = this.text.trim().split(',')
            for (var i = 0; i < parts.length; i++) {
                var n = parseInt(parts[i]); if (!isNaN(n)) d[n] = true
            }
            notifPanel.dismissedIds = d
            historyProc.running = false; historyProc.running = true
        }}
    }

    Process { id: saveDism; command: ["bash", "-c", "true"] }
    function persistDismissed() {
        var keys = Object.keys(notifPanel.dismissedIds)
        saveDism.command = ["bash", "-c",
            "mkdir -p \"$(dirname \"" + notifPanel.dismPath + "\")\"; echo '" + keys.join(",") + "' > \"" + notifPanel.dismPath + "\""]
        saveDism.running = false; saveDism.running = true
    }

    function dismissOne(id) {
        var nd = {}
        for (var k in notifPanel.dismissedIds) nd[k] = true
        nd[parseInt(id)] = true
        notifPanel.dismissedIds = nd          // reassign → bindings update
        persistDismissed()
        // also clear it from mako if it's still an active popup
        actionProc.command = ["bash", "-c", "makoctl dismiss -n " + id + " 2>/dev/null || true"]
        actionProc.running = false; actionProc.running = true
    }

    function dismissAll() {
        var nd = {}
        for (var k in notifPanel.dismissedIds) nd[k] = true
        for (var i = 0; i < notifPanel.recent.length; i++) nd[parseInt(notifPanel.recent[i].id)] = true
        notifPanel.dismissedIds = nd
        persistDismissed()
        actionProc.command = ["bash", "-c", "makoctl dismiss --all 2>/dev/null || true"]
        actionProc.running = false; actionProc.running = true
    }

    Process { id: actionProc; command: ["bash", "-c", "true"] }

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

    // ── parse active popups + history into `recent` (deduped by id) ──
    Process {
        id: historyProc
        command: ["bash", "-c", "(makoctl list 2>/dev/null; makoctl history 2>/dev/null) | head -120"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split('\n')
                var list = [], cur = null, seen = {}
                function flush() {
                    if (cur && !seen[cur.id]) { seen[cur.id] = true; list.push(cur) }
                    cur = null
                }
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i]
                    var m = l.match(/^Notification (\d+): (.*)/)
                    if (m) {
                        flush()
                        cur = { id: m[1], summary: (m[2] || "").trim(), appName: '', body: '' }
                    } else if (cur) {
                        var a = l.match(/^\s+App name:\s+(.+)/)
                        if (a) { cur.appName = a[1].trim(); continue }
                        var b = l.match(/^\s+Body:\s+(.+)/)
                        if (b) cur.body = b[1].trim()
                    }
                }
                flush()
                notifPanel.recent = list

                // prune dismissed ids that are no longer present (keeps the set small)
                var nd = {}, changed = false
                for (var k in notifPanel.dismissedIds) {
                    if (seen[k]) nd[k] = true; else changed = true
                }
                if (changed) { notifPanel.dismissedIds = nd; notifPanel.persistDismissed() }
            }
        }
    }

    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { historyProc.running = false; historyProc.running = true }
    }

    onVisibleChanged: {
        if (visible) { historyProc.running = false; historyProc.running = true }
    }

    Process { id: invokeRunner; command: ["bash", "-c", "true"] }
    function openNotification(id) {
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
                    text: notifPanel.unreadCount > 0 ? "Notifications · " + notifPanel.unreadCount : "Notifications"
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

            // ── notification list (each individually dismissable) ──
            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: notifPanel.shownNotifs

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
                            anchors.rightMargin: 26   // leave room for the ✕
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

                        // click body → focus the app
                        MouseArea {
                            id: entryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notifPanel.openNotification(modelData.id)
                        }

                        // per-item dismiss ✕ (on top, top-right corner)
                        Rectangle {
                            anchors.top: parent.top; anchors.right: parent.right
                            anchors.topMargin: 4; anchors.rightMargin: 4
                            width: 18; height: 18; radius: 9
                            color: xMa.containsMouse ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.20) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: xMa.containsMouse ? root.seal : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: xMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notifPanel.dismissOne(modelData.id)
                            }
                        }
                    }
                }

                // "+N more" hint when the list is capped
                Text {
                    visible: notifPanel.pending.length > notifPanel.maxShown
                    width: col.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "+ " + (notifPanel.pending.length - notifPanel.maxShown) + " more"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
                    font.family: root.mono
                    font.pixelSize: 10
                }

                Text {
                    visible: notifPanel.pending.length === 0
                    width: col.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "No notifications"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                    font.family: root.mono
                    font.pixelSize: 11
                }
            }

            // ── clear all ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                visible: notifPanel.pending.length > 0
                readonly property bool hovered: clearMa.containsMouse
                color: hovered ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                border.color: hovered ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: clearMa.containsMouse ? root.seal : root.sumi
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: clearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notifPanel.dismissAll()
                }
            }
        }
    }
}
