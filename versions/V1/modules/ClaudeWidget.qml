import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property bool claudeActive: false
    property int  pct5h:   0
    // fill snaps to 5% steps, consistent with the 5% increments used elsewhere
    readonly property int pct5hStep: Math.round(pct5h / 5) * 5
    property bool blocked: false
    property string tooltipFull: ""

    readonly property string tooltipText: tooltipFull || ("Claude " + pct5h + "%")

    readonly property bool shown: claudeActive && root.modClaude

    // keep rendered until the collapse animation finishes, so the pill fades out
    // cleanly instead of being hard-clipped mid-shrink
    visible: implicitWidth > 0.5
    implicitWidth: shown ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    clip: true
    opacity: shown ? 1 : 0

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // ── process detection ──
    Process {
        id: detectProc
        command: ["bash", "-c", "pgrep -x claude >/dev/null 2>&1 && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: { rootMod.claudeActive = (this.text.trim() === "1") }
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { detectProc.running = false; detectProc.running = true }
    }

    // ── background pill ──
    Rectangle {
        anchors.centerIn: row
        width: row.width + 18
        height: 24; radius: 12
        color: root.pill
        border.color: root.sep
        border.width: 1
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        // icon with bottom-to-top red fill based on usage %
        Item {
            id: iconItem
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: iconBg.implicitWidth
            implicitHeight: iconBg.implicitHeight

            Text {
                id: iconBg
                text: String.fromCodePoint(0xF167A)
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.25)
                font.family: root.mono
                font.pixelSize: 14
            }

            Item {
                clip: true
                width: parent.width
                anchors.bottom: parent.bottom
                // floor the fill so low percentages still render over the glyph's
                // ink (a 3px fill at the very bottom lands in empty glyph space)
                height: rootMod.pct5hStep > 0
                    ? Math.min(parent.height, Math.max(parent.height * rootMod.pct5hStep / 100, parent.height * 0.25))
                    : 0
                Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                Text {
                    anchors.bottom: parent.bottom
                    text: String.fromCodePoint(0xF167A)
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 14
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.blocked ? "BLK" : String(rootMod.pct5h).padStart(2, "0") + "%"
            // icon fill conveys the level; text stays neutral & readable (blocked → red)
            color: rootMod.blocked
                ? root.seal
                : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85)
            font.family: root.mono
            font.pixelSize: 12
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // ── data polling ──
    Process {
        id: readProc
        command: ["cat", Quickshell.env("HOME") + "/.cache/claude-usage.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text.trim())
                    var util5h = parseFloat(d["5h-utilization"]) || 0
                    var util7d = parseFloat(d["7d-utilization"]) || 0
                    rootMod.pct5h   = Math.round(util5h * 100)
                    rootMod.blocked = d.status === "rejected" || d.status === "blocked"

                    var resetTs = parseInt(d["5h-reset"]) || 0
                    var now = Date.now() / 1000
                    var resetStr = "free window"
                    if (resetTs > now && resetTs <= now + 6 * 3600) {
                        var mins = Math.round((resetTs - now) / 60)
                        resetStr = mins >= 60
                            ? Math.floor(mins / 60) + "h " + (mins % 60) + "m"
                            : mins + "m"
                    }

                    var tokUsed  = ((d["_tokens_used"]  || 0) / 1e6).toFixed(2) + "M"
                    var tokLimit = ((d["_window_limit"] || 0) / 1e6).toFixed(1) + "M"
                    var rateH    = Math.round((d["_rate_per_hour"] || 0) / 1000)
                    var pct7d    = Math.round(util7d * 100)

                    rootMod.tooltipFull =
                        "Claude Code\n" +
                        "5h: " + rootMod.pct5h + "%  (reset in " + resetStr + ")\n" +
                        (pct7d > 0 ? "7d: " + pct7d + "%\n" : "") +
                        tokUsed + " / " + tokLimit + " tokens" +
                        (rateH > 0 ? "  · " + rateH + "k tok/h" : "")
                } catch (e) {
                    rootMod.pct5h    = 0
                    rootMod.tooltipFull = ""
                }
            }
        }
    }

    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { readProc.running = false; readProc.running = true }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: if (claudeActive) tip.show()
        onExited: { tip.hide() }
    }
}
