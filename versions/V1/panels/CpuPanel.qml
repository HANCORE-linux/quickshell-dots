import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: cpuPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-cpu"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property int cpuPct: 0
    property string gpuDriver: ""
    property int gpuUtil: 0
    property int gpuTemp: 0
    property int gpuMemUsed: 0
    property int gpuMemTotal: 0
    readonly property bool hasGpu: gpuDriver !== "" && gpuDriver !== "none"

    property real reveal: root.cpuVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.cpuVisible ? 160 : 120
            easing.type: root.cpuVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.cpuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.cpuVisible = false
    }

    Rectangle {
        id: card
        width: 320
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: 6
        y: barBottom + gap
        opacity: cpuPanel.reveal
        focus: root.cpuVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.cpuVisible = false;
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── header ──
            Item {
                width: parent.width
                height: 24
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CPU \u00B7 GPU"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2715"
                    color: root.sumi
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cpuVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── CPU (label · bar · % on one row) ──
            Item {
                width: parent.width
                height: 16
                Text {
                    id: cpuLbl
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "CPU"; color: root.sumi
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Text {
                    id: cpuVal
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: cpuPanel.cpuPct + "%"; color: root.seal
                    font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.left: cpuLbl.right; anchors.leftMargin: 8
                    anchors.right: cpuVal.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8; radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * cpuPanel.cpuPct / 100
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // ── GPU (label · bar · % on one row) ──
            Item {
                width: parent.width
                height: 16
                visible: cpuPanel.hasGpu
                Text {
                    id: gpuLbl
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "GPU"; color: root.sumi
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Text {
                    id: gpuVal
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: cpuPanel.gpuUtil + "%"; color: root.seal
                    font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.left: gpuLbl.right; anchors.leftMargin: 8
                    anchors.right: gpuVal.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8; radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * cpuPanel.gpuUtil / 100
                        height: parent.height; radius: 4
                        color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            Row {
                width: parent.width
                visible: cpuPanel.hasGpu && cpuPanel.gpuTemp > 0
                Text {
                    text: "Temperature"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.4
                }
                Text {
                    text: cpuPanel.gpuTemp + "\u00B0C"
                    color: root.ink
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.3
                }
            }

            Row {
                width: parent.width
                visible: cpuPanel.hasGpu && cpuPanel.gpuMemTotal > 0
                Text {
                    text: "VRAM"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.4
                }
                Text {
                    text: cpuPanel.gpuMemUsed + " / " + cpuPanel.gpuMemTotal + " MiB"
                    color: root.ink
                    font.family: root.mono; font.pixelSize: 11
                    width: parent.width * 0.3
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── button ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4
                color: root.seal
                Text {
                    anchors.centerIn: parent
                    text: "Open btop"
                    color: root.paper
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.cpuVisible = false;
                        btopRunner.running = false;
                        btopRunner.running = true;
                    }
                }
            }
        }
    }

    Process {
        id: dataProc
        command: ["bash", "-c",
            "read _ u1 n1 s1 i1 w1 r1 s s < /proc/stat && " +
            "sleep 0.5 && " +
            "read _ u2 n2 s2 i2 w2 r2 s s < /proc/stat && " +
            "du=$((u2+n2+s2-u1-n1-s1)) && " +
            "di=$((i2-i1)) && dt=$((du+di)) && " +
            "echo CPU $((dt>0?100*du/dt:0))%; " +
            "if command -v nvidia-smi &>/dev/null; then " +
            "  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | " +
            "  awk -F', ' '{printf \"GPU %s %s %s %s\\n\", $1, $2, $3, $4}'; " +
            "elif [ -f /sys/class/drm/card0/device/gpu_busy_percent ]; then " +
            "  read p < /sys/class/drm/card0/device/gpu_busy_percent; " +
            "  t=$(cat /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1); " +
            "  echo \"GPU $p 0 0 0\"; " +
            "elif [ -f /sys/class/hwmon/hwmon2/device/gpu_busy_percent ]; then " +
            "  read p < /sys/class/hwmon/hwmon2/device/gpu_busy_percent; " +
            "  echo \"GPU $p 0 0 0\"; " +
            "fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].trim().split(/\s+/)
                    if (parts[0] === "CPU" && parts.length >= 2) {
                        cpuPanel.cpuPct = parseInt(parts[1]) || 0
                    } else if (parts[0] === "GPU" && parts.length >= 2) {
                        cpuPanel.gpuDriver = "detected"
                        cpuPanel.gpuUtil = parseInt(parts[1]) || 0
                        cpuPanel.gpuTemp = parseInt(parts[2]) || 0
                        cpuPanel.gpuMemUsed = parseInt(parts[3]) || 0
                        cpuPanel.gpuMemTotal = parseInt(parts[4]) || 0
                    }
                }
            }
        }
    }

    Process {
        id: btopRunner
        command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation 'btop'"]
    }

    onVisibleChanged: {
        if (visible) {
            dataProc.running = false
            dataProc.running = true
        }
    }
}
