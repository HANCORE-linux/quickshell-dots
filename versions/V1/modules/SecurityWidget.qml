import QtQuick
import Quickshell
import Quickshell.Io
import "../IconMap.js" as IconMap

// Security-status badge. Read-only mirror of ~/.cache/qs-security-status.json,
// written by ~/.local/bin/qs-security-scan.sh (systemd timer, every 6h).
// Merges two independent scanners: AUR-Malware (Atomic-Arch IOC scan) and
// bumblebee (package inventory; findings stay 0 until an exposure catalog is
// wired up). Click opens SecurityPanel for the breakdown + manual rescan.
Item {
    id: rootMod
    required property var root

    implicitWidth: 22
    implicitHeight: 28

    readonly property var aur: root.securityStatus.aur_malware || ({})
    readonly property var bb: root.securityStatus.bumblebee || ({})
    readonly property bool everScanned: !!root.securityStatus.checked

    readonly property bool hasNotice: everScanned && (
        aur.status === "warn" || aur.status === "fail"
        || bb.status === "findings" || aur.status === "error" || bb.status === "error"
    )
    readonly property bool hasCritical: aur.status === "fail" || bb.status === "findings"

    FileView {
        id: statusFile
        path: Quickshell.env("HOME") + "/.cache/qs-security-status.json"
        watchChanges: true
        onFileChanged: statusFile.reload()
        onLoaded: {
            try {
                root.securityStatus = JSON.parse(statusFile.text())
            } catch (e) {
                // keep the last good value on a malformed read
            }
            rootMod.root.securityScanning = false
        }
        onLoadFailed: {}   // first boot, before the timer's first run: no badge, no notice
    }

    Component.onCompleted: statusFile.reload()

    property int scanTrigger: root.securityCheckTick
    onScanTriggerChanged: {
        rootMod.root.securityScanning = true
        rescanProc.running = false
        rescanProc.running = true
    }

    Process {
        id: rescanProc
        command: [Quickshell.env("HOME") + "/.local/bin/qs-security-scan.sh"]
        running: false
        onExited: statusFile.reload()
    }

    // unstick the button if a manual scan ever hangs (real scans take ~10s)
    Timer {
        interval: 60000
        running: root.securityScanning
        onTriggered: { root.securityScanning = false; rescanProc.running = false }
    }

    IconText {
        id: ic
        anchors.centerIn: parent
        text: root.securityScanning ? "" : IconMap.icon("shield")
        color: root.securityScanning
            ? Qt.rgba(root.sumi.r, root.sumi.g, root.sumi.b, 1)
            : (rootMod.hasNotice ? root.warn : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4))
        font.pixelSize: 14
    }

    readonly property string tooltipText: {
        if (root.securityScanning) return "Scanning…"
        if (!rootMod.everScanned) return "Security scan pending\nClick to view details"
        var parts = []
        if (rootMod.aur.status) parts.push("AUR-Malware: " + (rootMod.aur.summary || rootMod.aur.status))
        if (rootMod.bb.status) parts.push("bumblebee: " + (rootMod.bb.summary || rootMod.bb.status))
        return parts.join("\n") + "\nClick to view details"
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: tip.hide()
        onClicked: {
            tip.hide()
            var p = rootMod.mapToItem(null, rootMod.width / 2, 0)
            rootMod.root.setPanelAnchor("security", p.x)
            rootMod.root.securityVisible = true
        }
    }
}
