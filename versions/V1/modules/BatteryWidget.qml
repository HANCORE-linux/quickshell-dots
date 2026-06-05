import QtQuick
import Quickshell
import Quickshell.Services.UPower

Item {
    id: rootMod
    required property var root

    // event-driven UPower data — updates instantly on plug / unplug
    readonly property var dev: UPower.displayDevice
    readonly property bool hasBattery: dev !== null && dev.isLaptopBattery
    readonly property int percent: {
        if (!dev) return 0
        var p = dev.percentage
        // robust to either 0..1 or 0..100 reporting
        return Math.round(p <= 1.0 ? p * 100 : p)
    }
    readonly property int devState: dev ? dev.state : UPowerDeviceState.Unknown
    readonly property bool charging: devState === UPowerDeviceState.Charging
    readonly property bool full:     devState === UPowerDeviceState.FullyCharged
    readonly property bool low:      !charging && !full && percent <= 20

    readonly property string statusText:
        full ? "Full"
        : charging ? "Charging"
        : devState === UPowerDeviceState.Discharging ? "Discharging"
        : "On battery"
    readonly property string tooltipText: statusText + " · " + percent + "%"

    // colour shared by the drawn battery body, fill and nub
    readonly property color battColor:
        full ? root.inkDeep
        : charging ? root.indigo
        : (low ? root.seal
        : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7))

    implicitWidth:  hasBattery ? (row.implicitWidth + 18) : 0
    implicitHeight: 28
    visible: hasBattery
    clip: true

    Behavior on implicitWidth {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.centerIn: row
        width: row.width + 18
        height: 24
        radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "BAT"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        // drawn landscape battery — body + stepless fill + terminal nub
        Item {
            id: batt
            width: 19
            height: 10
            anchors.verticalCenter: parent.verticalCenter

            readonly property real ratio: Math.max(0, Math.min(1, rootMod.percent / 100))

            Rectangle {
                id: body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 9
                radius: 2.5
                color: "transparent"
                border.width: 1.2
                border.color: rootMod.battColor
                Behavior on border.color { ColorAnimation { duration: 200 } }

                // faint indigo wash so a charging cell reads "active" at any level
                Rectangle {
                    visible: rootMod.charging
                    anchors.fill: parent
                    anchors.margins: 1.8
                    radius: 1.2
                    color: Qt.rgba(root.indigo.r, root.indigo.g, root.indigo.b, 0.28)
                }

                Rectangle {
                    id: fill
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1.8
                    width: Math.max(batt.ratio > 0 ? 1.5 : 0, (parent.width - 3.6) * batt.ratio)
                    radius: 1.2
                    clip: true
                    color: rootMod.battColor
                    Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 200 } }

                    // font-free charging shimmer that sweeps across the fill
                    Rectangle {
                        visible: rootMod.charging && !rootMod.full
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 6
                        radius: parent.radius
                        color: Qt.rgba(1, 1, 1, 0.18)
                        property real pos: 0
                        x: (parent.width + width) * pos - width
                        SequentialAnimation on pos {
                            running: rootMod.charging && !rootMod.full
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: 500 }
                        }
                    }
                }

                // charging bolt overlay — clear "is charging" cue
                Canvas {
                    id: bolt
                    visible: rootMod.charging && !rootMod.full
                    anchors.centerIn: parent
                    width: 6
                    height: 8
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.beginPath()
                        ctx.moveTo(width * 0.55, 0)
                        ctx.lineTo(width * 0.12, height * 0.55)
                        ctx.lineTo(width * 0.45, height * 0.55)
                        ctx.lineTo(width * 0.38, height)
                        ctx.lineTo(width * 0.88, height * 0.45)
                        ctx.lineTo(width * 0.55, height * 0.45)
                        ctx.closePath()
                        ctx.fillStyle = root.paper.toString()
                        ctx.fill()
                    }
                    Component.onCompleted: requestPaint()
                    Connections {
                        target: root
                        function onPaperChanged() { bolt.requestPaint() }
                    }
                }
            }

            // terminal nub (positive pole)
            Rectangle {
                anchors.left: body.right
                anchors.leftMargin: -0.5
                anchors.verticalCenter: parent.verticalCenter
                width: 2.5
                height: 5
                radius: 1.2
                color: rootMod.battColor
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.percent + "%"
            color: {
                if (rootMod.charging || rootMod.full) return rootMod.battColor
                if (rootMod.low) return root.seal
                return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            }
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: { if (rootMod.hasBattery) tipDelay.restart() }
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: { tipDelay.stop(); root.hideTooltip(rootMod); root.batteryVisible = !root.batteryVisible }
    }
}
