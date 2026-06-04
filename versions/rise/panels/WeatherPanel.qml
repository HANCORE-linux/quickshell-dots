import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: wxPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-weather"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property string temp: ""
    property string feels: ""
    property string desc: ""
    property string location: ""
    property string humidity: ""
    property string wind: ""
    property bool   refreshing: false

    function refresh() { refreshing = true; wxData.running = false; wxData.running = true }

    property real reveal: root.weatherVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.weatherVisible ? 160 : 120
            easing.type: root.weatherVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.weatherVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.weatherVisible = false }

    Rectangle {
        id: card
        width: 300
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: Math.round((parent.width - width) / 2)
        y: barBottom + gap
        opacity: wxPanel.reveal
        focus: root.weatherVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.weatherVisible = false; event.accepted = true }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Weather"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: root.sumi; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.weatherVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Item {
                width: parent.width
                height: 36
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: wxPanel.temp !== "" ? wxPanel.temp + "°" : "—"
                    color: root.seal; font.family: root.mono; font.pixelSize: 26; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: wxPanel.desc
                    color: root.ink; font.family: root.mono; font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                    width: parent.width * 0.55; wrapMode: Text.WordWrap
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Row {
                    width: parent.width
                    visible: wxPanel.location !== ""
                    Text { text: "Location"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: wxPanel.location; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.6; elide: Text.ElideRight }
                }
                Row {
                    width: parent.width
                    visible: wxPanel.feels !== ""
                    Text { text: "Feels like"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: wxPanel.feels + "°"; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: wxPanel.humidity !== ""
                    Text { text: "Humidity"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: wxPanel.humidity + "%"; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: wxPanel.wind !== ""
                    Text { text: "Wind"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: wxPanel.wind + " km/h"; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: wxPanel.refreshing ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.45) : root.seal
                Text {
                    anchors.centerIn: parent
                    text: wxPanel.refreshing ? "Refreshing…" : "Refresh"
                    color: root.paper; font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    enabled: !wxPanel.refreshing
                    onClicked: wxPanel.refresh()
                }
            }
        }
    }

    Process {
        id: wxData
        command: ["bash", "-c",
            "curl -s --max-time 5 'wttr.in/?format=j1' 2>/dev/null | " +
            "jq -r '[.current_condition[0].temp_C, .current_condition[0].FeelsLikeC, " +
            ".current_condition[0].weatherDesc[0].value, .current_condition[0].humidity, " +
            ".current_condition[0].windspeedKmph, (.nearest_area[0].areaName[0].value)] | @tsv' 2>/dev/null"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim().split("\t")
                if (p.length >= 6) {
                    wxPanel.temp = p[0]; wxPanel.feels = p[1]; wxPanel.desc = p[2]
                    wxPanel.humidity = p[3]; wxPanel.wind = p[4]; wxPanel.location = p[5]
                }
            }
        }
        onExited: wxPanel.refreshing = false
    }

    onVisibleChanged: { if (visible && wxPanel.temp === "") wxPanel.refresh() }
}
