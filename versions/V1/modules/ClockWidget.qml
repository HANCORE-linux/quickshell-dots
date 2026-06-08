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

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    Process {
        id: tzRunner
        command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation omarchy-tz-select 2>/dev/null"]
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.RightButton
        onEntered: { tip.show(); }
        onExited: { tip.hide(); }
        onClicked: (e) => {
            tip.hide();
            tzRunner.running = false;
            tzRunner.running = true;
        }
    }
}
