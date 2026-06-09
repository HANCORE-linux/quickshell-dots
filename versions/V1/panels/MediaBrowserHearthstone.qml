import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "ImagePickerModel.js" as Model

// Hearthstone (card-deck) variant of the screenshot/video browser. Original felt
// look + fanned cards on the same fast data layer as the Tanzaku media browser
// (cached thumbnails, niced pre-warm, delete/copy). Active only while
// pickerStyle == "hearthstone".
PanelWindow {
    id: panel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-media-browser-hs"
    WlrLayershell.keyboardFocus: panel.ready ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool active: root.pickerStyle === "hearthstone"
    readonly property bool isVideos: root.mediaBrowserMode === "videos"
    readonly property bool ready: root.mediaBrowserVisible && active && loaded && layoutSettled

    property bool loaded:        false
    property bool layoutSettled: false
    property var  imageArray:    []
    property int  selFilt:       0
    property string filterText:  ""

    visible: root.mediaBrowserVisible && active

    // ── reveal + deal ──
    property real reveal: 0
    Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    property real dealT: 0
    Behavior on dealT { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    onReadyChanged: { reveal = ready ? 1 : 0; if (ready) dealT = 1 }

    // ── filtered list ──
    readonly property var filtered: {
        var out = []
        for (var i = 0; i < imageArray.length; i++) {
            if (!Model.itemMatches(imageArray, i, filterText)) continue
            out.push({
                idx:      i,
                filePath: imageArray[i].filePath,
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
                panel.dealT         = 0
                panel.runScan()
            }
        } else {
            panel.loaded        = false
            panel.layoutSettled = false
            panel.reveal        = 0
            panel.dealT         = 0
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

    // scan-result cache → instant (re)open (shared with the Tanzaku media browser)
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
        if (fromCache && (!t.trim() || loaded)) return
        if (!fromCache && t.trim() === _lastScan.trim() && loaded) return
        _lastScan = t
        var rows = Model.loadRows(t)
        panel.imageArray = rows
        panel.selFilt    = 0
        panel.loaded     = rows.length > 0
        Qt.callLater(function() {
            if (root.mediaBrowserVisible && panel.active) {
                panel.layoutSettled = true
                hand.forceActiveFocus()
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

    // ── background pre-warm (nice; after open settles) ──
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
                "for s in \"$@\"; do b=$(basename \"$s\"); o=\"$d/${b%.*}-512.jpg\"; [ -f \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\"; done | " +
                "nice -n 19 xargs -d '\\n' -P 2 -n 2 sh -c 'ffmpegthumbnailer -i \"$0\" -o \"$1\" -s 910 -q 6 >/dev/null 2>&1'",
                "warm"].concat(srcs)
        } else {
            warmProc.command = ["bash", "-c",
                "D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\"; command -v magick >/dev/null 2>&1 || exit 0; " +
                "for s in \"$@\"; do k=$(printf '%s' \"$s\" | md5sum | cut -d' ' -f1); m=$(stat -c %Y \"$s\" 2>/dev/null); " +
                "o=\"$D/$k-$m-512.jpg\"; [ -f \"$o\" ] && continue; printf '%s\\n%s\\n' \"$s\" \"$o\"; done | " +
                "nice -n 19 xargs -d '\\n' -P 3 -n 2 sh -c 'magick \"$0\" -auto-orient -strip -thumbnail 512x512^ -quality 82 \"$1\" >/dev/null 2>&1'",
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
        onExited: {
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

    function mediaLabel(path) {
        var n = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
        var m = n.match(/(\d{4})-(\d{2})-(\d{2})[_-](\d{2})-(\d{2})-(\d{2})/)
        return m ? (m[1] + "-" + m[2] + "-" + m[3] + "  " + m[4] + ":" + m[5]) : n
    }

    // ── card-hand geometry ──
    readonly property int  cardW:      232
    readonly property int  cardH:      330
    readonly property real focusScale: 1.24
    readonly property real spreadDeg:  6.0
    readonly property real stepX:      128
    readonly property real focusLift:  54
    readonly property int  maxVisible: 5

    // ── felt look ──
    readonly property color feltColor: Qt.rgba(0.035, 0.035, 0.05, 0.975)
    readonly property color frameDark: "#16161c"
    readonly property color textLight: "#ECECEE"
    readonly property color textDim:   Qt.rgba(0.92, 0.92, 0.94, 0.55)

    // ── felt scrim ──
    Rectangle {
        anchors.fill: parent
        color: panel.feltColor
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
        color: panel.textLight
        font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 1
    }

    // ── header + position (top) ──
    Text {
        visible: panel.ready && panel.filtered.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 40
        opacity: panel.reveal
        text: (panel.isVideos ? "VIDEOS" : "SCREENSHOTS") + "      " + (panel.selFilt + 1) + " / " + panel.filtered.length
        color: panel.textDim
        font.family: root.mono; font.pixelSize: 12; font.letterSpacing: 2
    }

    // ── the hand ──
    Item {
        id: hand
        visible: panel.ready && panel.filtered.length > 0
        focus: true
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -16
        width: parent.width
        height: panel.cardH + panel.focusLift + 40

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
                id: card
                required property int index
                readonly property var  entry:   panel.filtered[index] || null
                readonly property int  relIdx:  index - panel.selFilt
                readonly property bool focused: relIdx === 0
                readonly property bool nearby:  Math.abs(relIdx) <= panel.maxVisible
                readonly property real dim: focused ? 0.0 : Math.min(0.62, 0.30 + Math.abs(relIdx) * 0.05)

                // lazy cached thumbnail (video poster or screenshot thumb)
                property string thumbPath: ""
                Process {
                    id: thumbProc
                    command: []
                    stdout: StdioCollector {
                        onStreamFinished: { var p = this.text.trim(); if (p) card.thumbPath = "file://" + p }
                    }
                }
                function ensureThumb() {
                    if (thumbPath || !panel.ready || !nearby || !entry) return
                    var fp = entry.filePath; if (!fp) return
                    if (panel.isVideos) {
                        thumbProc.command = ["bash", "-c",
                            "d=$HOME/.cache/quickshell-media-thumbs; mkdir -p \"$d\"; " +
                            "b=$(basename " + panel.shq(fp) + "); o=\"$d/${b%.*}-512.jpg\"; " +
                            "[ -s \"$o\" ] || nice -n 10 ffmpegthumbnailer -i " + panel.shq(fp) +
                            " -o \"$o\" -s 910 -q 6 >/dev/null 2>&1; [ -s \"$o\" ] && echo \"$o\""]
                    } else {
                        thumbProc.command = ["bash", "-c",
                            "s=" + panel.shq(fp) + "; D=$HOME/.cache/quickshell-img-thumbs; mkdir -p \"$D\"; " +
                            "k=$(printf '%s' \"$s\" | md5sum | cut -d' ' -f1); m=$(stat -c %Y \"$s\" 2>/dev/null); o=\"$D/$k-$m-512.jpg\"; " +
                            "if command -v magick >/dev/null 2>&1; then [ -f \"$o\" ] || nice -n 10 magick \"$s\" -auto-orient -strip -thumbnail 512x512^ -quality 82 \"$o\" >/dev/null 2>&1; fi; " +
                            "[ -f \"$o\" ] && echo \"$o\" || echo \"$s\""]
                    }
                    thumbProc.running = false; thumbProc.running = true
                }
                onNearbyChanged: if (nearby) ensureThumb()
                Component.onCompleted: ensureThumb()
                Connections { target: panel; function onReadyChanged() { if (panel.ready) card.ensureThumb() } }

                width: panel.cardW; height: panel.cardH
                visible: nearby
                transformOrigin: Item.Bottom

                x: (hand.width  - panel.cardW) / 2 + relIdx * panel.stepX * panel.dealT
                y: (hand.height - panel.cardH)     - (focused ? panel.focusLift * panel.dealT : 0)
                rotation: relIdx * panel.spreadDeg * panel.dealT
                scale: focused ? 1 + (panel.focusScale - 1) * panel.dealT : 1
                z: focused ? 1000 : 500 - Math.min(Math.abs(relIdx), 40)
                opacity: panel.dealT

                Behavior on x        { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on y        { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on scale    { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                // photo/poster (raster) — edges hidden behind the passepartout
                Item {
                    anchors.fill: parent
                    anchors.margins: 6
                    Image {
                        anchors.fill: parent
                        source: (panel.ready && card.nearby && card.entry) ? card.thumbPath : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
                        sourceSize.width:  panel.cardW * 2
                        sourceSize.height: panel.cardH * 2
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 70
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                        }
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                        text: card.entry ? card.entry.label : ""
                        color: panel.textLight
                        font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.fill: parent; color: "black"
                        opacity: card.dim
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
                // passepartout — crisp rounded outer + inner hole over the photo
                Shape {
                    id: frameShape
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real w:  panel.cardW
                    readonly property real h:  panel.cardH
                    readonly property real ro: 18
                    readonly property real m:  8
                    readonly property real ri: 10
                    ShapePath {
                        fillRule: ShapePath.OddEvenFill
                        fillColor: panel.frameDark
                        strokeColor: "transparent"
                        strokeWidth: 0
                        startX: frameShape.ro; startY: 0
                        PathLine { x: frameShape.w - frameShape.ro; y: 0 }
                        PathArc  { x: frameShape.w; y: frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.w; y: frameShape.h - frameShape.ro }
                        PathArc  { x: frameShape.w - frameShape.ro; y: frameShape.h; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.ro; y: frameShape.h }
                        PathArc  { x: 0; y: frameShape.h - frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: 0; y: frameShape.ro }
                        PathArc  { x: frameShape.ro; y: 0; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathMove { x: frameShape.m + frameShape.ri; y: frameShape.m }
                        PathLine { x: frameShape.w - frameShape.m - frameShape.ri; y: frameShape.m }
                        PathArc  { x: frameShape.w - frameShape.m; y: frameShape.m + frameShape.ri; radiusX: frameShape.ri; radiusY: frameShape.ri }
                        PathLine { x: frameShape.w - frameShape.m; y: frameShape.h - frameShape.m - frameShape.ri }
                        PathArc  { x: frameShape.w - frameShape.m - frameShape.ri; y: frameShape.h - frameShape.m; radiusX: frameShape.ri; radiusY: frameShape.ri }
                        PathLine { x: frameShape.m + frameShape.ri; y: frameShape.h - frameShape.m }
                        PathArc  { x: frameShape.m; y: frameShape.h - frameShape.m - frameShape.ri; radiusX: frameShape.ri; radiusY: frameShape.ri }
                        PathLine { x: frameShape.m; y: frameShape.m + frameShape.ri }
                        PathArc  { x: frameShape.m + frameShape.ri; y: frameShape.m; radiusX: frameShape.ri; radiusY: frameShape.ri }
                    }
                    // focus accent — OUTER outline only (one border, not two)
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: card.focused ? root.seal : "transparent"
                        strokeWidth: card.focused ? 2 : 0
                        Behavior on strokeColor { ColorAnimation { duration: 160 } }
                        startX: frameShape.ro; startY: 0
                        PathLine { x: frameShape.w - frameShape.ro; y: 0 }
                        PathArc  { x: frameShape.w; y: frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.w; y: frameShape.h - frameShape.ro }
                        PathArc  { x: frameShape.w - frameShape.ro; y: frameShape.h; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: frameShape.ro; y: frameShape.h }
                        PathArc  { x: 0; y: frameShape.h - frameShape.ro; radiusX: frameShape.ro; radiusY: frameShape.ro }
                        PathLine { x: 0; y: frameShape.ro }
                        PathArc  { x: frameShape.ro; y: 0; radiusX: frameShape.ro; radiusY: frameShape.ro }
                    }
                }
                // play glyph (videos) — on top, centred in the cut-out
                Text {
                    visible: panel.isVideos
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -12
                    text: ""   // play_arrow
                    font.family: "Material Symbols Rounded"; font.pixelSize: 46
                    color: Qt.rgba(1, 1, 1, 0.9)
                    style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: card.focused ? panel.openSelected() : (panel.selFilt = index)
                }
            }
        }
    }

    // ── label + delete-confirm + hint (bottom) ──
    Column {
        visible: panel.ready && panel.filtered.length > 0
        opacity: panel.reveal
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 28
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 820
            text: (panel.isVideos ? "Videos · " : "Screenshots · ") + panel.currentLabel
            color: panel.textLight
            font.family: root.mono; font.pixelSize: 24; font.weight: Font.DemiBold
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
            color: panel.textDim
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
