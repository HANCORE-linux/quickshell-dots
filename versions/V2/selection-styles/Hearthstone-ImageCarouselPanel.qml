import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "ImagePickerModel.js" as Model

PanelWindow {
    id: panel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-image-carousel"
    WlrLayershell.keyboardFocus: panel.ready ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property bool isThemeMode: root.imagePickerMode === "theme"
    readonly property bool ready: root.imagePickerVisible && imagesLoaded && layoutSettled

    property bool imagesLoaded:  false
    property bool layoutSettled: false
    property var  imageArray:    []
    property int  selectedIndex: 0
    property string filterText:  ""
    property string currentImage: ""

    visible: root.imagePickerVisible

    // ── Deal animation ──
    //  dealT 0 = cards stacked at centre   ·   dealT 1 = fanned out into a hand
    property real dealT: 0
    Behavior on dealT { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
    onReadyChanged: if (ready) dealT = 1

    // watch for open request
    Connections {
        target: root
        function onImagePickerVisibleChanged() {
            if (root.imagePickerVisible) {
                panel.imagesLoaded  = false
                panel.layoutSettled = false
                panel.filterText    = ""
                panel.imageArray    = []
                panel.selectedIndex = 0
                panel.dealT         = 0
                currentProc.running = false; currentProc.running = true
            }
        }
    }

    // step 1: get current image
    Process {
        id: currentProc
        command: panel.isThemeMode
            ? ["bash", "-c",
               "CACHE=$HOME/.cache/quickshell-theme-picker; " +
               "name=$(cat ~/.config/omarchy/current/theme.name 2>/dev/null || true); " +
               "for ext in png jpg jpeg webp; do f=\"$CACHE/$name.$ext\"; [ -L \"$f\" ] && echo \"$f\" && exit 0; done; echo ''"]
            : ["bash", "-c", "readlink -f ~/.config/omarchy/current/background 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                panel.currentImage = this.text.trim()
                scanProc.command = panel.buildScanCmd()
                scanProc.running = false; scanProc.running = true
            }
        }
    }

    // step 2: scan images
    Process {
        id: scanProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var images = Model.loadRows(String(text || ""))
                panel.imageArray    = images
                panel.selectedIndex = Model.indexForSelectedImage(images, panel.currentImage)
                panel.imagesLoaded  = images.length > 0
                Qt.callLater(function() {
                    if (root.imagePickerVisible) {
                        panel.layoutSettled = true
                        hand.forceActiveFocus()
                    }
                })
            }
        }
    }

    function buildScanCmd() {
        if (isThemeMode) {
            return ["bash", "-c", [
                "CACHE=$HOME/.cache/quickshell-theme-picker; mkdir -p \"$CACHE\";",
                "for d in ~/.local/share/omarchy/themes/* ~/.config/omarchy/themes/*; do",
                "  [ -d \"$d\" ] || continue;",
                "  name=$(basename \"$d\");",
                "  prev=$(find -L \"$d\" -maxdepth 1 \\( -iname 'preview.png' -o -iname 'preview.jpg' -o -iname 'preview.jpeg' \\) 2>/dev/null | head -1);",
                "  [ -z \"$prev\" ] && prev=$(find -L \"$d/backgrounds\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null | sort | head -1);",
                "  [ -z \"$prev\" ] && continue;",
                "  ext=\"${prev##*.}\"; link=\"$CACHE/$name.$ext\";",
                "  [ -L \"$link\" ] || ln -sf \"$prev\" \"$link\";",
                "  printf '%s\\t%s\\n' \"$link\" \"$prev\";",
                "done | sort -u"
            ].join(" ")]
        } else {
            return ["bash", "-c",
                "find -L ~/.config/omarchy/current/theme/backgrounds -maxdepth 1 -type f " +
                "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) " +
                "2>/dev/null | sort | while read f; do printf '%s\\t%s\\n' \"$f\" \"$f\"; done"
            ]
        }
    }

    Process { id: applyThemeProc; command: [] }
    Process { id: applyBgProc;    command: [] }

    function applySelected() {
        if (!imagesLoaded || imageArray.length === 0) return
        var path = imageArray[selectedIndex].filePath; if (!path) return
        if (isThemeMode) {
            var name = Model.nameForPath(path)
            applyThemeProc.command = ["bash", "-c", "omarchy-theme-set '" + name.replace(/'/g, "'\\''") + "'"]
            applyThemeProc.running = false; applyThemeProc.running = true
        } else {
            applyBgProc.command = ["bash", "-c", "omarchy-theme-bg-set '" + path.replace(/'/g, "'\\''") + "'"]
            applyBgProc.running = false; applyBgProc.running = true
        }
        root.imagePickerVisible = false
    }

    function selectAdjacent(dir) {
        var count = imageArray.length; if (count === 0) return
        var idx = selectedIndex
        for (var i = 0; i < count; i++) {
            idx = (idx + dir + count) % count
            if (Model.itemMatches(imageArray, idx, filterText)) { selectedIndex = idx; return }
        }
    }

    function currentLabel() {
        if (imageArray.length === 0 || !Model.itemMatches(imageArray, selectedIndex, filterText)) return filterText ? "No matches" : ""
        return Model.labelForPath(imageArray[selectedIndex].filePath)
    }

    function filteredPos(idx)  { return Model.filteredPosition(imageArray, idx, filterText) }
    function selectedFiltPos() { return Model.selectedFilteredPosition(imageArray, selectedIndex, filterText) }
    function itemMatches(idx)  { return Model.itemMatches(imageArray, idx, filterText) }
    function labelFor(idx)     { return Model.labelForPath(imageArray[idx].filePath) }

    // ── Card hand geometry ──
    readonly property int  cardW:      232
    readonly property int  cardH:      330
    readonly property real focusScale: 1.24
    readonly property real spreadDeg:  6.0   // fan rotation per card
    readonly property real stepX:      128   // horizontal slide per card (overlap)
    readonly property real focusLift:  54    // how far the focused card rises
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
        onClicked: root.imagePickerVisible = false
        onWheel: function(wheel) {
            if (!panel.ready) return
            panel.selectAdjacent(wheel.angleDelta.y < 0 ? 1 : -1)
        }
    }

    // ── Loading indicator ──
    Text {
        visible: root.imagePickerVisible && !panel.ready
        anchors.centerIn: parent
        text: "Loading…"
        color: panel.textLight
        font.family: root.mono; font.pixelSize: 18
    }

    // ── A single theme card ──
    component Card : Item {
        id: card
        property string src: ""
        property string title: ""
        property bool   focused: false
        property real   dim: 0.0

        // frame
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: panel.frameDark
            border.width: card.focused ? 2 : 1
            border.color: card.focused ? panel.accent : Qt.rgba(1, 1, 1, 0.10)
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        // rounded image inset inside the frame — static content, rasterised once
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
                source: panel.ready && card.src ? card.src : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
                // cap decode resolution so big wallpapers don't choke the deal animation
                sourceSize.width:  panel.cardW * 2
                sourceSize.height: panel.cardH * 2
            }
            // bottom gradient so the title is always legible
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 70
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                }
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                text: card.title
                color: panel.textLight
                font.family: root.mono; font.pixelSize: 13; font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            }
        }
        // dim overlay — cheap rounded rect outside the layer, animates opacity only
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
                else root.imagePickerVisible = false
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.applySelected(); event.accepted = true
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

                readonly property bool matched:  panel.itemMatches(index)
                readonly property int  relIdx:   panel.filteredPos(index) - panel.selectedFiltPos()
                readonly property bool isFocused: matched && index === panel.selectedIndex
                readonly property bool nearby:   matched && Math.abs(relIdx) <= panel.maxVisible
                property bool srcReady: nearby
                onNearbyChanged: if (nearby) srcReady = true

                src:     srcReady && panel.imageArray[index] ? ("file://" + panel.imageArray[index].thumbnailPath) : ""
                title:   panel.imageArray[index] ? panel.labelFor(index) : ""
                focused: isFocused
                dim:     isFocused ? 0.0 : Math.min(0.62, 0.30 + Math.abs(relIdx) * 0.05)

                width: panel.cardW; height: panel.cardH
                visible: nearby
                transformOrigin: Item.Bottom

                // bottoms sit on a line; tops fan out by rotation; focused card rises
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
                    onClicked: cardItem.isFocused ? panel.applySelected() : (panel.selectedIndex = index)
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
            width: 768; text: panel.currentLabel()
            color: panel.textLight
            font.family: root.mono; font.pixelSize: 28; font.weight: Font.DemiBold
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
            text: "← → scroll navigate   Enter apply   Esc cancel   type to filter"
            color: panel.textDim
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
