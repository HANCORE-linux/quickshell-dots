import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
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
                        carousel.forceActiveFocus()
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

    // ── Carousel geometry ──
    readonly property int expandedW: 768
    readonly property int expandedH: 432
    readonly property int sliceW:    108
    readonly property int sliceH:    390
    readonly property int sliceGap:  -30
    readonly property int skew:       28

    // ── Colors ──
    readonly property color scrimColor:       Qt.rgba(0, 0, 0, 0.68)
    readonly property color selBorder:        root.seal
    readonly property color unselBorder:      Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22)
    readonly property color dimColor:         root.paper

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: panel.scrimColor
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
        color: Qt.rgba(1, 1, 1, 0.5)
        font.family: root.mono; font.pixelSize: 18
    }

    // ── Carousel ──
    Item {
        id: carousel
        visible: panel.ready && panel.imageArray.length > 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40
        width: panel.expandedW + 13 * (panel.sliceW + panel.sliceGap)
        height: panel.expandedH
        focus: true

        readonly property real itemStep: panel.sliceW + panel.sliceGap
        readonly property real previewX: (width - panel.expandedW) / 2

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

            delegate: Item {
                id: slice
                required property int index

                readonly property var  imgData:    panel.imageArray[index]
                readonly property bool matched:    panel.itemMatches(index)
                readonly property int  relIdx:     panel.filteredPos(index) - panel.selectedFiltPos()
                readonly property bool selected:   matched && index === panel.selectedIndex
                readonly property bool nearby:     matched && Math.abs(relIdx) <= 14
                property bool srcActivated: nearby
                onNearbyChanged: if (nearby) srcActivated = true

                visible: nearby
                x: selected ? carousel.previewX
                             : (relIdx < 0 ? carousel.previewX + relIdx * carousel.itemStep
                                           : carousel.previewX + panel.expandedW + panel.sliceGap + (relIdx - 1) * carousel.itemStep)
                y: selected ? 0 : (panel.expandedH - panel.sliceH) / 2
                width:  selected ? panel.expandedW : panel.sliceW
                height: selected ? panel.expandedH : panel.sliceH
                z: selected ? 100 : 50 - Math.min(Math.abs(relIdx), 40)

                Behavior on x     { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on y     { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                readonly property real skAbs:    Math.abs(panel.skew)
                readonly property real topLeft:  panel.skew >= 0 ? skAbs : 0
                readonly property real topRight: panel.skew >= 0 ? width : width - skAbs
                readonly property real botRight: panel.skew >= 0 ? width - skAbs : width
                readonly property real botLeft:  panel.skew >= 0 ? 0 : skAbs

                Item {
                    id: maskShape; anchors.fill: parent
                    visible: false; layer.enabled: true
                    Shape {
                        anchors.fill: parent; antialiasing: true
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "white"; strokeColor: "transparent"
                            startX: slice.topLeft; startY: 0
                            PathLine { x: slice.topRight; y: 0 }
                            PathLine { x: slice.botRight; y: slice.height }
                            PathLine { x: slice.botLeft;  y: slice.height }
                            PathLine { x: slice.topLeft;  y: 0 }
                        }
                    }
                }

                Item {
                    anchors.fill: parent; layer.enabled: true; layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true; maskSource: maskShape
                        maskThresholdMin: 0.3; maskSpreadAtMin: 0.3
                    }
                    Image {
                        anchors.fill: parent
                        source: slice.srcActivated && slice.imgData ? ("file://" + slice.imgData.thumbnailPath) : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; smooth: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(panel.dimColor.r, panel.dimColor.g, panel.dimColor.b, slice.selected ? 0 : 0.42)
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                Shape {
                    anchors.fill: parent; antialiasing: true
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: slice.selected ? panel.selBorder : panel.unselBorder
                        strokeWidth: slice.selected ? 3 : 1
                        Behavior on strokeColor { ColorAnimation { duration: 150 } }
                        startX: slice.topLeft; startY: 0
                        PathLine { x: slice.topRight; y: 0 }
                        PathLine { x: slice.botRight; y: slice.height }
                        PathLine { x: slice.botLeft;  y: slice.height }
                        PathLine { x: slice.topLeft;  y: 0 }
                    }
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: slice.selected ? panel.applySelected() : (panel.selectedIndex = index)
                }
            }
        }
    }

    // ── Label + hint ──
    Column {
        visible: panel.ready
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 32
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: panel.expandedW; text: panel.currentLabel()
            color: root.ink
            style: Text.Outline
            styleColor: Qt.rgba(panel.dimColor.r, panel.dimColor.g, panel.dimColor.b, 0.7)
            font.family: root.mono; font.pixelSize: 30; font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Text {
            visible: panel.filterText.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: panel.expandedW; text: panel.filterText
            color: root.ink; opacity: 0.75
            style: Text.Outline
            styleColor: Qt.rgba(panel.dimColor.r, panel.dimColor.g, panel.dimColor.b, 0.7)
            font.family: root.mono; font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← → navigate   Enter apply   Esc cancel   type to filter"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
            font.family: root.mono; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
