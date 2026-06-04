import QtQuick
import Quickshell
import Quickshell.Io
import "../IconMap.js" as IconMap

Item {
    id: rootMod
    required property var root

    property int updateCount: 0
    property int systemCount: 0
    property int aurCount: 0
    property int flatpakCount: 0
    property bool refreshing: false

    readonly property bool hasUpdates: rootMod.updateCount > 0

    implicitWidth: hasUpdates ? ic.implicitWidth + 4 + ct.implicitWidth + 2 : 24
    implicitHeight: 28

    Process {
        id: checkProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                rootMod.parseOutput(this.text)
                rootMod.refreshing = false
            }
        }
        onExited: {
            if (exitCode !== 0) rootMod.refreshing = false
        }
    }

    Timer {
        interval: 1800000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.archRefreshTick++
    }

    property int extTrigger: root.archRefreshTick
    onExtTriggerChanged: {
        if (!rootMod.refreshing) rootMod.doRefresh()
    }

    function doRefresh() {
        var cmd = [
            "bash", "-c",
            "LC_ALL=C pacman -Qu 2>/dev/null | while read n o _ v; do echo \"S|\"$n\"|\"$o\"|\"$v; done; " +
            "if command -v paru &>/dev/null; then paru -Qum 2>/dev/null | while read n o _ v; do echo \"A|\"$n\"|\"$o\"|\"$v; done; " +
            "elif command -v yay &>/dev/null; then yay -Qum 2>/dev/null | while read n o _ v; do echo \"A|\"$n\"|\"$o\"|\"$v; done; fi; " +
            "if command -v flatpak &>/dev/null; then " +
            "  flatpak update --no-deploy --noninteractive >/dev/null 2>&1; " +
            "  flatpak remote-ls --updates --columns=application,version 2>/dev/null | while read a v; do echo \"F|\"$a\"|?|\"$v; done; " +
            "fi"
        ]
        rootMod.refreshing = true
        checkProc.command = cmd
        checkProc.running = false
        checkProc.running = true
    }

    function parseOutput(text) {
        var lines = text.trim().split("\n")
        var updates = []
        var sysCount = 0; var aCount = 0; var fCount = 0
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|")
            if (parts.length >= 4) {
                var src = parts[0]
                var entry = {name: parts[1], oldVer: parts[2], newVer: parts[3], source: src === "S" ? "system" : (src === "A" ? "aur" : "flatpak")}
                updates.push(entry)
                if (src === "S") sysCount++
                else if (src === "A") aCount++
                else if (src === "F") fCount++
            }
        }
        rootMod.systemCount = sysCount
        rootMod.aurCount = aCount
        rootMod.flatpakCount = fCount
        rootMod.updateCount = sysCount + aCount + fCount
        root.archUpdates = updates
    }

    Process {
        id: updateRunner
        command: ["bash", "-c", "omarchy-launch-floating-terminal-with-presentation 'paru'"]
    }

    Row {
        anchors.centerIn: parent
        spacing: 4
        Text {
            id: ic
            text: rootMod.refreshing ? "\uE5D5" : IconMap.icon("package_2")
            color: rootMod.refreshing
                ? Qt.rgba(root.sumi.r, root.sumi.g, root.sumi.b, 1)
                : (rootMod.hasUpdates ? root.seal : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4))
            font.family: "Material Symbols Rounded"
            font.pixelSize: 14
        }
        Text {
            id: ct
            visible: rootMod.hasUpdates || rootMod.refreshing
            text: rootMod.refreshing ? "\u22EF" : String(rootMod.updateCount)
            color: rootMod.refreshing
                ? Qt.rgba(root.sumi.r, root.sumi.g, root.sumi.b, 1)
                : (rootMod.hasUpdates ? root.seal : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4))
            font.family: root.mono
            font.pixelSize: 12
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    readonly property string tooltipText: {
        if (rootMod.refreshing) return ""
        if (rootMod.updateCount === 0) return "Up to date"
        var parts = []
        if (rootMod.systemCount) parts.push(rootMod.systemCount + " system")
        if (rootMod.aurCount) parts.push(rootMod.aurCount + " AUR")
        if (rootMod.flatpakCount) parts.push(rootMod.flatpakCount + " flatpak")
        return parts.join(" \u00B7 ") + "\nClick to view details"
    }

    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            if (!rootMod.tooltipText) return;
            var p = rootMod.mapToItem(null, width / 2, height / 2);
            root.showTooltip(rootMod.tooltipText, p.x, p.y, rootMod);
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: { tipDelay.restart(); }
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod); }
        onClicked: (e) => {
            tipDelay.stop();
            root.hideTooltip(rootMod);
            if (e.button === Qt.RightButton) {
                root.archRefreshTick++;
            } else {
                root.archVisible = true;
            }
        }
    }
}
