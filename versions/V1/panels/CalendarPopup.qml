import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: calPopup
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-calendar"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property real reveal: root.calendarVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.calendarVisible ? 160 : 120
            easing.type: root.calendarVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.calendarVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.calendarVisible = false
    }

    Rectangle {
        id: card
        width: 280
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: Math.round((parent.width - width) / 2)
        y: barBottom + gap
        opacity: calPopup.reveal
        focus: root.calendarVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.calendarVisible = false;
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ── header: month name ──
            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.centerIn: parent
                    text: root.calendarMonthName + "  " + root.calendarYear
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── weekday headers ──
            Row {
                width: parent.width
                Repeater {
                    model: ["MO","TU","WE","TH","FR","SA","SU"]
                    delegate: Item {
                        required property string modelData
                        required property int index
                        width: parent.width / 7
                        height: 20
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: index >= 5 ? root.seal : root.inkDeep
                            opacity: index >= 5 ? 0.85 : 0.7
                            font.family: root.mono
                            font.pixelSize: 10
                            font.letterSpacing: 2
                        }
                    }
                }
            }

            // ── day grid ──
            Grid {
                columns: 7
                rowSpacing: 2
                columnSpacing: 0
                width: parent.width
                Repeater {
                    model: root.calendarCells
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: parent.width / 7
                        height: 28

                        readonly property int dayOfWeek: index % 7
                        readonly property bool isCurrentMonth: modelData.day !== 0
                        readonly property bool isToday: modelData.today
                        readonly property bool isSelected: isCurrentMonth && root.selectedDay === modelData.day

                        readonly property color textColor: {
                            if (isToday) return root.seal.hsvValue < 0.5 ? root.ink : root.paper;
                            if (!isCurrentMonth) return root.inkDeep;
                            return dayOfWeek >= 5 ? root.seal : root.ink;
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 24; height: 24; radius: 12
                            color: root.seal
                            visible: isToday
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 24; height: 24; radius: 12
                            border.color: root.seal; border.width: 1
                            color: "transparent"
                            visible: isSelected && !isToday
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.day === 0 ? "" : modelData.day
                            color: textColor
                            opacity: isCurrentMonth ? 1.0 : 0.35
                            font.family: root.mono
                            font.pixelSize: 12
                            font.weight: isToday ? Font.Medium : Font.Light
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: isCurrentMonth
                            enabled: isCurrentMonth
                            cursorShape: isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.selectedDay = modelData.day
                        }
                    }
                }
            }
        }
    }
}
