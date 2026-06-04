import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property string state: "idle"   // idle | recording | transcribing
    property string tip:   ""

    readonly property string displayIcon: {
        if (state === "recording")    return "\uE029"   // mic
        if (state === "transcribing") return "\uE65F"   // auto_awesome
        return ""
    }

    visible: displayIcon !== ""
    implicitWidth: visible ? 20 : 0
    implicitHeight: 28

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    readonly property string tooltipText: tip !== "" ? tip : (state === "recording" ? "Voxtype recording" : "Voxtype transcribing")

    Text {
        id: ico
        anchors.centerIn: parent
        text: rootMod.displayIcon
        color: rootMod.state === "recording" ? root.seal : root.ink
        font.family: "Material Symbols Rounded"
        font.pixelSize: 14

        // pulse while recording
        SequentialAnimation on opacity {
            running: rootMod.state === "recording"
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
        }
        onTextChanged: if (rootMod.state !== "recording") opacity = 1.0
    }

    Process {
        id: vtProc
        command: ["bash", "-c",
            "if command -v voxtype >/dev/null 2>&1; then " +
            "timeout 1 voxtype status --extended --format json 2>/dev/null | jq -r '[(.class // .alt // \"idle\"), ((.tooltip // \"\") | split(\"\\n\")[0])] | @tsv' 2>/dev/null; " +
            "else echo 'idle\\t'; fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split("\t")
                rootMod.state = parts[0] || "idle"
                rootMod.tip   = parts[1] || ""
            }
        }
    }

    Timer {
        interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { vtProc.running = false; vtProc.running = true }
    }

    Process { id: modelProc;  command: ["bash", "-c", "omarchy-voxtype-model"] }
    Process { id: configProc; command: ["bash", "-c", "omarchy-voxtype-config"] }

    Timer {
        id: tipDelay; interval: 320
        onTriggered: {
            if (!rootMod.tooltipText) return
            var p = rootMod.mapToItem(null, width / 2, height / 2)
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod)
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tipDelay.restart()
        onExited:  { tipDelay.stop(); root.hideTooltip(rootMod) }
        onClicked: (e) => {
            tipDelay.stop(); root.hideTooltip(rootMod)
            if (e.button === Qt.RightButton) { configProc.running = false; configProc.running = true }
            else                             { modelProc.running = false;  modelProc.running = true }
        }
    }
}
