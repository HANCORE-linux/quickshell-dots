import QtQuick
import "../modules"
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Notifications

PanelWindow {
    id: notifPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-notifications"

    readonly property int barBottom: 35
    readonly property int gap: 8

    AudioData { id: notificationAudio }

    // Quickshell is the notification server. History is retained locally so it
    // survives reloads without polling an external notification daemon.
    property var recent: []             // [{key,id,appName,summary,body,firstSeen,active,notification}]
    readonly property int historyLimit: 10
    property var dismissed: ({})         // composite-key -> true (persisted)
    property int seq: 0                  // monotonic first-seen counter (ordering)
    property bool cacheLoaded: false
    property string lastSaved: ""
    property string pendingSave: ""
    property bool cacheWritePending: false
    // Notifications can arrive as soon as the D-Bus service is owned, before
    // FileView finishes its first read. Keep their live objects until history
    // is ready instead of silently dropping that small startup window.
    property var earlyNotifications: []
    property double lastSoundAt: 0
    property string queuedSound: ""
    property bool queuedSoundCritical: false
    readonly property int soundGap: 220
    readonly property int earlyLimit: 32
    readonly property int appNameLimit: 128
    readonly property int summaryLimit: 512
    readonly property int bodyLimit: 4096

    // pending = not dismissed → drives both the list and the badge
    readonly property var pending: {
        var out = []
        for (var i = 0; i < recent.length; i++)
            if (!dismissed[recent[i].key]) out.push(recent[i])
        return out
    }
    readonly property int unreadCount: pending.length
    // scrollable list height cap, clamped to the monitor
    readonly property int listCap: Math.max(120, Math.min(420, notifPanel.height - 220))

    Binding { target: root; property: "notifCount"; value: notifPanel.unreadCount }

    // ── persistent cache (quickshell is the sole writer; write only on change) ──
    readonly property string cachePath: Quickshell.env("HOME") + "/.cache/qs-rise-notifications.json"
    FileView {
        id: cacheFile
        path: notifPanel.cachePath
        onLoaded: {
            try {
                var j = JSON.parse(cacheFile.text())
                var parsedSeq = Number(j.seq)
                notifPanel.seq = isFinite(parsedSeq) && parsedSeq >= 0
                    ? Math.floor(parsedSeq) : 0
                notifPanel.recent = notifPanel.normalizeCachedRows(j.recent)
                var cachedDismissed = (j.dismissed && typeof j.dismissed === "object")
                    ? j.dismissed : ({})
                notifPanel.dismissed = notifPanel.compactDismissed(
                    notifPanel.recent, cachedDismissed)
                notifPanel.lastSaved    = cacheFile.text()
            } catch (e) {
                notifPanel.seq = 0; notifPanel.recent = []; notifPanel.dismissed = ({})
            }
            notifPanel.cacheLoaded = true
            notifPanel.saveCache()      // persiste también el recorte de un historial antiguo
            notifPanel.drainEarlyNotifications()
        }
        onLoadFailed: {                  // first run: no cache yet
            notifPanel.cacheLoaded = true
            notifPanel.drainEarlyNotifications()
        }
        onSaved: {
            notifPanel.lastSaved = notifPanel.pendingSave
            notifPanel.pendingSave = ""
            notifPanel.cacheWritePending = false
            if (notifPanel.cacheState() !== notifPanel.lastSaved)
                cacheSaveDebounce.restart()
        }
        onSaveFailed: function(error) {
            notifPanel.pendingSave = ""
            notifPanel.cacheWritePending = false
        }
    }
    // force the initial load (don't rely on implicit auto-load) — the whole panel
    // is gated on cacheLoaded, so a missed load would mean no notifications ever
    Component.onCompleted: cacheFile.reload()

    function boundedText(value, limit) {
        if (value === undefined || value === null) return ""
        var s = String(value)
        if (s.length <= limit) return s
        return s.slice(0, Math.max(0, limit - 1)) + "…"
    }

    function normalizeCachedRows(value) {
        if (!Array.isArray(value)) return []
        var out = [], seen = ({})
        for (var i = 0; i < value.length && out.length < notifPanel.historyLimit; i++) {
            var row = value[i]
            if (!row || typeof row !== "object") continue
            var key = notifPanel.boundedText(row.key, 128)
            if (key === "" || seen[key]) continue
            seen[key] = true
            var firstSeen = Number(row.firstSeen)
            if (!isFinite(firstSeen) || firstSeen < 0) firstSeen = 0
            out.push({ key: key, id: row.id,
                       appName: notifPanel.boundedText(row.appName, notifPanel.appNameLimit),
                       summary: notifPanel.boundedText(row.summary, notifPanel.summaryLimit),
                       body: notifPanel.boundedText(row.body, notifPanel.bodyLimit),
                       firstSeen: Math.floor(firstSeen), active: false,
                       notification: null })
        }
        return out
    }

    function compactDismissed(rows, source) {
        var out = ({})
        if (!source || typeof source !== "object") return out
        for (var i = 0; i < rows.length; i++)
            if (source[rows[i].key]) out[rows[i].key] = true
        return out
    }

    function cacheState() {
        notifPanel.dismissed = notifPanel.compactDismissed(
            notifPanel.recent, notifPanel.dismissed)
        var rows = notifPanel.recent.map(function(entry) {
            return { key: entry.key, id: entry.id, appName: entry.appName,
                     summary: entry.summary, body: entry.body,
                     firstSeen: entry.firstSeen, active: false }
        })
        return JSON.stringify({ seq: notifPanel.seq, recent: rows,
                                dismissed: notifPanel.dismissed })
    }

    function saveCache() {
        if (notifPanel.cacheLoaded) cacheSaveDebounce.restart()
    }

    function flushCache() {
        var state = notifPanel.cacheState()
        if (state === notifPanel.lastSaved) return
        if (notifPanel.cacheWritePending) {
            cacheSaveDebounce.restart()
            return
        }
        notifPanel.pendingSave = state
        notifPanel.cacheWritePending = true
        cacheFile.setText(state)
    }

    // Collapse a burst into one atomic FileView write. This avoids spawning an
    // operation for every D-Bus event while preserving the newest state.
    Timer {
        id: cacheSaveDebounce
        interval: 80
        repeat: false
        onTriggered: notifPanel.flushCache()
    }

    // At most one sound every 220 ms. A burst keeps only its newest sound,
    // while a critical event takes priority over a normal one.
    Timer {
        id: soundThrottle
        interval: notifPanel.soundGap
        repeat: false
        onTriggered: {
            var sound = notifPanel.queuedSound
            notifPanel.queuedSound = ""
            notifPanel.queuedSoundCritical = false
            if (sound !== "" && !root.notifSilenced)
                notifPanel.playNotificationSoundNow(sound)
        }
    }

    function playNotificationSoundNow(sound) {
        notifPanel.lastSoundAt = Date.now()
        var sink = notificationAudio.sink
        var props = sink ? (sink.properties || ({})) : ({})
        var output = sink ? [sink.name || "", sink.description || "", sink.nickname || "",
                             props["device.form_factor"] || "", props["device.icon-name"] || ""]
                              .join(" ").toLowerCase() : ""
        // Event gain only: do not alter the user's master volume. Headphones
        // need extra attenuation because a full-scale desktop chime is harsh
        // at close range (Barracuda and common headset labels are detected).
        var gain = /(headphone|headset|auricular|earbud|airpod|barracuda|\bbuds\b)/.test(output)
                   ? "-12.0" : "-5.0"
        Quickshell.execDetached(["canberra-gtk-play", "-i", sound,
                                 "-V", gain, "-d", "Desktop notification"])
    }

    function queueNotificationSound(notification) {
        if (root.notifSilenced || notification.urgency === NotificationUrgency.Low) return

        var hints = notification.hints || ({})
        var suppress = hints["suppress-sound"]
        if (suppress === true || suppress === 1
                || (typeof suppress === "string"
                    && suppress.toLowerCase() !== "false"
                    && suppress !== "0" && suppress !== "")) return

        var requested = hints["sound-name"] || ""
        // Sound names are theme identifiers, never shell input or paths.
        if (typeof requested !== "string" || !/^[A-Za-z0-9._-]{1,80}$/.test(requested)
                || requested.toLowerCase() === "none") requested = ""
        var critical = notification.urgency === NotificationUrgency.Critical
        var sound = requested !== "" ? requested
                    : (critical ? "dialog-warning" : "message")

        var elapsed = Date.now() - notifPanel.lastSoundAt
        if (!soundThrottle.running && elapsed >= notifPanel.soundGap) {
            notifPanel.playNotificationSoundNow(sound)
            return
        }
        // Never let a later normal event downgrade a queued critical alert.
        if (notifPanel.queuedSound === "" || !notifPanel.queuedSoundCritical || critical) {
            notifPanel.queuedSound = sound
            notifPanel.queuedSoundCritical = critical
        }
        soundThrottle.interval = Math.max(1, notifPanel.soundGap - elapsed)
        soundThrottle.restart()
    }

    function acceptNotification(notification) {
        var entry = { key: "qs:" + (++notifPanel.seq), id: notification.id,
                      appName: notifPanel.boundedText(root.notificationAppName(notification), notifPanel.appNameLimit),
                      summary: notifPanel.boundedText(notification.summary, notifPanel.summaryLimit),
                      body: notifPanel.boundedText(notification.body, notifPanel.bodyLimit),
                      firstSeen: notifPanel.seq,
                      active: true, notification: notification }
        var rows = [entry].concat(notifPanel.recent)
        if (rows.length > notifPanel.historyLimit) rows = rows.slice(0, notifPanel.historyLimit)
        notifPanel.recent = rows
        notifPanel.dismissed = notifPanel.compactDismissed(rows, notifPanel.dismissed)
        notifPanel.saveCache()

        // Toast + sound only outside DND. In DND the strings remain in history,
        // but a notification retained during startup can now be released.
        if (root.notifSilenced) {
            notification.tracked = false
            return
        }
        notification.tracked = true
        notifPanel.queueNotificationSound(notification)
        root.notifyToast(notification)
    }

    function drainEarlyNotifications() {
        if (!notifPanel.cacheLoaded || notifPanel.earlyNotifications.length === 0) return
        var queued = notifPanel.earlyNotifications.slice()
        notifPanel.earlyNotifications = []
        for (var i = 0; i < queued.length; i++) notifPanel.acceptNotification(queued[i])
    }

    NotificationServer {
        id: notificationServer
        // false: mantenerlas re-entregaba las vivas en cada reload (historial
        // duplicado); los toasts tampoco deben sobrevivir un reload
        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        onNotification: function(notification) {
            // regla heredada de mako user-rules.ini: warnings Wayland de fcitx5
            // son ruido conocido (ver memoria fcitx5_wayland_warnings)
            if ((notification.appName || "") === "Fcitx"
                    && /Wayland/.test(notification.summary || "")) {
                notification.dismiss()
                return
            }
            if (!notifPanel.cacheLoaded) {
                // Retainable: without tracked=true Quickshell may discard the
                // object before FileView completes and the queue is drained.
                notification.tracked = true
                var early = notifPanel.earlyNotifications.concat([notification])
                if (early.length > notifPanel.earlyLimit) {
                    var released = early.shift()
                    released.tracked = false
                }
                notifPanel.earlyNotifications = early
                return
            }
            notifPanel.acceptNotification(notification)
        }
    }

    // ── actions ──
    function dismissOne(entry) {
        var nd = {}
        for (var k in notifPanel.dismissed) nd[k] = true
        nd[entry.key] = true
        notifPanel.dismissed = nd                // reassign → bindings update
        if (entry.notification) entry.notification.dismiss()
        notifPanel.saveCache()
    }

    function dismissAll() {
        for (var i = 0; i < notifPanel.recent.length; i++)
            if (notifPanel.recent[i].notification) notifPanel.recent[i].notification.dismiss()
        notifPanel.recent = []
        notifPanel.dismissed = ({})
        notifPanel.saveCache()
    }

    function openNotification(entry) {
        root.notifVisible = false
    }

    property real reveal: root.notifVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.notifVisible ? 200 : 140
            easing.type: root.notifVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    // receta popover macOS: movimiento+escala en reloj aparte y más largo
    // que el fade (320 vs ~200ms) — entra desde la barra y asienta suave
    property real slide: root.notifVisible ? 1 : 0
    Behavior on slide {
        NumberAnimation {
            duration: root.notifVisible ? 320 : 140
            easing.type: root.notifVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.notifVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None


    MouseArea {
        anchors.fill: parent
        onClicked: root.notifVisible = false
    }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.notifBarX, parent.width - width - 6)))
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
        opacity: notifPanel.reveal
        transform: Translate { y: (1 - notifPanel.slide) * (notifPanel.root.barPosition === "bottom" ? 10 : -10) }
        scale: 0.97 + 0.03 * notifPanel.slide
        transformOrigin: notifPanel.root.barPosition === "bottom" ? Item.Bottom : Item.Top
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
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: notifPanel.unreadCount > 0 ? "Notificaciones · " + notifPanel.unreadCount : "Notificaciones"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── notification list (scrollable; each individually dismissable) ──
            Flickable {
                width: parent.width
                height: Math.min(listCol.implicitHeight, notifPanel.listCap)
                contentHeight: listCol.implicitHeight
                clip: true
                interactive: listCol.implicitHeight > notifPanel.listCap
                boundsBehavior: Flickable.StopAtBounds   // no overshoot/rebound at the top/bottom edge
                flickableDirection: Flickable.VerticalFlick

                Column {
                    id: listCol
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: notifPanel.pending

                        delegate: Rectangle {
                            required property var modelData
                            width: listCol.width
                            height: entryCol.implicitHeight + 16
                            radius: root.tileRadius
                            color: entryMa.containsMouse ? root.fillHover : root.fillIdle
                            border.color: entryMa.containsMouse ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Column {
                                id: entryCol
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.margins: 8
                                anchors.topMargin: 8
                                anchors.rightMargin: 26   // leave room for the ✕
                                spacing: 3

                                UiText {
                                    text: modelData.appName || "App"
                                    color: root.sumiHi
                                    font.family: root.mono
                                    font.pixelSize: 10
                                    font.letterSpacing: 0.5
                                    width: parent.width
                                    elide: Text.ElideRight
                                }
                                UiText {
                                    text: modelData.summary || ""
                                    color: root.ink
                                    font.family: root.mono
                                    font.pixelSize: 11
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }
                                UiText {
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

                            // click body → focus the app (only if still active in mako)
                            MouseArea {
                                id: entryMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notifPanel.openNotification(modelData)
                            }

                            // per-item dismiss ✕ (on top, top-right corner)
                            Rectangle {
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.topMargin: 4; anchors.rightMargin: 4
                                width: 18; height: 18; radius: 9
                                color: "transparent"
                                UiText {
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
                                    onClicked: notifPanel.dismissOne(modelData)
                                }
                            }
                        }
                    }

                    UiText {
                        visible: notifPanel.pending.length === 0
                        width: listCol.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Sin notificaciones"
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                        font.family: root.mono
                        font.pixelSize: 11
                    }
                }
            }

            // ── clear all ──
            Rectangle {
                width: parent.width
                height: 28; radius: root.tileRadius
                visible: notifPanel.pending.length > 0
                readonly property bool hovered: clearMa.containsMouse
                color: hovered ? root.fillHover : root.fillIdle
                border.color: hovered ? root.seal : root.sep
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: "Borrar todo"
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
