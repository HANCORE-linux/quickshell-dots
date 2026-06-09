import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "ImagePickerModel.js" as Model

// Screenshot / video browser. Reuses the theme-picker card-deck look, but
// scans ~/Pictures (screenshots) or ~/Videos (recordings) and opens the
// selected file with xdg-open. Video posters are generated lazily per card.
PanelWindow {
    id: panel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-media-browser"
    WlrLayershell.keyboardFocus: panel.ready ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool isVideos: root.mediaBrowserMode === "videos"
    readonly property bool ready: root.mediaBrowserVisible && loaded && layoutSettled

    property bool loaded:        false
    property bool layoutSettled: false
    property var  imageArray:    []
    property int  selectedIndex: 0
    property string filterText:  ""

    visible: root.mediaBrowserVisible

    // ── Deal animation ──
    property real dealT: 0
    Behavior on dealT { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    onReadyChanged: if (ready) dealT = 1

    Connections {
        target: root
        function onMediaBrowserVisibleChanged() {
            if (root.mediaBrowserVisible) {
                panel.loaded        = false
                panel.layoutSettled = false
                panel.filterText    = ""
                panel.imageArray    = []
                panel.selectedIndex = 0
                panel.dealT         = 0
                scanProc.command    = panel.buildScanCmd()
                scanProc.running    = false; scanProc.running = true
            }
        }
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

    Process {
        id: scanProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var rows = Model.loadRows(String(text || ""))
                panel.imageArray    = rows
                panel.selectedIndex = 0
                panel.loaded        = rows.length > 0
                Qt.callLater(function() {
                    if (root.mediaBrowserVisible) {
                        panel.layoutSettled = true
                        hand.forceActiveFocus()
                    }
                })
            }
        }
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function openSelected() {
        if (!loaded || imageArray.length === 0) return
        var path = imageArray[selectedIndex].filePath; if (!path) return
        Quickshell.execDetached(["xdg-open", path])
        root.mediaBrowserVisible = false
    }

    function selectAdjacent(dir) {
        var count = imageArray.length; if (count === 0) return
        var idx = selectedIndex
        for (var i = 0; i < count; i++) {
            idx = (idx + dir + count) % count
            if (Model.itemMatches(imageArray, idx, filterText)) { selectedIndex = idx; return }
        }
    }

    // "screenshot-01-2025-10-28_19-54-26" → "2025-10-28 19:54"
    function mediaLabel(path) {
        var n = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
        var m = n.match(/(\d{4})-(\d{2})-(\d{2})[_-](\d{2})-(\d{2})-(\d{2})/)
        return m ? (m[1] + "-" + m[2] + "-" + m[3] + "  " + m[4] + ":" + m[5]) : n
    }
    function currentLabel() {
        if (imageArray.length === 0 || !Model.itemMatches(imageArray, selectedIndex, filterText)) return filterText ? "No matches" : ""
        return mediaLabel(imageArray[selectedIndex].filePath)
    }

    function filteredPos(idx)  { return Model.filteredPosition(imageArray, idx, filterText) }
    function selectedFiltPos() { return Model.selectedFilteredPosition(imageArray, selectedIndex, filterText) }
    function itemMatches(idx)  { return Model.itemMatches(imageArray, idx, filterText) }

    // ── Card hand geometry (matches the theme picker) ──
    readonly property int  cardW:      232
    readonly property int  cardH:      330
    readonly property real focusScale: 1.24
    readonly property real spreadDeg:  6.0
    readonly property real stepX:      128
    readonly property real focusLift:  54
    readonly property int  maxVisible: 5

    // ── Felt table + accents ──
    readonly property color feltColor:  Qt.rgba(0.035, 0.035, 0.05, 0.975)
    readonly property color frameDark:   "#16161c"
    readonly property color textLight:   "#ECECEE"
    readonly property color textDim:      Qt.rgba(0.92, 0.92, 0.94, 0.55)
    readonly property color accent:       root.seal

    // ── Felt scrim ──
    Rectangle {
        anchors.fill: parent
        color: panel.feltColor
        opacity: panel.ready ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: panel.ready
        onClicked: root.mediaBrowserVisible = false
        onWheel: function(wheel) {
            if (!panel.ready) return
            panel.selectAdjacent(wheel.angleDelta.y < 0 ? 1 : -1)
        }
    }

    // ── Loading / empty indicator ──
    Text {
        visible: root.mediaBrowserVisible && !panel.ready
        anchors.centerIn: parent
        text: panel.layoutSettled && !panel.loaded
              ? (panel.isVideos ? "No recordings in ~/Videos" : "No screenshots in ~/Pictures")
              : "Loading…"
        color: panel.textLight
        font.family: root.mono; font.pixelSize: 18
    }

    // ── A single media card ──
    component Card : Item {
        id: card
        property string src: ""        // screenshots: file://png
        property string filePath: ""   // videos: source path (for poster gen)
        property bool   isVideo: false
        property string title: ""
        property bool   focused: false
        property real   dim: 0.0
        property bool   active: false  // nearby → allowed to render/generate

        property string posterPath: ""

        Process {
            id: thumbProc
            running: false
            command: []
            stdout: StdioCollector {
                onStreamFinished: {
                    var p = this.text.trim()
                    if (p) card.posterPath = "file://" + p
                }
            }
        }
        function ensurePoster() {
            if (!isVideo || posterPath || !filePath || !active || !panel.ready) return
            thumbProc.command = ["bash", "-c",
                "d=$HOME/.cache/quickshell-media-thumbs; mkdir -p \"$d\"; " +
                "b=$(basename " + panel.shq(filePath) + "); o=\"$d/${b%.*}.jpg\"; " +
                "[ -f \"$o\" ] || ffmpegthumbnailer -i " + panel.shq(filePath) +
                " -o \"$o\" -s 480 -q 6 >/dev/null 2>&1; echo \"$o\""]
            thumbProc.running = false; thumbProc.running = true
        }
        onActiveChanged: ensurePoster()
        Component.onCompleted: ensurePoster()

        // frame
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: panel.frameDark
            border.width: card.focused ? 2 : 1
            border.color: card.focused ? panel.accent : Qt.rgba(1, 1, 1, 0.10)
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        // rounded image (screenshot thumbnail or video poster)
        Item {
            anchors.fill: parent
            anchors.margins: 7
            layer.enabled: true; layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true; maskSource: cardMask
                maskThresholdMin: 0.5; maskSpreadAtMin: 0.4
            }
            Image {
                anchors.fill: parent
                source: card.isVideo ? card.posterPath : (panel.ready && card.src ? card.src : "")
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
                sourceSize.width:  panel.cardW * 2
                sourceSize.height: panel.cardH * 2
            }
            // bottom gradient + date label
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 64
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.74) }
                }
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 9 }
                text: card.title
                color: panel.textLight
                font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            }
        }
        // play glyph overlay for videos
        Text {
            visible: card.isVideo
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -10
            text: ""   // play_arrow
            font.family: "Material Symbols Rounded"; font.pixelSize: 52
            color: Qt.rgba(1, 1, 1, 0.88)
            style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
        }
        // dim overlay (cheap, outside the layer)
        Rectangle {
            anchors.fill: parent; anchors.margins: 7
            radius: 12; color: "black"
            opacity: card.dim
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        Item {
            id: cardMask; anchors.fill: parent; anchors.margins: 7
            visible: false; layer.enabled: true
            Rectangle { anchors.fill: parent; radius: 12; color: "white" }
        }
    }

    // ── The hand ──
    Item {
        id: hand
        visible: panel.ready && panel.imageArray.length > 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -16
        width: parent.width
        height: panel.cardH + panel.focusLift + 40
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (panel.filterText) panel.filterText = ""
                else root.mediaBrowserVisible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.openSelected(); event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                if (panel.filterText.length > 0) { panel.filterText = panel.filterText.slice(0, -1); event.accepted = true }
            } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab) {
                panel.selectAdjacent(-1); event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
                panel.selectAdjacent(1); event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                       && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                panel.filterText += event.text; event.accepted = true
            }
        }

        Repeater {
            model: panel.imageArray.length

            delegate: Card {
                id: cardItem
                required property int index

                readonly property bool matched:   panel.itemMatches(index)
                readonly property int  relIdx:    panel.filteredPos(index) - panel.selectedFiltPos()
                readonly property bool isFocused: matched && index === panel.selectedIndex
                readonly property bool nearby:    matched && Math.abs(relIdx) <= panel.maxVisible
                property bool srcReady: nearby
                onNearbyChanged: if (nearby) srcReady = true

                isVideo: panel.isVideos
                filePath: panel.imageArray[index] ? panel.imageArray[index].filePath : ""
                src:     (!panel.isVideos && srcReady && panel.imageArray[index]) ? ("file://" + panel.imageArray[index].thumbnailPath) : ""
                title:   panel.imageArray[index] ? panel.mediaLabel(panel.imageArray[index].filePath) : ""
                active:  srcReady
                focused: isFocused
                dim:     isFocused ? 0.0 : Math.min(0.62, 0.30 + Math.abs(relIdx) * 0.05)

                width: panel.cardW; height: panel.cardH
                visible: nearby
                transformOrigin: Item.Bottom

                x: (hand.width  - panel.cardW) / 2 + relIdx * panel.stepX * panel.dealT
                y: (hand.height - panel.cardH)     - (isFocused ? panel.focusLift * panel.dealT : 0)
                rotation: relIdx * panel.spreadDeg * panel.dealT
                scale: isFocused ? 1 + (panel.focusScale - 1) * panel.dealT : 1
                z: isFocused ? 1000 : 500 - Math.min(Math.abs(relIdx), 40)
                opacity: panel.dealT

                Behavior on x        { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on y        { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on rotation { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on scale    { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: cardItem.isFocused ? panel.openSelected() : (panel.selectedIndex = index)
                }
            }
        }
    }

    // ── Label + hint ──
    Column {
        visible: panel.ready
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 30
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 768; text: (panel.isVideos ? "Videos · " : "Screenshots · ") + panel.currentLabel()
            color: panel.textLight
            font.family: root.mono; font.pixelSize: 22; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Text {
            visible: panel.filterText.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: 768; text: panel.filterText
            color: panel.accent; opacity: 0.95
            font.family: root.mono; font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← → scroll navigate   Enter open   Esc cancel   type to filter"
            color: panel.textDim
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
