import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property string state: "idle"   // idle | recording | transcribing
    property string hint:  ""
    property bool   hasVoxtype: true   // turns off polling entirely when absent

    readonly property string displayIcon: {
        if (state === "recording")    return "\uE029"   // mic
        if (state === "transcribing") return "\uE65F"   // auto_awesome
        return ""
    }

    visible: displayIcon !== ""
    implicitWidth: visible ? 20 : 0
    implicitHeight: 28

    Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    readonly property string tooltipText: hint !== "" ? hint : (state === "recording" ? "Voxtype recording" : "Voxtype transcribing")

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
            "else echo 'MISSING'; fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split("\t")
                if (parts[0] === "MISSING") {
                    rootMod.hasVoxtype = false   // stops the timer → no more polling
                    rootMod.state = "idle"; rootMod.hint = ""
                    return
                }
                rootMod.state = parts[0] || "idle"
                rootMod.hint  = parts[1] || ""
            }
        }
    }

    Timer {
        interval: 1000; running: rootMod.hasVoxtype; repeat: true; triggeredOnStart: true
        onTriggered: { vtProc.running = false; vtProc.running = true }
    }

    Process { id: modelProc;  command: ["bash", "-c", "omarchy-voxtype-model"] }
    Process { id: configProc; command: ["bash", "-c", "omarchy-voxtype-config"] }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited:  { tip.hide() }
        onClicked: (e) => {
            tip.hide()
            if (e.button === Qt.RightButton) { configProc.running = false; configProc.running = true }
            else                             { modelProc.running = false;  modelProc.running = true }
        }
    }
}
