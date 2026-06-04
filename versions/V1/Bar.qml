import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "modules"

PanelWindow {
    id: bar
    required property var root

    color: "transparent"
    anchors { top: true; left: true; right: true }
    exclusionMode: ExclusionMode.Auto
    implicitHeight: 37

    // split state lives in Theme (shared with the ControlPanel)
    readonly property int gap: 6
    readonly property int rad: 18

    Item {
        id: island
        anchors {
            top: parent.top; topMargin: 5
            left: parent.left; leftMargin: 5
            right: parent.right; rightMargin: 5
        }
        height: 32

        // center width tracks its content (grows when indicators appear)
        readonly property real centerW: Math.round(Math.max(120, centerRow.implicitWidth + 24))
        readonly property real fixedW: 16 + centerW + 16
            + (root.splitLeft ? bar.gap * 2 : 0)
            + (root.splitRight ? bar.gap * 2 : 0)
        readonly property real fillW: Math.round(Math.max(0, width - fixedW) / 2)

        // ── dynamic pill runs ──
        // 5 content atoms: A0=launcher/ws/status, A1=mem/cpu/audio, A2=center,
        // A3=mpris/batt/bri, A4=net/pp/bt. Cut before atom n by these splits:
        readonly property var atomCut: [false, root.splitArch, root.splitMon, root.splitMprisL, root.splitNet]
        // depends only on splits → recomputed only when a split toggles (no flicker)
        readonly property var pillRuns: {
            var runs = []
            var i = 0
            while (i < 5) {
                var s = i
                while (i + 1 < 5 && !atomCut[i + 1]) i++
                runs.push({ s: s, e: i })
                i++
            }
            return runs
        }
        // is atom non-empty? (only atom 3 = mpris/batt/bri can be empty)
        function atomVisible(i) {
            if (i === 3) return mprisW.width > 1 || battW.width > 1 || briW.width > 1
            return true
        }
        // content edges (used when an atom is the last/first VISIBLE in a run but
        // not the run's structural end — i.e. trailing/leading empty atoms exist)
        function atomCL(i) {
            if (i === 1) return memW.x
            if (i === 2) return centerRow.x - 9
            if (i === 3) return mprisW.x
            return networkW.x
        }
        function atomCR(i) {
            if (i === 0) return statusCluster.x + statusCluster.width
            if (i === 1) return audioW.x + audioW.width
            if (i === 2) return centerRow.x + centerRow.width + 9
            return briW.x + briW.width
        }
        // run edges aligned to the split gaps / island edges (clean borders).
        // the center (atom 2) sits in the middle of the centering whitespace, far
        // from its mon/mpris split gaps → hug the clock content instead.
        function runLeftEdge(s) {
            if (s === 0) return 0
            if (s === 1) return gArchL.x + gArchL.width
            if (s === 2) return centerRow.x - 14
            if (s === 3) return sepML.x + sepML.width
            return sepNet.x + sepNet.width
        }
        function runRightEdge(e) {
            if (e === 4) return island.width
            if (e === 0) return sepArch.x
            if (e === 1) return sepMon.x
            if (e === 2) return centerRow.x + centerRow.width + 14
            return gNetL.x
        }

        // ── dynamic section pills (one per content run) ──
        Repeater {
            model: island.pillRuns
            delegate: Rectangle {
                required property var modelData
                readonly property int s: modelData.s
                readonly property int e: modelData.e
                readonly property bool hasContent: {
                    for (var i = s; i <= e; i++) if (island.atomVisible(i)) return true
                    return false
                }
                // left: structural edge if first atom visible, else hug first visible content
                readonly property real lx: {
                    for (var i = s; i <= e; i++) if (island.atomVisible(i))
                        return i === s ? island.runLeftEdge(s) : island.atomCL(i) - 5
                    return 0
                }
                // right: structural edge if last atom visible, else hug last visible content
                readonly property real rx: {
                    for (var i = e; i >= s; i--) if (island.atomVisible(i))
                        return i === e ? island.runRightEdge(e) : island.atomCR(i) + 5
                    return 0
                }
                x: lx
                y: 0
                height: island.height
                width: Math.max(0, rx - lx)
                visible: hasContent && width > 16
                radius: rad
                color: root.bg
                border.color: root.sep
                border.width: 1
                Behavior on x     { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }

        // ── sizing skeleton (anchor chain, left-to-right) ──
        Item { id: sLeft
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: island.fillW
        }
        Item { id: gL
            anchors { left: sLeft.right; top: parent.top; bottom: parent.bottom }
            width: root.splitLeft ? bar.gap : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Item { id: sep1
            anchors { left: gL.right; top: parent.top; bottom: parent.bottom }
            width: 16
        }
        Item { id: gR1
            anchors { left: sep1.right; top: parent.top; bottom: parent.bottom }
            width: root.splitLeft ? bar.gap : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Item { id: sCenter
            anchors { left: gR1.right; top: parent.top; bottom: parent.bottom }
            width: island.centerW
        }
        Item { id: gL2
            anchors { left: sCenter.right; top: parent.top; bottom: parent.bottom }
            width: root.splitRight ? bar.gap : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Item { id: sep2
            anchors { left: gL2.right; top: parent.top; bottom: parent.bottom }
            width: 16
        }
        Item { id: gR2
            anchors { left: sep2.right; top: parent.top; bottom: parent.bottom }
            width: root.splitRight ? bar.gap : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Item { id: sRight
            anchors { left: gR2.right; top: parent.top; bottom: parent.bottom; right: parent.right }
        }

        // ── net sub-split skeleton (mirror of arch, right-side) ──
        Item { id: sepNet
            anchors { top: parent.top; bottom: parent.bottom }
            x: networkW.x - 4 - width
            width: 12
        }
        Item { id: gNetL
            anchors { top: parent.top; bottom: parent.bottom }
            width: root.splitNet ? bar.gap : 0
            x: sepNet.x - width
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        // ── mpris-left sub-split skeleton (peels whole right cluster) ──
        Item { id: sepML
            anchors { top: parent.top; bottom: parent.bottom }
            x: mprisW.x - 4 - width
            width: 12
        }
        Item { id: gML
            anchors { top: parent.top; bottom: parent.bottom }
            width: root.splitMprisL ? bar.gap : 0
            x: sepML.x - width
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }


        // ── arch sub-split skeleton ──
        Item { id: sepArch
            anchors { top: parent.top; bottom: parent.bottom }
            x: statusCluster.x + statusCluster.width + 4
            width: 12
        }
        Item { id: gArchL
            anchors { top: parent.top; bottom: parent.bottom }
            x: sepArch.x + sepArch.width
            width: root.splitArch ? bar.gap : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Item { id: sLeftA
            anchors { left: sLeft.left; top: parent.top; bottom: parent.bottom; right: sepArch.left }
        }
        Item { id: sLeftB
            anchors { top: parent.top; bottom: parent.bottom }
            x: gArchL.x + gArchL.width
            width: Math.max(0, sepMon.x - (gArchL.x + gArchL.width))
        }
        Item { id: sepMon
            anchors { top: parent.top; bottom: parent.bottom }
            x: audioW.x + audioW.width + 4
            width: 12
        }
        Item { id: gMonL
            anchors { top: parent.top; bottom: parent.bottom }
            x: sepMon.x + sepMon.width
            width: root.splitMon ? bar.gap : 0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
        Item { id: sLeftC
            anchors { top: parent.top; bottom: parent.bottom }
            x: gMonL.x + gMonL.width
            width: Math.max(0, sLeft.width - (gMonL.x + gMonL.width))
        }


        // ── center cluster pill (weather · clock · date · indicators) ──
        Rectangle {
            anchors.centerIn: centerRow
            width: centerRow.implicitWidth + 18
            height: 24
            radius: 12
            color: root.pill
            border.color: root.sep
            border.width: 1
        }

        // ── weather + clock + date ──
        Row {
            id: centerRow
            anchors.centerIn: sCenter
            spacing: 8
            WeatherWidget {
                id: weather
                root: bar.root
            }
            ClockWidget {
                id: clock
                root: bar.root
            }
            Item {
                implicitWidth: dateLabel.implicitWidth
                implicitHeight: 28
                Text {
                    id: dateLabel
                    anchors.centerIn: parent
                    text: {
                        clock.now;
                        var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                        var d = new Date();
                        return days[d.getDay()] + " " + d.getDate();
                    }
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 0.5
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { root.calendarTick++; root.calendarVisible = !root.calendarVisible; }
                }
            }
            IdleWidget { root: bar.root; anchors.verticalCenter: parent.verticalCenter }
            NotificationSilenceWidget { root: bar.root; anchors.verticalCenter: parent.verticalCenter }
            ScreenRecordWidget { root: bar.root; anchors.verticalCenter: parent.verticalCenter }
            VoxtypeWidget { root: bar.root; anchors.verticalCenter: parent.verticalCenter }
            UpdateWidget { root: bar.root; anchors.verticalCenter: parent.verticalCenter }
        }

        // ── sep1/sep2 (Left/Right) are now handled by Monitor/Media at the
        //    content edge — the floating centering-zone separators were removed.

        // ── sync panel positions ──
        Binding { target: root; property: "trayBarX";  value: island.x + statusCluster.x }
        Binding { target: root; property: "notifBarX"; value: island.x + statusCluster.x }

        // ── modules ──
        LauncherWidget {
            id: launcherW
            anchors { left: sLeft.left; leftMargin: 4; verticalCenter: sLeft.verticalCenter }
            root: bar.root
        }
        WorkspaceWidget {
            id: wsW
            anchors { left: launcherW.right; leftMargin: 10; verticalCenter: sLeft.verticalCenter }
            root: bar.root
        }
        // ── status cluster (arch · tray · notif) in one shared pill ──
        Item {
            id: statusCluster
            anchors { left: wsW.right; leftMargin: 8; verticalCenter: sLeft.verticalCenter }
            implicitWidth: statusRow.implicitWidth + 18
            implicitHeight: 28

            Rectangle {
                anchors.centerIn: parent
                width: parent.implicitWidth
                height: 24
                radius: 12
                color: root.pill
                border.color: root.sep
                border.width: 1
            }

            Row {
                id: statusRow
                anchors.centerIn: parent
                spacing: 6
                ArchUpdaterWidget { id: archUpdater; root: bar.root; anchors.verticalCenter: parent.verticalCenter }
                TrayWidget { id: trayW; root: bar.root; anchors.verticalCenter: parent.verticalCenter }
                NotificationWidget { id: notifW; root: bar.root; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        // ── separator arch (split/merge arch) ──
        Text {
            anchors.centerIn: sepArch
            text: "•"; color: root.sumi
            font.pixelSize: 9; font.family: root.mono
            opacity: root.splitArch ? 0.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        Rectangle {
            anchors.centerIn: sepArch
            anchors.horizontalCenterOffset: 3
            width: 14; height: 14; radius: 7
            color: root.sumi
            opacity: root.splitArch && sepArchMa.containsMouse ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Text {
                anchors.centerIn: parent
                text: "←"; color: root.paper
                font.pixelSize: 9; font.family: root.mono
            }
        }
        MouseArea {
            id: sepArchMa
            anchors.fill: sepArch
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.splitArch = !root.splitArch
        }
        MemoryWidget {
            id: memW
            anchors { left: parent.left; leftMargin: gArchL.x + gArchL.width + 4; verticalCenter: sLeft.verticalCenter }
            root: bar.root
        }
        CpuWidget {
            id: cpuW
            anchors { left: memW.right; leftMargin: 4; verticalCenter: sLeft.verticalCenter }
            root: bar.root
        }
        AudioWidget {
            id: audioW
            anchors { left: cpuW.right; leftMargin: 4; verticalCenter: sLeft.verticalCenter }
            root: bar.root
        }

        // ── separator mon (split/merge monitors) ──
        Text {
            anchors.centerIn: sepMon
            text: "•"; color: root.sumi
            font.pixelSize: 9; font.family: root.mono
            opacity: root.splitMon ? 0.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        Rectangle {
            anchors.centerIn: sepMon
            anchors.horizontalCenterOffset: 3
            width: 14; height: 14; radius: 7; color: root.sumi
            opacity: root.splitMon && sepMonMa.containsMouse ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Text { anchors.centerIn: parent; text: "←"; color: root.paper; font.pixelSize: 9; font.family: root.mono }
        }
        MouseArea {
            id: sepMonMa
            anchors.fill: sepMon
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.splitMon = !root.splitMon
        }
        BluetoothWidget {
            id: btW
            anchors { right: sRight.right; rightMargin: 4; verticalCenter: sRight.verticalCenter }
            root: bar.root
        }
        PowerProfileWidget {
            id: ppW
            anchors { right: btW.left; rightMargin: 4; verticalCenter: sRight.verticalCenter }
            root: bar.root
        }
        NetworkWidget {
            id: networkW
            anchors { right: ppW.left; rightMargin: 4; verticalCenter: sRight.verticalCenter }
            root: bar.root
        }
        // ── separator net (split/merge net) ──
        Text {
            anchors.centerIn: sepNet
            text: "•"; color: root.sumi
            font.pixelSize: 9; font.family: root.mono
            opacity: root.splitNet ? 0.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        Rectangle {
            anchors.centerIn: sepNet
            anchors.horizontalCenterOffset: -3
            width: 14; height: 14; radius: 7; color: root.sumi
            opacity: root.splitNet && sepNetMa.containsMouse ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Text { anchors.centerIn: parent; text: "←"; color: root.paper; font.pixelSize: 9; font.family: root.mono }
        }
        MouseArea {
            id: sepNetMa
            anchors.fill: sepNet
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.splitNet = !root.splitNet
        }

        BrightnessWidget {
            id: briW
            anchors { right: gNetL.left; rightMargin: briW.hasBacklight ? 4 : 0; verticalCenter: sRight.verticalCenter }
            root: bar.root
        }
        BatteryWidget {
            id: battW
            anchors { right: briW.left; rightMargin: battW.hasBattery ? 4 : 0; verticalCenter: sRight.verticalCenter }
            root: bar.root
        }
        MprisWidget {
            id: mprisW
            anchors { right: battW.left; rightMargin: 4; verticalCenter: sRight.verticalCenter }
            root: bar.root
        }

        // ── separator mpris-left (peel/merge right cluster) ──
        Text {
            anchors.centerIn: sepML
            text: "•"; color: root.sumi
            font.pixelSize: 9; font.family: root.mono
            opacity: root.splitMprisL ? 0.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
        Rectangle {
            anchors.centerIn: sepML
            anchors.horizontalCenterOffset: -3
            width: 14; height: 14; radius: 7; color: root.sumi
            opacity: root.splitMprisL && sepMLMa.containsMouse ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Text { anchors.centerIn: parent; text: "←"; color: root.paper; font.pixelSize: 9; font.family: root.mono }
        }
        MouseArea {
            id: sepMLMa
            anchors.fill: sepML
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: root.splitMprisL = !root.splitMprisL
        }
    }
}
