import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property date now: new Date()

    function pad(n) { return n < 10 ? "0" + n : String(n) }

    readonly property string timeStr: pad(now.getHours()) + ":" + pad(now.getMinutes())

    readonly property var months: ["January","February","March","April","May","June",
                                    "July","August","September","October","November","December"]
    readonly property var days: ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    readonly property string tooltipText: days[now.getDay()] + ", " + now.getDate() + " " + months[now.getMonth()] + " " + now.getFullYear()

    implicitWidth: label.implicitWidth
    implicitHeight: 28

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: rootMod.now = new Date()
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: rootMod.timeStr
        color: root.ink
        font.family: root.mono
        font.pixelSize: 12
        font.letterSpacing: 1
    }

    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            var p = rootMod.mapToItem(null, width / 2, height / 2);
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod);
        }
    }

    Process {
        id: tzRunner
        command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation omarchy-tz-select 2>/dev/null"]
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.RightButton
        onEntered: { tipDelay.restart(); }
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod); }
        onClicked: (e) => {
            tipDelay.stop();
            root.hideTooltip(rootMod);
            tzRunner.running = false;
            tzRunner.running = true;
        }
    }
}
