import Quickshell.Hyprland
import QtQuick

Item {
    id: wsWidget
    required property var root

    implicitWidth: wsRow.implicitWidth
    implicitHeight: 28
    readonly property color contentColor: root.widgetContentColor("G2", root.seal)

    // The focused workspace's id ONLY when it's a real (positive) workspace beyond
    // the persist range — else 0. An int signals on value change only, so switching
    // between in-range workspaces does NOT renotify → workspaceList stays identical
    // → the Repeater model is stable → the per-delegate width/colour Behaviors keep
    // animating instead of the whole model rebuilding (B2). `id > n` (n≥5) also
    // excludes negative special/scratchpad ids (B3).
    readonly property int extraWs: {
        if (root.workspaceMode === "active") return 0
        var n = root.workspaceMode === "5" ? 5 : 10
        var f = Hyprland.focusedWorkspace
        return (f && f.id > n) ? f.id : 0
    }

    readonly property var workspaceList: {
        if (root.workspaceMode === "active") {
            var ids = {}
            var ws = Hyprland.workspaces.values
            for (var i = 0; i < ws.length; i++) if (ws[i].id > 0) ids[ws[i].id] = true   // F13: skip special (negative-id) workspaces
            if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0) ids[Hyprland.focusedWorkspace.id] = true
            return Object.keys(ids).map(Number).sort(function(a, b) { return a - b })
        }
        var n = root.workspaceMode === "5" ? 5 : 10
        var list = []; for (var j = 1; j <= n; j++) list.push(j)
        if (extraWs > 0) list.push(extraWs)   // focused-beyond-range, stable per id
        return list
    }

    // right-click anywhere opens the workspace panel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.workspaceVisible = !root.workspaceVisible
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: root.workspaceStyle === "rings" || root.workspaceStyle === "aurora" ? 3 : 5

        Repeater {
            model: wsWidget.workspaceList

            delegate: Item {
                id: wsCell
                required property int modelData
                readonly property int wsId: modelData

                // hover feedback works in every style (the old code scaled the
                // default-only `dot`, invisible in numbers/magic)
                Behavior on scale { NumberAnimation { duration: 120 } }

                readonly property bool isFocused: Hyprland.focusedWorkspace !== null
                                               && Hyprland.focusedWorkspace.id === wsId

                readonly property bool isOccupied: {
                    var ws = Hyprland.workspaces.values
                    for (var i = 0; i < ws.length; i++)
                        if (ws[i].id === wsId) return !isFocused
                    return false
                }

                readonly property bool isEmpty: !isFocused && !isOccupied

                implicitWidth: root.workspaceStyle === "numbers" ? 22
                             : root.workspaceStyle === "kanji"   ? 22
                             : root.workspaceStyle === "magic"   ? (isFocused ? 20 : 18)
                             : root.workspaceStyle === "rings"   ? 19
                             : root.workspaceStyle === "aurora"  ? (isFocused ? 38 : 20)
                             : (isFocused ? 32 : 16)
                implicitHeight: 28

                Behavior on implicitWidth {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // ── DEFAULT style: glow + dot ──
                // glow — alle states, nur opacity variiert
                Rectangle {
                    visible: root.workspaceStyle === "default"
                    anchors.centerIn: parent
                    width:  isFocused ? 34 : 16
                    height: isFocused ? 16 : 16
                    radius: isFocused ?  8 :  8
                    color: isFocused
                        ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.20)
                        : isOccupied
                        ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.18)
                        : Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.06)

                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // pill / kreis
                Rectangle {
                    id: dot
                    visible: root.workspaceStyle === "default"
                    anchors.centerIn: parent
                    width:  isFocused  ? 26 : 8
                    height: 8
                    radius: 4
                    color:  isFocused
                        ? wsWidget.contentColor
                        : isOccupied
                        ? wsWidget.contentColor
                        : Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.25)

                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // ── NUMBERS style: a digit on the shared 6px V2 button shape. ──
                Rectangle {
                    visible: root.workspaceStyle === "numbers"
                    anchors.centerIn: parent
                    width:  20
                    height: 20
                    radius: root.panelButtonRadius
                    color: isFocused  ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.30)
                         : isOccupied ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.12)
                                      : Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.04)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text {
                        anchors.centerIn: parent
                        text: wsId
                        // focused = the only BRIGHT digit (lightened seal + bold + bigger);
                        // others dimmed so the active workspace is unmistakable
                        color: isFocused  ? wsWidget.contentColor
                             : isOccupied ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.5)
                                          : Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.28)
                        font.family: root.mono
                        font.pixelSize: isFocused ? 13 : 12
                        font.weight: isFocused ? Font.Bold : Font.Normal
                    }
                }

                // ── MAGIC style: the 3 ORIGINAL sparkle glyphs (filled / hollow / dot),
                //    all forced into ONE font (Adwaita Mono has all three) so they share
                //    a metric → no cross-font fallback misalignment ──
                Text {
                    visible: root.workspaceStyle === "magic"
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: isFocused ? 0 : 1   // active lifted vs occupied/empty
                    text: isFocused  ? String.fromCodePoint(0x2726)    // ✦ filled four-point star (active)
                         : isOccupied ? String.fromCodePoint(0x2727)    // ✧ hollow four-point star (occupied)
                                      : String.fromCodePoint(0x00B7)    // · middle dot (empty)
                    color: isFocused  ? wsWidget.contentColor
                         : isOccupied ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.7)
                                      : Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.3)
                    font.family: "Adwaita Mono"   // all 3 sparkle glyphs live here → one consistent metric
                    font.pixelSize: isFocused ? 22 : 18
                    renderType: Text.NativeRendering   // crisp hinted raster (default QtRendering softens small symbols)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // ── KANJI style: 一–十 numerals (waybar V7.2a format-icons), same
                //    focused/occupied/empty treatment as the other styles; ids >10
                //    fall back to the Arabic number ──
                Text {
                    visible: root.workspaceStyle === "kanji"
                    anchors.centerIn: parent
                    text: wsId >= 1 && wsId <= 10
                        ? ["一","二","三","四","五","六","七","八","九","十"][wsId - 1]
                        : String(wsId)
                    color: isFocused  ? wsWidget.contentColor
                         : isOccupied ? Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.7)
                                      : Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g, wsWidget.contentColor.b, 0.3)
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: isFocused ? 15 : 13
                    font.weight: Font.Normal
                    renderType: Text.NativeRendering
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // ── RINGS style: Waybar V1.3's active filled circle and dimmed
                //    hollow inactive circles. CSS opacity is preserved per state. ──
                Rectangle {
                    id: ringsMark
                    visible: root.workspaceStyle === "rings"
                    anchors.centerIn: parent
                    width: isFocused ? 13 : 12
                    height: width
                    radius: width / 2
                    color: isFocused ? wsWidget.contentColor : "transparent"
                    border.width: isFocused ? 0 : 1
                    border.color: wsWidget.contentColor
                    opacity: wsMa.containsMouse ? 0.4
                        : isFocused ? 1.0
                        : isOccupied ? 0.45
                        : 0.10
                    antialiasing: true

                    Behavior on width {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 300; easing.type: Easing.InOutCubic }
                    }
                }

                // ── AURORA style: V3.1c's full-height round buttons and strongly
                //    expanded active workspace, intentionally rendered in one
                //    theme-aware color instead of the source gradient. ──
                Rectangle {
                    id: auroraMark
                    visible: root.workspaceStyle === "aurora"
                    anchors.centerIn: parent
                    width: isFocused ? 36 : 18
                    height: 16
                    radius: 8
                    antialiasing: true
                    color: Qt.rgba(wsWidget.contentColor.r, wsWidget.contentColor.g,
                        wsWidget.contentColor.b,
                        isEmpty ? (wsMa.containsMouse ? 0.25 : 0.10)
                                : (wsMa.containsMouse ? 0.55 : 1.0))

                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                MouseArea {
                    id: wsMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.gotoWorkspace(wsId)
                    onEntered: wsCell.scale = root.workspaceStyle === "rings" ? 1.06
                        : root.workspaceStyle === "aurora" ? 1.03 : 1.15
                    onExited:  wsCell.scale = 1.0
                }
            }
        }
    }

}
