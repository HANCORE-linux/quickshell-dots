import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

PanelWindow {
    id: launcher
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-launcher"
    WlrLayershell.keyboardFocus: root.launcherVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property var activeScreen: Quickshell.screens[0]
    screen: activeScreen

    property real reveal: root.launcherVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.launcherVisible ? 200 : 150
            easing.type: root.launcherVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001

    // ── App data ──
    property var allApps: []
    property var filteredApps: []
    property var settingsApps: []
    property var favorites: []
    property var hiddenApps: []
    property bool settingsMode: false
    property int selectedIndex: 0

    readonly property string favFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-favorites"
    readonly property string hidFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-hidden"

    // ── Load apps ──
    Process {
        id: appLoader
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/bar/load-apps.py"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var apps = []
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("||")
                    if (parts.length >= 3 && parts[0].trim())
                        apps.push({ name: parts[0], icon: parts[1], exec: parts[2] })
                }
                launcher.allApps = apps
                launcher.filter()
            }
        }
    }

    // ── Load favorites ──
    Process {
        id: favLoader
        command: ["sh", "-c", "cat '" + launcher.favFile + "' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                launcher.favorites = this.text.trim().split("\n").filter(function(x) { return x.trim() !== "" })
                launcher.filter()
            }
        }
    }

    // ── Load hidden ──
    Process {
        id: hidLoader
        command: ["sh", "-c", "cat '" + launcher.hidFile + "' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                launcher.hiddenApps = this.text.trim().split("\n").filter(function(x) { return x.trim() !== "" })
                launcher.filter()
            }
        }
    }

    // ── Save processes ──
    Process { id: saveFavProc; command: [] }
    Process { id: saveHidProc; command: [] }

    Component.onCompleted: {
        favLoader.running = true
        hidLoader.running = true
        appLoader.running = true
    }

    function saveFavorites() {
        var args = ["python3", "-c",
            "import sys; f=open(sys.argv[1],'w'); f.write('\\n'.join(sys.argv[2:])); f.close()",
            launcher.favFile
        ]
        for (var i = 0; i < launcher.favorites.length; i++) args.push(launcher.favorites[i])
        saveFavProc.command = args
        saveFavProc.running = true
    }

    function saveHidden() {
        var args = ["python3", "-c",
            "import sys; f=open(sys.argv[1],'w'); f.write('\\n'.join(sys.argv[2:])); f.close()",
            launcher.hidFile
        ]
        for (var i = 0; i < launcher.hiddenApps.length; i++) args.push(launcher.hiddenApps[i])
        saveHidProc.command = args
        saveHidProc.running = true
    }

    function toggleFavorite(appName) {
        var idx = launcher.favorites.indexOf(appName)
        var newFavs = launcher.favorites.slice()
        if (idx >= 0) newFavs.splice(idx, 1)
        else newFavs.push(appName)
        launcher.favorites = newFavs
        launcher.saveFavorites()
        launcher.filter()
    }

    function toggleHidden(appName) {
        var idx = launcher.hiddenApps.indexOf(appName)
        var newHidden = launcher.hiddenApps.slice()
        if (idx >= 0) newHidden.splice(idx, 1)
        else newHidden.push(appName)
        launcher.hiddenApps = newHidden
        launcher.saveHidden()
        launcher.filter()
    }

    function filter() {
        var q = searchInput.text.toLowerCase().trim()

        // Filtered by search (applied to both modes)
        var all = q ? launcher.allApps.filter(function(a) {
            return a.name.toLowerCase().indexOf(q) >= 0
        }) : launcher.allApps.slice()

        // Settings: all apps including hidden
        launcher.settingsApps = all

        // Normal: exclude hidden, favorites first
        var visible = all.filter(function(a) {
            return launcher.hiddenApps.indexOf(a.name) < 0
        })
        var favs = visible.filter(function(a) { return launcher.favorites.indexOf(a.name) >= 0 })
        var rest = visible.filter(function(a) { return launcher.favorites.indexOf(a.name) < 0 })
        launcher.filteredApps = favs.concat(rest)

        launcher.selectedIndex = 0
        appListArea.scrollOffset = 0
    }

    function launch(app) {
        if (!app) return
        launchProc.command = ["bash", "-c", "nohup " + app.exec + " &>/dev/null &"]
        launchProc.running = true
        close()
    }

    function close() {
        root.launcherVisible = false
        searchInput.text = ""
        launcher.settingsMode = false
        appListArea.scrollOffset = 0
        filter()
    }

    Process { id: launchProc; command: [] }

    Timer {
        id: focusTimer; interval: 30
        onTriggered: searchInput.forceActiveFocus()
    }
    Connections {
        target: root
        function onLauncherVisibleChanged() {
            if (root.launcherVisible) {
                var mon = Hyprland.focusedMonitor
                if (mon) {
                    for (var i = 0; i < Quickshell.screens.length; i++) {
                        if (Quickshell.screens[i].name === mon.name) {
                            launcher.activeScreen = Quickshell.screens[i]
                            break
                        }
                    }
                }
                focusTimer.restart()
            }
        }
    }

    // ── Backdrop ──
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55 * launcher.reveal)
        MouseArea {
            anchors.fill: parent
            onClicked: launcher.close()
        }
    }

    // ── Card ──
    Rectangle {
        id: card
        width: 560
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - launcher.reveal) * -40
        height: cardCol.implicitHeight + 20
        opacity: launcher.reveal
        radius: 8
        color: root.bg
        border.color: root.sep
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 8

            // ── Search bar with gear button ──
            Item {
                width: parent.width
                height: 40

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                    border.color: searchInput.activeFocus
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.7)
                        : root.sep
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 12
                    text: launcher.settingsMode ? "Filter…" : "Search applications…"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 13
                    visible: searchInput.text.length === 0
                }

                TextInput {
                    id: searchInput
                    anchors {
                        left: parent.left; right: gearBtn.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12; rightMargin: 6
                    }
                    color: root.ink
                    font.family: root.mono; font.pixelSize: 13
                    selectByMouse: true
                    onTextChanged: launcher.filter()

                    Keys.onUpPressed: {
                        if (!launcher.settingsMode && launcher.selectedIndex > 0) {
                            launcher.selectedIndex--
                            var top = launcher.selectedIndex * 46
                            if (top < appListArea.scrollOffset) appListArea.scrollOffset = top
                        }
                    }
                    Keys.onDownPressed: {
                        if (!launcher.settingsMode && launcher.selectedIndex < launcher.filteredApps.length - 1) {
                            launcher.selectedIndex++
                            var bottom = (launcher.selectedIndex + 1) * 46
                            if (bottom > appListArea.scrollOffset + appListArea.height)
                                appListArea.scrollOffset = bottom - appListArea.height
                        }
                    }
                    Keys.onReturnPressed: {
                        if (!launcher.settingsMode && launcher.filteredApps.length > 0)
                            launcher.launch(launcher.filteredApps[launcher.selectedIndex])
                    }
                    Keys.onEscapePressed: {
                        if (launcher.settingsMode) {
                            launcher.settingsMode = false
                            searchInput.text = ""
                            launcher.filter()
                        } else {
                            launcher.close()
                        }
                    }
                }

                // Gear button
                Item {
                    id: gearBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28

                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: launcher.settingsMode
                            ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.2)
                            : (gearMa.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1) : "transparent")
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: launcher.settingsMode ? root.seal : root.sumi
                        font.pixelSize: 15
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    MouseArea {
                        id: gearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            launcher.settingsMode = !launcher.settingsMode
                            searchInput.text = ""
                            launcher.filter()
                            searchInput.forceActiveFocus()
                        }
                    }
                }
            }

            // ── Unified app list (normal + settings mode) ──
            Item {
                id: appListArea
                width: parent.width
                height: Math.min(listCol.implicitHeight, 420)
                clip: true

                property real scrollOffset: 0

                MouseArea {
                    anchors.fill: parent
                    z: 5
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        var count = launcher.settingsMode ? launcher.settingsApps.length : launcher.filteredApps.length
                        var maxOff = Math.max(0, count * 46 - appListArea.height)
                        if (maxOff <= 0) return
                        appListArea.scrollOffset = Math.max(0, Math.min(appListArea.scrollOffset - wheel.angleDelta.y / 2, maxOff))
                    }
                }

                Rectangle {
                    id: keyHighlight
                    width: appListArea.width - 2; x: 1
                    height: 44
                    y: (!launcher.settingsMode && launcher.filteredApps.length > 0)
                        ? launcher.selectedIndex * 46 + 1 - appListArea.scrollOffset : -50
                    radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    border.color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.4)
                    border.width: 1
                    z: 1
                }

                Column {
                    id: listCol
                    width: appListArea.width
                    y: -appListArea.scrollOffset
                    spacing: 0

                        Repeater {
                            model: launcher.settingsMode ? launcher.settingsApps : launcher.filteredApps
                            delegate: Item {
                                required property var modelData
                                required property int index
                                width: listCol.width
                                height: 46

                                property bool isFav: launcher.favorites.indexOf(modelData.name) >= 0
                                property bool isHid: launcher.hiddenApps.indexOf(modelData.name) >= 0

                                Rectangle {
                                    anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                    radius: 4
                                    color: (!launcher.settingsMode && rowMa.containsMouse)
                                        ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                                        : "transparent"

                                    MouseArea {
                                        id: rowMa
                                        anchors.fill: parent
                                        enabled: !launcher.settingsMode
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: launcher.launch(modelData)
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left; anchors.leftMargin: 10
                                        spacing: 14

                                        Image {
                                            width: 24; height: 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: modelData.icon
                                            sourceSize: Qt.size(24, 24)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true; mipmap: true
                                            asynchronous: true
                                            opacity: (launcher.settingsMode && isHid) ? 0.3 : 1.0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            layer.enabled: root.launcherIconEffect === "gradient-tint"
                                            layer.effect: ShaderEffect {
                                                property color tintColor: root.launcherIconTint
                                                fragmentShader: Qt.resolvedUrl("../shaders/icon-gradient.frag.qsb")
                                            }
                                        }

                                        Text {
                                            text: modelData.name
                                            color: (launcher.settingsMode && isHid) ? root.sumi : root.ink
                                            font.family: root.mono; font.pixelSize: 13
                                            anchors.verticalCenter: parent.verticalCenter
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "★"
                                        color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.55)
                                        font.pixelSize: 11
                                        visible: !launcher.settingsMode && isFav
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        visible: launcher.settingsMode

                                        Item {
                                            width: 30; height: 30
                                            Rectangle {
                                                anchors.fill: parent; radius: 4
                                                color: favMa.containsMouse
                                                    ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18)
                                                    : "transparent"
                                                Behavior on color { ColorAnimation { duration: 80 } }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: isFav ? "★" : "☆"
                                                color: isFav ? root.seal : root.sumi
                                                font.pixelSize: 16
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            MouseArea {
                                                id: favMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: launcher.toggleFavorite(modelData.name)
                                            }
                                        }

                                        Item {
                                            width: 30; height: 30
                                            Rectangle {
                                                anchors.fill: parent; radius: 4
                                                color: hidMa.containsMouse
                                                    ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1)
                                                    : "transparent"
                                                Behavior on color { ColorAnimation { duration: 80 } }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: isHid ? "✕" : "●"
                                                color: isHid ? Qt.rgba(1.0, 0.38, 0.38, 0.9) : root.sumi
                                                font.pixelSize: isHid ? 13 : 9
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            MouseArea {
                                                id: hidMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: launcher.toggleHidden(modelData.name)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
            }

            // Settings mode hint footer
            Item {
                width: parent.width
                height: launcher.settingsMode ? 26 : 0
                clip: true

                Text {
                    anchors.centerIn: parent
                    text: "★ favorite   ● visible / ✕ hidden"
                    color: root.sumi
                    font.family: root.mono; font.pixelSize: 11
                    opacity: 0.55
                }
            }
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherVisible = !root.launcherVisible }
        function show(): void   { root.launcherVisible = true }
        function hide(): void   { root.launcherVisible = false }
        function reload(): void { appLoader.running = false; appLoader.running = true }
    }
}
