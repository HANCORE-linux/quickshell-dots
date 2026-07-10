import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Breakdown for SecurityWidget's badge. Read-only view of root.securityStatus
// (mirrored from ~/.cache/qs-security-status.json by SecurityWidget's FileView);
// "Scan now" re-runs ~/.local/bin/qs-security-scan.sh via root.securityCheckTick.
PanelWindow {
    id: panel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-security"

    readonly property int barBottom: 35
    readonly property int gap: 8

    readonly property var aur: root.securityStatus.aur_malware || ({})
    readonly property var bb: root.securityStatus.bumblebee || ({})
    readonly property bool everScanned: !!root.securityStatus.checked

    function statusColor(s) {
        if (s === "fail" || s === "findings" || s === "error") return root.warn
        if (s === "warn") return root.warn
        return Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
    }
    function statusLabel(s) {
        if (s === "clean") return "CLEAN"
        if (s === "warn") return "WARNINGS"
        if (s === "fail") return "COMPROMISED"
        if (s === "findings") return "FINDINGS"
        if (s === "error") return "ERROR"
        return "UNKNOWN"
    }
    function relTime(iso) {
        if (!iso) return ""
        var then = new Date(iso).getTime()
        if (isNaN(then)) return ""
        var mins = Math.max(0, Math.round((Date.now() - then) / 60000))
        if (mins < 1) return "just now"
        if (mins < 60) return mins + "m ago"
        var hrs = Math.round(mins / 60)
        if (hrs < 24) return hrs + "h ago"
        return Math.round(hrs / 24) + "d ago"
    }

    // detached (setsid -f) so the picker + floating terminal survive the
    // panel closing — mirrors applyRunner in ShellUpdatePanel.qml
    Process {
        id: bunCheckRunner
        command: ["setsid", "-f", "bash", Quickshell.env("HOME") + "/.local/bin/qs-bun-check-oneshot.sh"]
    }
    Process {
        id: bumblebeeRunner
        command: ["setsid", "-f", "bash", Quickshell.env("HOME") + "/.local/bin/qs-bumblebee-oneshot.sh"]
    }

    property real reveal: root.securityVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.securityVisible ? 160 : 120
            easing.type: root.securityVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.securityVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.securityVisible = false }

    Rectangle {
        id: card
        width: 340
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.securityBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
        opacity: panel.reveal
        focus: root.securityVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.securityVisible = false; event.accepted = true }
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
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Security"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                UiText {
                    anchors.right: closeBtn.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.everScanned ? panel.relTime(root.securityStatus.checked) : "never scanned"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                UiText {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.securityVisible = false
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── AUR-Malware section ──
            Column {
                width: parent.width
                spacing: 3
                Row {
                    width: parent.width
                    UiText {
                        text: "AUR-MALWARE"
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                        font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1
                    }
                    Item { width: parent.width - 140; height: 1 }
                    UiText {
                        text: panel.everScanned ? panel.statusLabel(panel.aur.status) : "—"
                        color: panel.statusColor(panel.aur.status)
                        font.family: root.mono; font.pixelSize: 9; font.weight: Font.Bold
                    }
                }
                UiText {
                    width: parent.width
                    text: panel.everScanned ? (panel.aur.summary || "no data") : "no scan yet"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.8)
                    font.family: root.mono; font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── bumblebee section ──
            Column {
                width: parent.width
                spacing: 3
                Row {
                    width: parent.width
                    UiText {
                        text: "BUMBLEBEE"
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                        font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1
                    }
                    Item { width: parent.width - 140; height: 1 }
                    UiText {
                        text: panel.everScanned ? panel.statusLabel(panel.bb.status) : "—"
                        color: panel.statusColor(panel.bb.status)
                        font.family: root.mono; font.pixelSize: 9; font.weight: Font.Bold
                    }
                }
                UiText {
                    width: parent.width
                    text: panel.everScanned ? (panel.bb.summary || "no data") : "no scan yet"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.8)
                    font.family: root.mono; font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── one-shot project scan (folder picker, not periodic) ──
            Column {
                width: parent.width
                spacing: 6
                UiText {
                    text: "SCAN A PROJECT FOLDER"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                    font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1
                }
                Row {
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: root.evenW((parent.width - 8) / 2)
                        height: 26; radius: root.tileRadius
                        color: bunMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: bunMa.containsMouse ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: "bun-check…"
                            color: bunMa.containsMouse ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 10
                        }
                        MouseArea {
                            id: bunMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.securityVisible = false
                                bunCheckRunner.running = false
                                bunCheckRunner.running = true
                            }
                        }
                    }

                    Rectangle {
                        width: root.evenW((parent.width - 8) / 2)
                        height: 26; radius: root.tileRadius
                        color: bbMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: bbMa.containsMouse ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: "bumblebee…"
                            color: bbMa.containsMouse ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 10
                        }
                        MouseArea {
                            id: bbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.securityVisible = false
                                bumblebeeRunner.running = false
                                bumblebeeRunner.running = true
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── scan now ──
            Rectangle {
                width: parent.width
                height: 28; radius: root.tileRadius
                color: (scanMa.containsMouse && !root.securityScanning) ? root.fillHover : root.fillIdle
                border.color: (scanMa.containsMouse && !root.securityScanning) ? root.seal : root.sep
                border.width: 1
                opacity: root.securityScanning ? 0.5 : 1.0
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText {
                    anchors.centerIn: parent
                    text: root.securityScanning ? "Scanning…" : "Scan now"
                    color: (scanMa.containsMouse && !root.securityScanning) ? root.seal : root.ink
                    font.family: root.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: scanMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !root.securityScanning
                    cursorShape: root.securityScanning ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: root.securityCheckTick++
                }
            }
        }
    }
}
