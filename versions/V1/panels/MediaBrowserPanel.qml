import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "ImagePickerModel.js" as Model

// Tanzaku filmstrip browser for screenshots & videos. Same language as the
// theme/wallpaper picker: focused media centred & full, thin paper strips for
// the rest, only the immediate neighbour widens to a preview peek, one seal
// brush-stroke under the focus. Video posters generated lazily (focus + peeks).
PanelWindow {
    id: panel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-media-browser"
    WlrLayershell.keyboardFocus: panel.ready ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool active: root.pickerStyle !== "hearthstone"   // tanzaku default
    readonly property bool isVideos: root.mediaBrowserMode === "videos"
    readonly property bool ready: root.mediaBrowserVisible && active && loaded && layoutSettled

    property bool loaded:        false
    property bool layoutSettled: false
    property var  imageArray:    []
    property int  selFilt:       0
    property string filterText:  ""

    visible: root.mediaBrowserVisible && active

    // ── reveal ──
    property real reveal: 0
    Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    onReadyChanged: reveal = ready ? 1 : 0

    // ── filtered list ──
    readonly property var filtered: {
        var out = []
        for (var i = 0; i < imageArray.length; i++) {
            if (!Model.itemMatches(imageArray, i, filterText)) continue
            out.push({
                idx:      i,
                filePath: imageArray[i].filePath,
                thumb:    panel.isVideos ? "" : ("file://" + imageArray[i].thumbnailPath),
                label:    panel.mediaLabel(imageArray[i].filePath),
                isVideo:  panel.isVideos
            })
        }
        return out
    }
    onFilteredChanged: if (selFilt >= filtered.length) selFilt = Math.max(0, filtered.length - 1)

    readonly property string currentLabel:
        (filtered.length > 0 && selFilt >= 0 && selFilt < filtered.length)
            ? filtered[selFilt].label
            : (filterText ? "No matches" : "")

    // ── open / style gating ──
    function syncOpen() {
        if (root.mediaBrowserVisible && active) {
            if (!loaded) {
                panel.layoutSettled = false
                panel.filterText    = ""
                panel.imageArray    = []
                panel.selFilt       = 0
                panel.reveal        = 0
                panel.runScan()
            }
        } else {
            panel.loaded        = false
            panel.layoutSettled = false
            panel.reveal        = 0
        }
    }
    Connections {
        target: root
        function onMediaBrowserVisibleChanged() { panel.syncOpen() }
        function onPickerStyleChanged()          { panel.syncOpen() }
    }

    function buildScanCmd() {
        if (isVideos) {
            return ["bash", "-c",
                "find ~/Videos -maxdepth 1 -type f " +
                "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.avi' -o -iname '*.m4v' \\) " +
                "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -100 | cut -f2-"]
        } else {
            return ["bash", "-c",
                "find ~/Pictures -maxdepth 1 -type f -iname 'screenshot-*.png' " +
                "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -100 | cut -f2- | " +
                "while IFS= read -r f; do printf '%s\\t%s\\n' \"$f\" \"$f\"; done"]
        }
    }

    // scan-result cache → instant (re)open
    readonly property string scanCachePath: Quickshell.env("HOME") + "/.cache/quickshell-scan-" + (isVideos ? "videos" : "screenshots")
    property string _lastScan: ""
    function liveScanCmd() { var c = panel.buildScanCmd(); c[2] = c[2] + " | tee " + panel.shq(panel.scanCachePath); return c }
    function runScan() {
        cacheProc.running = false; cacheProc.running = true
        scanProc.command = panel.liveScanCmd(); scanProc.running = false; scanProc.running = true
    }
    Process {
        id: cacheProc
        command: ["cat", panel.scanCachePath]
        stdout: StdioCollector { onStreamFinished: panel.applyScan(this.text, true) }
    }
    function applyScan(text, fromCache) {
        var t = String(text || "")
        if (fromCache && (!t.trim() || loaded)) return          // don't paint an empty/stale cache
        if (!fromCache && t.trim() === _lastScan.trim() && loaded) return
        _lastScan = t
        var rows = Model.loadRows(t)
        panel.imageArray = rows
        panel.selFilt    = 0
        panel.loaded     = rows.length > 0
        Qt.callLater(function() {
            if (root.mediaBrowserVisible && panel.active) {
                panel.layoutSettled = true
                stage.forceActiveFocus()
                if (!fromCache) warmTimer.restart()
            }
        })
    }
    Process {
        id: scanProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyScan(text, false)
        }
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    // ── background pre-warm at LOW priority (nice), started after the open
    // settles so the burst never competes with the open animation / GUI ──
    Process { id: warmProc; command: [] }
    Timer { id: warmTimer; interval: 450; onTriggered: panel.warmAll() }
    function warmAll() {
        var srcs = []
        for (var i = 0; i < imageArray.length; i++)
            if (imageArray[i].filePath) srcs.push(imageArray[i].filePath)
        if (srcs.length === 0) return
        if (panel.isVideos) {
            warmProc.command = ["bash", "-c",
                "d=$HOME/.cache/quickshell-media-thumbs; mkdir -p \"$d\"; command -v ffmpegthumbnailer >/dev/null 2>&1 || exit 0; " +
                "for s in \"$@\"; do b=$(basename \"$s\"); o=\"$d/${b%.*}.jpg\"; [ -f \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\"; done | " +
                "nice -n 19 xargs -d '\\n' -P 2 -n 2 sh -c 'ffmpegthumbnailer -i \"$0\" -o \"$1\" -s 480 -q 6 >/dev/null 2>&1'",
                "warm"].concat(srcs)
        } else {
            warmProc.command = ["bash", "-c",
                "D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\"; command -v magick >/dev/null 2>&1 || exit 0; " +
                "for s in \"$@\"; do k=$(printf '%s' \"$s\" | md5sum | cut -d' ' -f1); m=$(stat -c %Y \"$s\" 2>/dev/null); " +
                "o=\"$D/$k-$m.jpg\"; [ -f \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\"; done | " +
                "nice -n 19 xargs -d '\\n' -P 3 -n 2 sh -c 'magick \"$0\" -auto-orient -strip -thumbnail 480x270^ -quality 82 \"$1\" >/dev/null 2>&1'",
                "warm"].concat(srcs)
        }
        warmProc.running = false; warmProc.running = true
    }

    function openSelected() {
        if (!loaded || filtered.length === 0) return
        if (selFilt < 0 || selFilt >= filtered.length) return
        var path = filtered[selFilt].filePath; if (!path) return
        Quickshell.execDetached(["xdg-open", path])
        root.mediaBrowserVisible = false
    }

    function moveSel(delta) {
        if (filtered.length === 0) return
        selFilt = Math.max(0, Math.min(filtered.length - 1, selFilt + delta))
    }

    readonly property var sel: (filtered.length > 0 && selFilt >= 0 && selFilt < filtered.length)
                               ? filtered[selFilt] : null

    // ── delete (two-step confirm) + copy ──
    property bool confirmDelete: false
    onSelFiltChanged: confirmDelete = false

    Process {
        id: deleteProc
        command: []
        onExited: {                      // re-scan once the file is gone (refresh + cache)
            scanProc.command = panel.liveScanCmd()
            scanProc.running = false; scanProc.running = true
        }
    }
    function deleteFocused() {
        if (!sel || !sel.filePath) return
        deleteProc.command = ["bash", "-c", "rm -f " + shq(sel.filePath)]
        deleteProc.running = false; deleteProc.running = true
        confirmDelete = false
    }

    Process { id: copyProc; command: [] }
    function copyFocused() {
        if (!sel || !sel.filePath) return
        copyProc.command = panel.isVideos
            ? ["bash", "-c", "printf '%s' " + shq(sel.filePath) + " | wl-copy"]
            : ["bash", "-c", "wl-copy --type image/png < " + shq(sel.filePath)]
        copyProc.running = false; copyProc.running = true
    }

    // "screenshot-01-2025-10-28_19-54-26" → "2025-10-28 19:54"
    function mediaLabel(path) {
        var n = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
        var m = n.match(/(\d{4})-(\d{2})-(\d{2})[_-](\d{2})-(\d{2})-(\d{2})/)
        return m ? (m[1] + "-" + m[2] + "-" + m[3] + "  " + m[4] + ":" + m[5]) : n
    }

    // ── geometry ──
    readonly property int  focusedW:   460
    readonly property int  focusedH:   259
    readonly property int  peekW:      104
    readonly property int  stripW:     24
    readonly property int  gap:        8
    readonly property int  maxVisible: 5

    function stripWidthFor(d) {
        if (d <= 0) return focusedW
        if (d === 1) return peekW
        return stripW
    }

    // ── colors ──
    readonly property color scrim:   Qt.rgba(root.paper.r, root.paper.g, root.paper.b, 0.8)
    readonly property color frameBg: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
    readonly property color uiDim:   Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)

    // ── scrim ──
    Rectangle {
        anchors.fill: parent
        color: panel.scrim
        opacity: panel.reveal
    }
    MouseArea {
        anchors.fill: parent
        enabled: panel.ready
        onClicked: root.mediaBrowserVisible = false
        onWheel: function(wheel) {
            if (!panel.ready) return
            panel.moveSel(wheel.angleDelta.y < 0 ? 1 : -1)
        }
    }

    // ── loading / empty ──
    Text {
        visible: root.mediaBrowserVisible && panel.active && !panel.ready
        anchors.centerIn: parent
        text: panel.layoutSettled && !panel.loaded
              ? (panel.isVideos ? "No recordings in ~/Videos" : "No screenshots in ~/Pictures")
              : "Loading…"
        color: root.ink
        font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 1
    }

    // ── header ──
    Text {
        visible: panel.ready
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: stage.top
        anchors.bottomMargin: 22
        opacity: panel.reveal
        text: panel.isVideos ? "VIDEOS" : "SCREENSHOTS"
        color: root.sumi
        font.family: root.mono; font.pixelSize: 12; font.letterSpacing: 3; font.weight: Font.Medium
        horizontalAlignment: Text.AlignHCenter
    }

    // ── the stage (filmstrip) ──
    Item {
        id: stage
        visible: panel.ready && panel.filtered.length > 0
        focus: true
        opacity: panel.reveal
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -10 + (1 - panel.reveal) * 14
        width: parent.width
        height: panel.focusedH

        readonly property real cx:     width / 2
        readonly property real fLeft:  cx - panel.focusedW / 2
        readonly property real fRight: cx + panel.focusedW / 2

        function xForRel(r) {
            if (r === 0) return fLeft
            var x
            if (r < 0) {
                x = fLeft
                for (var k = -1; k >= r; k--) x = x - panel.gap - panel.stripWidthFor(-k)
                return x
            }
            x = fRight + panel.gap
            for (var j = 1; j < r; j++) x = x + panel.stripWidthFor(j) + panel.gap
            return x
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (panel.confirmDelete) panel.confirmDelete = false
                else if (panel.filterText) panel.filterText = ""
                else root.mediaBrowserVisible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Delete) {
                if (panel.confirmDelete) panel.deleteFocused()
                else panel.confirmDelete = true
                event.accepted = true
            } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                panel.copyFocused(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.openSelected(); event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                if (panel.filterText.length > 0) panel.filterText = panel.filterText.slice(0, -1)
                event.accepted = true
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
                       || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                panel.moveSel(-1); event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                panel.moveSel(1); event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                       && event.text.charCodeAt(0) !== 127
                       && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                panel.filterText += event.text; event.accepted = true
            }
        }

        Repeater {
            model: panel.filtered.length

            delegate: Item {
                id: item
                required property int index
                readonly property var  entry:   panel.filtered[index] || null
                readonly property int  relIdx:  index - panel.selFilt
                readonly property bool focused: relIdx === 0
                readonly property bool near:    Math.abs(relIdx) <= panel.maxVisible
                // every visible tile gets a thumbnail (videos + screenshots);
                // the background pre-warm fills the rest so fast scrubbing keeps up
                readonly property bool wantThumb: panel.ready && near && entry

                width:  panel.stripWidthFor(Math.abs(relIdx))
                height: panel.focusedH
                y: 0
                x: stage.xForRel(relIdx)
                z: focused ? 100 : 50 - Math.abs(relIdx)
                visible: near
                opacity: near ? 1 : 0

                Behavior on x       { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on width   { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }

                // ── lazy cached thumbnail (480px jpg) — videos via ffmpegthumbnailer,
                // screenshots via magick; full-size sources are never decoded live ──
                property string thumbPath: ""
                Process {
                    id: thumbProc
                    running: false
                    command: []
                    stdout: StdioCollector {
                        onStreamFinished: { var p = this.text.trim(); if (p) item.thumbPath = "file://" + p }
                    }
                }
                function ensureThumb() {
                    if (!wantThumb || thumbPath) return
                    var fp = entry.filePath; if (!fp) return
                    if (panel.isVideos) {
                        thumbProc.command = ["bash", "-c",
                            "d=$HOME/.cache/quickshell-media-thumbs; mkdir -p \"$d\"; " +
                            "b=$(basename " + panel.shq(fp) + "); o=\"$d/${b%.*}.jpg\"; " +
                            "[ -f \"$o\" ] || nice -n 10 ffmpegthumbnailer -i " + panel.shq(fp) +
                            " -o \"$o\" -s 480 -q 6 >/dev/null 2>&1; echo \"$o\""]
                    } else {
                        thumbProc.command = ["bash", "-c",
                            "s=" + panel.shq(fp) + "; D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\"; " +
                            "k=$(printf '%s' \"$s\" | md5sum | cut -d' ' -f1); m=$(stat -c %Y \"$s\" 2>/dev/null); o=\"$D/$k-$m.jpg\"; " +
                            "if command -v magick >/dev/null 2>&1; then [ -f \"$o\" ] || nice -n 10 magick \"$s\" -auto-orient -strip -thumbnail 480x270^ -quality 82 \"$o\" >/dev/null 2>&1; fi; " +
                            "[ -f \"$o\" ] && echo \"$o\" || echo \"$s\""]
                    }
                    thumbProc.running = false; thumbProc.running = true
                }
                onWantThumbChanged: if (wantThumb) ensureThumb()
                Component.onCompleted: ensureThumb()

                // hairline frame (rounded; image inset so corners read round)
                Rectangle {
                    id: frame
                    anchors.fill: parent
                    radius: 8
                    color: panel.frameBg
                    border.width: 1
                    border.color: item.focused ? root.seal : root.sep
                    clip: true
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    // image / poster — no per-item layer effect (keeps the width
                    // animation smooth); inset gives the rounded look
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        // always the cached 480px thumb (never the full source);
                        // current-visibility bound → bounded memory
                        source: (panel.ready && item.near && item.entry) ? item.thumbPath : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
                        sourceSize.width:  panel.focusedW
                        sourceSize.height: panel.focusedH
                    }
                    // play glyph (videos, only on focus + peeks where it fits)
                    Text {
                        visible: panel.isVideos && Math.abs(item.relIdx) <= 1
                        anchors.centerIn: parent
                        text: ""   // play_arrow
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: item.focused ? 40 : 20
                        color: Qt.rgba(1, 1, 1, 0.9)
                        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
                    }
                    // paper-wash dim; the preview peek lighter
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 3
                        color: root.paper
                        opacity: item.focused ? 0 : (Math.abs(item.relIdx) === 1 ? 0.28 : 0.5)
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: item.focused ? panel.openSelected() : (panel.selFilt = index)
                }
            }
        }
    }

    // ── brush-stroke + label + hint ──
    Column {
        visible: panel.ready && panel.filtered.length > 0
        opacity: panel.reveal
        anchors.top: stage.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: stage.horizontalCenter
        spacing: 12

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: panel.focusedW * 0.42
            height: 3; radius: 1.5
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.5;  color: root.seal }
                GradientStop { position: 1.0;  color: "transparent" }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: panel.focusedW + 160
            text: (panel.isVideos ? "Videos · " : "Screenshots · ") + panel.currentLabel
            color: root.ink
            font.family: root.mono; font.pixelSize: 22; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Text {
            visible: panel.filterText.length > 0 && !panel.confirmDelete
            anchors.horizontalCenter: parent.horizontalCenter
            text: panel.filterText
            color: root.seal; opacity: 0.95
            font.family: root.mono; font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }

        // delete confirmation prompt (replaces the hint while armed)
        Text {
            visible: panel.confirmDelete
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Delete this " + (panel.isVideos ? "video" : "screenshot")
                  + "?   Del again to confirm   ·   Esc cancel"
            color: root.seal
            font.family: root.mono; font.pixelSize: 11; font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: !panel.confirmDelete
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← →  scroll navigate     Enter open     Del delete     Ctrl+C copy     Esc"
            color: panel.uiDim
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
