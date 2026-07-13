import QtQuick
import "../modules"
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import "../IconMap.js" as IconMap

PanelWindow {
    id: btPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-bluetooth"

    readonly property int barBottom: 35
    readonly property int gap: 8

    // ── Bluetooth via Quickshell.Bluetooth (native BlueZ service) ──────────
    // Replaces the old bluetoothctl-per-device approach and the temporary BlueZ
    // ObjectManager helper: power, discovery, pairing, connection and per-device
    // state all come from the declarative service.
    //   • adapter = Bluetooth.defaultAdapter → power (adapter.enabled) and
    //     discovery (adapter.discovering).
    //   • Bluetooth.devices.values           → mapped into `devices` view rows
    //     (name/mac/connected/paired/battery/icon), sorted connected→paired→rest.
    // The service is event-driven (fire-and-forget calls + model updates), so
    // progress/completion are tracked by watching device state via
    // onDevicesChanged → syncBusyState(), not through callbacks.

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter !== null && adapter.enabled
    readonly property bool scanning: adapter !== null && adapter.discovering
    readonly property var nativeDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var devices: {
        var rows = []
        for (var i = 0; i < nativeDevices.length; i++) {
            var device = nativeDevices[i]
            if (!device || !device.address)
                continue
            rows.push({
                ref: device,
                name: device.name || device.deviceName || device.address,
                mac: device.address,
                connected: !!device.connected,
                paired: !!(device.paired || device.bonded || device.trusted),
                icon: device.icon || "",
                rssi: null,
                battery: device.batteryAvailable ? Math.round(device.battery * 100) : -1
            })
        }
        rows.sort(function(a, b) {
            var ra = a.connected ? 0 : a.paired ? 1 : 2
            var rb = b.connected ? 0 : b.paired ? 1 : 2
            if (ra !== rb) return ra - rb
            return a.name.localeCompare(b.name)
        })
        return rows
    }
    property bool savedOnly: false
    property string selectedMac: ""
    property int keyboardIndex: -1
    property string busyMac: ""
    property string busyLabel: ""
    readonly property var savedDevices: devices.filter(function(device) {
        return device.paired || device.connected
    })
    readonly property var shownDevices: (savedOnly ? savedDevices : devices).slice(0, 12)
    readonly property int numConnected: {
        var n = 0
        for (var i = 0; i < devices.length; i++) if (devices[i].connected) n++
        return n
    }
    // One-tap action keyed on current state: connected → disconnect;
    // paired → trust + connect; new → trust + pair (syncBusyState then
    // auto-connects once pairing lands). busyMac/busyLabel drive the row label.
    function activateDevice(device) {
        if (!device || !device.ref)
            return

        if (device.connected) {
            busyLabel = "Disconnecting…"
            device.ref.disconnect()
        } else if (device.paired) {
            busyLabel = "Connecting…"
            device.ref.trusted = true
            device.ref.connect()
        } else {
            busyLabel = "Pairing…"
            device.ref.trusted = true
            device.ref.pair()
        }
        busyMac = device.mac
        busyTimeout.restart()
    }

    function forgetDevice(device) {
        if (!device || !device.ref)
            return
        selectedMac = ""
        busyMac = device.mac
        busyLabel = "Forgetting…"
        device.ref.forget()
        busyTimeout.restart()
    }

    // Event-driven progress tracker (the native API has no completion
    // callbacks): runs on every onDevicesChanged. Advances Pairing… →
    // Connecting… once the device reports paired, and clears the busy state
    // when the pending op is observed complete (connected / disconnected / no
    // longer paired). busyTimeout is the safety net if the transition never lands.
    function syncBusyState() {
        if (busyMac === "")
            return
        var device = null
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].mac === busyMac) {
                device = devices[i]
                break
            }
        }
        if (busyLabel === "Pairing…" && device && device.paired && !device.connected) {
            busyLabel = "Connecting…"
            device.ref.connect()
            busyTimeout.restart()
            return
        }
        var finished = (busyLabel === "Connecting…" && device && device.connected)
            || (busyLabel === "Disconnecting…" && device && !device.connected)
            || (busyLabel === "Forgetting…" && (!device || !device.paired))
        if (finished) {
            busyMac = ""
            busyLabel = ""
            busyTimeout.stop()
        }
    }

    onDevicesChanged: syncBusyState()

    onSavedOnlyChanged: {
        keyboardIndex = -1
        selectedMac = ""
    }

    property real reveal: root.bluetoothVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.bluetoothVisible ? 160 : 120
            easing.type: root.bluetoothVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.bluetoothVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.bluetoothVisible = false }

    Rectangle {
        id: card
        width: 300
        height: col.implicitHeight + 24
        radius: reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.bluetoothBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
        opacity: btPanel.reveal
        focus: root.bluetoothVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (btPanel.selectedMac !== "")
                    btPanel.selectedMac = ""
                else
                    root.bluetoothVisible = false
                event.accepted = true
                return
            }

            var entries = btPanel.shownDevices
            if (!btPanel.btOn || entries.length === 0)
                return

            if (event.key === Qt.Key_Down) {
                btPanel.keyboardIndex = (btPanel.keyboardIndex + 1) % entries.length
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                btPanel.keyboardIndex = btPanel.keyboardIndex <= 0
                    ? entries.length - 1 : btPanel.keyboardIndex - 1
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                if (btPanel.keyboardIndex >= 0)
                    btPanel.selectedMac = entries[btPanel.keyboardIndex].mac
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                btPanel.selectedMac = ""
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (btPanel.keyboardIndex >= 0)
                    btPanel.activateDevice(entries[btPanel.keyboardIndex])
                event.accepted = true
            }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // ── header + power toggle ──
            Item {
                width: parent.width
                height: 24
                Row {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        color: root.ink; font.family: root.mono; font.pixelSize: 13
                        font.letterSpacing: 2; font.weight: Font.Medium
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: btPanel.btOn && btPanel.numConnected > 0
                        spacing: 3
                        IconText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: IconMap.icon("bluetooth_connected")
                            color: root.seal
                            font.pixelSize: 13
                        }
                        UiText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(btPanel.numConnected)
                            color: root.seal
                            font.family: root.mono; font.pixelSize: 11
                        }
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    // power toggle pill
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46; height: 20; radius: 10
                        color: btPanel.btOn ? root.fillActive
                                            : root.fillIdle
                        border.color: btPanel.btOn ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: 14; height: 14; radius: 7
                            anchors.verticalCenter: parent.verticalCenter
                            x: btPanel.btOn ? parent.width - width - 3 : 3
                            color: btPanel.btOn ? root.seal : root.sumi
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (btPanel.adapter) btPanel.adapter.enabled = !btPanel.adapter.enabled
                        }
                    }
                    UiText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✕"; color: closeMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 12
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.bluetoothVisible = false }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── off state ──
            UiText {
                visible: !btPanel.btOn
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Bluetooth is off"
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
                font.family: root.mono; font.pixelSize: 11
                topPadding: 4; bottomPadding: 4
            }

            Row {
                visible: btPanel.btOn
                width: parent.width
                height: 28
                spacing: 6

                Repeater {
                    model: [
                        { label: btPanel.scanning ? "Discovering…" : "Discover", saved: false },
                        { label: "Saved" + (btPanel.savedDevices.length > 0 ? " (" + btPanel.savedDevices.length + ")" : ""), saved: true }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 6) / 2
                        height: 28
                        radius: root.tileRadius
                        readonly property bool active: btPanel.savedOnly === modelData.saved
                        color: active ? root.fillActive : btTabMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: active || btTabMa.containsMouse ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.active ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 10
                        }
                        MouseArea {
                            id: btTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                btPanel.savedOnly = modelData.saved
                                if (!modelData.saved && btPanel.adapter) {
                                    btPanel.adapter.discovering = true
                                    scanTimeout.restart()
                                }
                            }
                        }
                    }
                }
            }

            // ── device list ──
            Column {
                width: parent.width
                spacing: 4
                visible: btPanel.btOn
                Repeater {
                    model: btPanel.shownDevices
                    delegate: Column {
                        id: devTile
                        required property var modelData
                        required property int index
                        width: col.width
                        spacing: 4
                        readonly property bool expanded: btPanel.selectedMac === modelData.mac
                        readonly property bool keyboardSelected: btPanel.keyboardIndex === index

                        Rectangle {
                            width: parent.width
                            height: 30
                            radius: root.tileRadius
                            readonly property bool active: devMa.containsMouse || devTile.expanded || devTile.keyboardSelected
                            color: modelData.connected ? root.fillActive : active ? root.fillHover : root.fillIdle
                            border.color: modelData.connected || active ? root.seal : root.sep
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }

                            IconText {
                                id: deviceTypeIcon
                                anchors.left: parent.left; anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: IconMap.btTypeIcon(modelData.icon)
                                color: modelData.connected ? root.seal : root.sumiHi
                                font.pixelSize: 14
                            }
                            UiText {
                                anchors.left: deviceTypeIcon.right; anchors.leftMargin: 7
                                anchors.right: deviceState.left; anchors.rightMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: modelData.connected || devMa.containsMouse ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                            UiText {
                                id: deviceState
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: btPanel.busyMac === modelData.mac ? btPanel.busyLabel
                                    : modelData.connected ? "Connected"
                                    : modelData.paired ? "Paired" : "Connect"
                                color: btPanel.busyMac === modelData.mac || modelData.connected ? root.seal : root.sumiHi
                                font.family: root.mono; font.pixelSize: 9
                            }
                            MouseArea {
                                id: devMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: btPanel.keyboardIndex = devTile.index
                                onClicked: btPanel.selectedMac = devTile.expanded ? "" : modelData.mac
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: devTile.expanded ? deviceDetails.implicitHeight + 16 : 0
                            visible: height > 0
                            clip: true
                            radius: root.tileRadius
                            color: root.fillIdle
                            border.color: root.sep
                            border.width: devTile.expanded ? 1 : 0
                            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Column {
                                id: deviceDetails
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6

                                UiText {
                                    text: "UID  " + modelData.mac
                                    color: root.sumiHi
                                    font.family: root.mono; font.pixelSize: 10
                                }
                                Row {
                                    spacing: 12
                                    visible: modelData.rssi !== null || modelData.battery >= 0
                                    UiText {
                                        visible: modelData.rssi !== null
                                        text: "Signal " + modelData.rssi + " dBm"
                                        color: root.sumiHi
                                        font.family: root.mono; font.pixelSize: 10
                                    }
                                    UiText {
                                        visible: modelData.battery >= 0
                                        text: "Battery " + modelData.battery + "%"
                                        color: root.seal
                                        font.family: root.mono; font.pixelSize: 10
                                    }
                                }
                                Row {
                                    width: parent.width
                                    height: 26
                                    spacing: 6

                                    Rectangle {
                                        width: (parent.width - 6) / 2
                                        height: parent.height
                                        radius: root.tileRadius
                                        color: btActionMa.containsMouse ? root.fillHover : root.fillIdle
                                        border.color: btActionMa.containsMouse ? root.seal : root.sep
                                        border.width: 1
                                        UiText {
                                            anchors.centerIn: parent
                                            text: modelData.connected ? "Disconnect" : modelData.paired ? "Reconnect" : "Connect"
                                            color: root.ink
                                            font.family: root.mono; font.pixelSize: 10
                                        }
                                        MouseArea {
                                            id: btActionMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: btPanel.activateDevice(modelData)
                                        }
                                    }
                                    Rectangle {
                                        width: (parent.width - 6) / 2
                                        height: parent.height
                                        radius: root.tileRadius
                                        color: btForgetMa.containsMouse ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18) : root.fillIdle
                                        border.color: btForgetMa.containsMouse ? root.seal : root.sep
                                        border.width: 1
                                        UiText {
                                            anchors.centerIn: parent
                                            text: "Forget"
                                            color: btForgetMa.containsMouse ? root.seal : root.ink
                                            font.family: root.mono; font.pixelSize: 10
                                        }
                                        MouseArea {
                                            id: btForgetMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: btPanel.forgetDevice(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                UiText {
                    visible: btPanel.btOn && btPanel.shownDevices.length === 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: btPanel.savedOnly ? "No saved devices"
                        : btPanel.scanning ? "Searching…" : "No devices — tap Discover"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                    font.family: root.mono; font.pixelSize: 11
                    topPadding: 2; bottomPadding: 2
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            Rectangle {
                width: parent.width
                height: 28; radius: root.tileRadius
                color: btSetMa.containsMouse ? root.fillPrimaryHover : root.seal
                Behavior on color { ColorAnimation { duration: 120 } }
                UiText { anchors.centerIn: parent; text: "Bluetooth settings"; color: root.paper; font.family: root.mono; font.pixelSize: 11 }
                MouseArea {
                    id: btSetMa
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { root.bluetoothVisible = false; btRunner.running = false; btRunner.running = true }
                }
            }
        }
    }

    Timer {
        id: scanTimeout
        interval: 10000
        onTriggered: if (btPanel.adapter) btPanel.adapter.discovering = false
    }

    Timer {
        id: busyTimeout
        interval: 8000
        onTriggered: {
            btPanel.busyMac = ""
            btPanel.busyLabel = ""
        }
    }

    Process { id: btRunner; command: ["bash", "-c", root.launchBtCmd] }

    onVisibleChanged: {
        keyboardIndex = -1
        if (!visible) selectedMac = ""
    }
}
