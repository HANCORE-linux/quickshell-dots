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

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter !== null && adapter.enabled
    readonly property bool scanning: adapter !== null && adapter.discovering
    // Keep discovery and device ownership tied to the adapter shown by this
    // panel. The global Bluetooth.devices model may include another adapter.
    readonly property var nativeDevices: adapter && adapter.devices ? adapter.devices.values : []
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
    property var pairDevice: null
    property string pairOutput: ""
    property string pairPromptMode: "" // "pin" | "confirm"
    property string pairPromptText: ""
    property string pairPin: ""
    property string actionError: ""
    property bool pairTimedOut: false
    readonly property var savedDevices: devices.filter(function(device) {
        return device.paired || device.connected
    })
    readonly property var shownDevices: savedOnly ? savedDevices : devices
    readonly property int numConnected: {
        var n = 0
        for (var i = 0; i < devices.length; i++) if (devices[i].connected) n++
        return n
    }
    function activateDevice(device) {
        if (!device || !device.ref)
            return

        actionError = ""
        pairPromptMode = ""
        pairPromptText = ""
        if (device.connected) {
            busyLabel = "Disconnecting…"
            device.ref.disconnect()
        } else if (device.paired) {
            busyLabel = "Connecting…"
            device.ref.trusted = true
            device.ref.connect()
        } else {
            busyLabel = "Pairing…"
            startPairing(device)
            return
        }
        busyMac = device.mac
        busyTimeout.restart()
    }

    function startPairing(device) {
        if (!device || !device.ref || pairProc.running)
            return
        pairDevice = device.ref
        pairOutput = ""
        pairPin = ""
        pairPromptMode = ""
        pairPromptText = ""
        pairTimedOut = false
        actionError = ""
        busyMac = device.mac
        busyLabel = "Pairing…"
        selectedMac = device.mac
        pairProc.command = ["bluetoothctl", "--agent", "KeyboardOnly", "--timeout", "35", "pair", device.mac]
        pairProc.running = true
        pairTimeout.restart()
    }

    function cleanPairOutput(chunk) {
        return String(chunk || "").replace(/\x1b\[[0-9;?]*[ -/]*[@-~]/g, "")
    }

    function handlePairOutput(chunk) {
        var clean = cleanPairOutput(chunk)
        pairOutput = (pairOutput + clean).slice(-4096)
        var confirm = pairOutput.match(/Confirm passkey\s+([0-9]+)/i)
        if (confirm) {
            pairPromptMode = "confirm"
            pairPromptText = "Confirm passkey " + confirm[1]
            busyLabel = "Confirmation required"
            return
        }
        if (/Enter (PIN code|passkey)/i.test(pairOutput)) {
            pairPromptMode = "pin"
            pairPromptText = "Enter the PIN shown by the device"
            busyLabel = "PIN required"
        }
        var failure = pairOutput.match(/Failed to pair:\s*([^\r\n]+)/i)
            || pairOutput.match(/(AuthenticationFailed|AuthenticationCanceled|AuthenticationRejected|ConnectionAttemptFailed)/i)
        if (failure)
            actionError = failure[1].replace(/^org\.bluez\.Error\./, "")
    }

    function answerPairing(answer) {
        if (!pairProc.running)
            return
        pairProc.write(String(answer) + "\n")
        pairPromptMode = ""
        pairPromptText = ""
        pairPin = ""
        busyLabel = "Pairing…"
    }

    function cancelPairing() {
        if (pairProc.running) {
            pairProc.write("no\n")
            pairProc.running = false
        }
        if (pairDevice && pairDevice.pairing)
            pairDevice.cancelPair()
        pairTimeout.stop()
        pairPromptMode = ""
        pairPromptText = ""
        busyLabel = ""
        busyMac = ""
        pairDevice = null
    }

    function forgetDevice(device) {
        if (!device || !device.ref)
            return
        selectedMac = ""
        busyMac = device.mac
        busyLabel = "Forgetting…"
        actionError = ""
        device.ref.forget()
        busyTimeout.restart()
    }

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
        var finished = (busyLabel === "Connecting…" && device && device.connected)
            || (busyLabel === "Disconnecting…" && device && !device.connected)
            || (busyLabel === "Forgetting…" && (!device || !device.paired))
        if (finished) {
            busyMac = ""
            busyLabel = ""
            busyTimeout.stop()
        }
    }

    function ensureKeyboardDeviceVisible() {
        if (keyboardIndex < 0 || keyboardIndex >= deviceRepeater.count)
            return
        var item = deviceRepeater.itemAt(keyboardIndex)
        if (!item)
            return
        var top = item.y
        var bottom = top + item.height
        if (top < deviceFlick.contentY)
            deviceFlick.contentY = top
        else if (bottom > deviceFlick.contentY + deviceFlick.height)
            deviceFlick.contentY = Math.min(deviceFlick.contentHeight - deviceFlick.height,
                                           bottom - deviceFlick.height)
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
                if (pairProc.running)
                    btPanel.cancelPairing()
                else if (btPanel.selectedMac !== "")
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
                Qt.callLater(btPanel.ensureKeyboardDeviceVisible)
                event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                btPanel.keyboardIndex = btPanel.keyboardIndex <= 0
                    ? entries.length - 1 : btPanel.keyboardIndex - 1
                Qt.callLater(btPanel.ensureKeyboardDeviceVisible)
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
            Flickable {
                id: deviceFlick
                width: parent.width
                height: Math.min(deviceList.implicitHeight, 280)
                contentHeight: deviceList.implicitHeight
                visible: btPanel.btOn
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: deviceList
                    width: deviceFlick.width
                    spacing: 4

                    Repeater {
                        id: deviceRepeater
                        model: btPanel.shownDevices
                        delegate: Column {
                        id: devTile
                        required property var modelData
                        required property int index
                        width: deviceList.width
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
                                UiText {
                                    visible: btPanel.busyMac === modelData.mac && btPanel.actionError !== ""
                                    width: parent.width
                                    text: btPanel.actionError
                                    color: root.seal
                                    wrapMode: Text.Wrap
                                    font.family: root.mono; font.pixelSize: 10
                                }
                                UiText {
                                    visible: btPanel.busyMac === modelData.mac && btPanel.pairPromptMode !== ""
                                    width: parent.width
                                    text: btPanel.pairPromptText
                                    color: root.seal
                                    wrapMode: Text.Wrap
                                    font.family: root.mono; font.pixelSize: 10
                                }
                                Row {
                                    id: pinPromptRow
                                    visible: btPanel.busyMac === modelData.mac && btPanel.pairPromptMode === "pin"
                                    width: parent.width
                                    height: visible ? 26 : 0
                                    spacing: 6

                                    Rectangle {
                                        width: parent.width * 0.66
                                        height: parent.height
                                        radius: root.tileRadius
                                        color: root.fillIdle
                                        border.color: pinInput.activeFocus ? root.seal : root.sep
                                        border.width: 1
                                        TextInput {
                                            id: pinInput
                                            anchors.fill: parent
                                            anchors.leftMargin: 7; anchors.rightMargin: 7
                                            verticalAlignment: TextInput.AlignVCenter
                                            color: root.ink
                                            font.family: root.mono; font.pixelSize: 11
                                            inputMethodHints: Qt.ImhDigitsOnly
                                            onTextChanged: btPanel.pairPin = text
                                            Keys.onReturnPressed: if (text !== "") btPanel.answerPairing(text)
                                        }
                                    }
                                    Rectangle {
                                        width: parent.width - pinInput.parent.width - 6
                                        height: parent.height
                                        radius: root.tileRadius
                                        color: btPanel.pairPin !== "" ? root.seal : root.fillIdle
                                        border.color: btPanel.pairPin !== "" ? root.seal : root.sep
                                        border.width: 1
                                        UiText {
                                            anchors.centerIn: parent
                                            text: "Send"
                                            color: btPanel.pairPin !== "" ? root.paper : root.sumi
                                            font.family: root.mono; font.pixelSize: 10
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: btPanel.pairPin !== ""
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: btPanel.answerPairing(btPanel.pairPin)
                                        }
                                    }
                                    onVisibleChanged: if (visible)
                                        Qt.callLater(function() { pinInput.forceActiveFocus() })
                                }
                                Row {
                                    visible: btPanel.busyMac === modelData.mac && btPanel.pairPromptMode === "confirm"
                                    width: parent.width
                                    height: visible ? 26 : 0
                                    spacing: 6

                                    Repeater {
                                        model: [
                                            { label: "Confirm", answer: "yes", primary: true },
                                            { label: "Reject", answer: "no", primary: false }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: (parent.width - 6) / 2
                                            height: parent.height
                                            radius: root.tileRadius
                                            color: modelData.primary ? root.seal : root.fillIdle
                                            border.color: modelData.primary ? root.seal : root.sep
                                            border.width: 1
                                            UiText {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: modelData.primary ? root.paper : root.ink
                                                font.family: root.mono; font.pixelSize: 10
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: btPanel.answerPairing(modelData.answer)
                                            }
                                        }
                                    }
                                }
                                Row {
                                    width: parent.width
                                    height: 26
                                    spacing: 6
                                    visible: !(btPanel.busyMac === modelData.mac && btPanel.pairPromptMode !== "")

                                    Rectangle {
                                        width: modelData.paired ? (parent.width - 6) / 2 : parent.width
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
                                        visible: modelData.paired
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
            btPanel.actionError = btPanel.busyLabel.replace("…", "") + " timed out"
            btPanel.busyLabel = "Timed out"
        }
    }

    Timer {
        id: pairTimeout
        interval: 37000
        onTriggered: {
            btPanel.pairTimedOut = true
            btPanel.actionError = "Pairing timed out"
            btPanel.busyLabel = "Timed out"
            btPanel.pairPromptMode = ""
            btPanel.pairPromptText = ""
            if (pairProc.running)
                pairProc.running = false
            if (btPanel.pairDevice && btPanel.pairDevice.pairing)
                btPanel.pairDevice.cancelPair()
        }
    }

    Process {
        id: pairProc
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { btPanel.handlePairOutput(data) }
        }
        stderr: SplitParser {
            splitMarker: ""
            onRead: function(data) { btPanel.handlePairOutput(data) }
        }
        onExited: function(exitCode) {
            pairTimeout.stop()
            if (btPanel.pairTimedOut) {
                btPanel.actionError = "Pairing timed out"
                btPanel.busyLabel = "Timed out"
            } else if (exitCode !== 0 || btPanel.actionError !== "") {
                if (btPanel.actionError === "")
                    btPanel.actionError = "Pairing failed"
                btPanel.busyLabel = "Failed"
            } else {
                var pairedDevice = btPanel.pairDevice
                if (pairedDevice) {
                    pairedDevice.trusted = true
                    pairedDevice.connect()
                }
                btPanel.busyLabel = "Connecting…"
                busyTimeout.restart()
            }
            btPanel.pairPromptMode = ""
            btPanel.pairPromptText = ""
            btPanel.pairPin = ""
            btPanel.pairDevice = null
        }
    }

    Process { id: btRunner; command: ["bash", "-c", root.launchBtCmd] }

    onVisibleChanged: {
        keyboardIndex = -1
        if (!visible) {
            selectedMac = ""
            if (pairProc.running)
                cancelPairing()
        }
    }
}
