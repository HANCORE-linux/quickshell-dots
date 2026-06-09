import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property bool   hasBacklight: false
    property int    percent:      0
    property string blDevice:     ""

    readonly property string tooltipText: "Brightness · " + percent + "%"

    readonly property bool shown: hasBacklight && root.modBrightness
    implicitWidth:  shown ? (row.implicitWidth + 18) : 0
    implicitHeight: 28
    visible: implicitWidth > 0.5
    clip: true
    opacity: shown ? 1 : 0

    Behavior on implicitWidth {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

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
            text: "BRI"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        // drawn sun — core + rays that grow/brighten with the level
        Item {
            id: sun
            width: 13
            height: 13
            anchors.verticalCenter: parent.verticalCenter

            readonly property real ratio: Math.max(0, Math.min(1, rootMod.percent / 100))
            // turns theme-red at full brightness, like the battery's full state
            readonly property color sunColor: rootMod.percent >= 100
                ? root.seal
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)

            Rectangle {
                anchors.centerIn: parent
                width: 6.5
                height: 6.5
                radius: 3.25
                color: sun.sunColor
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            Repeater {
                model: 8
                delegate: Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 45
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 0.3
                        width: 1.5
                        height: 2 + 1.4 * sun.ratio
                        radius: 0.75
                        color: sun.sunColor
                        opacity: 0.35 + 0.65 * sun.ratio
                        Behavior on height  { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        Behavior on color   { ColorAnimation  { duration: 200 } }
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.percent + "%"
            color: rootMod.percent >= 100
                ? root.seal
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // detect backlight on startup
    Process {
        id: detectProc
        command: ["bash", "-c", "BL=$(ls /sys/class/backlight/ 2>/dev/null | head -1); [ -n \"$BL\" ] && echo \"$BL\" || echo NONE"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var bl = this.text.trim()
                if (bl !== "NONE" && bl !== "") {
                    rootMod.blDevice = bl
                    rootMod.hasBacklight = true
                    root.hasBacklight = true
                }
            }
        }
    }

    Process {
        id: briProc
        command: ["bash", "-c",
            "BL=$(ls /sys/class/backlight/ 2>/dev/null | head -1); " +
            "[ -z \"$BL\" ] && exit; " +
            "CUR=$(cat /sys/class/backlight/$BL/brightness 2>/dev/null || echo 0); " +
            "MAX=$(cat /sys/class/backlight/$BL/max_brightness 2>/dev/null || echo 100); " +
            "echo $((MAX > 0 ? CUR * 100 / MAX : 0))"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim())
                if (!isNaN(v)) rootMod.percent = Math.max(0, Math.min(100, v))
            }
        }
    }

    Timer {
        interval: 3000; running: rootMod.hasBacklight; repeat: true; triggeredOnStart: true
        onTriggered: { briProc.running = false; briProc.running = true }
    }

    Process { id: briUp;   command: ["bash", "-c", "brightnessctl set +5% -q"] }
    Process { id: briDown; command: ["bash", "-c", "brightnessctl set 5%- -q"] }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: { if (rootMod.hasBacklight) tip.show() }
        onExited:  { tip.hide() }
        onClicked: { tip.hide(); root.brightnessVisible = !root.brightnessVisible }
        onWheel: (e) => {
            if (e.angleDelta.y > 0) { briUp.running = false;   briUp.running = true }
            else                    { briDown.running = false; briDown.running = true }
            briProc.running = false; briProc.running = true
        }
    }
}
