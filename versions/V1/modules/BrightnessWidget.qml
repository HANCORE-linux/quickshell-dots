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

    implicitWidth:  hasBacklight ? (row.implicitWidth + 18) : 0
    implicitHeight: 28
    visible: hasBacklight
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
            text: "BRI"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 0.5
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(rootMod.percent).padStart(3) + "%"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            font.family: root.mono
            font.pixelSize: 12
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
        onEntered: { if (rootMod.hasBacklight) tipDelay.restart() }
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: { tipDelay.stop(); root.hideTooltip(rootMod); root.brightnessVisible = !root.brightnessVisible }
        onWheel: (e) => {
            if (e.angleDelta.y > 0) { briUp.running = false;   briUp.running = true }
            else                    { briDown.running = false; briDown.running = true }
            briProc.running = false; briProc.running = true
        }
    }
}
