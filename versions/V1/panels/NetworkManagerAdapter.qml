import QtQuick
import Quickshell.Networking

Item {
    id: adapter

    property var panel: null
    property bool panelOpen: false

    readonly property bool backendAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property bool available: backendAvailable && wifiDevice !== null
    readonly property bool wifiBlocked: !Networking.wifiEnabled

    property var networks: []
    property bool scanning: false

    function findDevice(type) {
        var devices = networkDevices || []
        for (var i = 0; i < devices.length; i++) {
            if (devices[i] && devices[i].type === type)
                return devices[i]
        }
        return null
    }

    function signalBars(strength) {
        var percent = Math.max(0, Math.min(100, Math.round((strength || 0) * 100)))
        if (percent <= 0)
            return 0
        return Math.max(1, Math.min(4, Math.ceil(percent / 25)))
    }

    function securityName(network) {
        return network && network.security === WifiSecurityType.Open ? "open" : "psk"
    }

    function syncNetworks() {
        var nets = []
        var objects = wifiNetworkObjects || []
        for (var i = 0; i < objects.length; i++) {
            var network = objects[i]
            if (!network)
                continue

            nets.push({
                network: network,
                conn: !!network.connected,
                known: !!network.known,
                ssid: network.name || "",
                sec: securityName(network),
                sig: signalBars(network.signalStrength)
            })
        }

        nets.sort(function(a, b) {
            if (a.conn !== b.conn)
                return a.conn ? -1 : 1
            if (a.known !== b.known)
                return a.known ? -1 : 1
            return b.sig - a.sig
        })
        networks = nets
        syncPanel()
    }

    function syncPanel() {
        if (!panel)
            return

        panel.hasWifi = wifiDevice !== null
        panel.wifiBlocked = wifiBlocked
        panel.scanning = scanning
        panel.networks = networks
        panel.known = []
    }

    function scan() {
        if (!available || wifiBlocked)
            return

        scanning = true
        if (wifiDevice)
            wifiDevice.scannerEnabled = true
        scanClearTimer.restart()
        syncNetworks()
    }

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled
        syncPanel()
        if (Networking.wifiEnabled)
            scan()
    }

    function connectTo(entry) {
        if (!entry || !entry.network)
            return

        if (entry.sec === "open" || entry.known || entry.conn) {
            entry.network.connect()
            refreshAfterAction.restart()
            return
        }

        if (panel && panel.root) {
            panel.beginNmPassword(entry)
        }
    }

    function connectWithPsk(network, psk) {
        if (!network || psk === "")
            return

        network.connectWithPsk(psk)
        refreshAfterAction.restart()
    }

    function refresh() {
        if (wifiDevice)
            wifiDevice.scannerEnabled = panelOpen && !wifiBlocked
        syncNetworks()
    }

    onPanelOpenChanged: refresh()
    onNetworkDevicesChanged: refresh()
    onWifiDeviceChanged: refresh()
    onWifiNetworkObjectsChanged: syncNetworks()
    onWifiBlockedChanged: refresh()
    onAvailableChanged: refresh()

    Component.onCompleted: refresh()
    Component.onDestruction: {
        if (wifiDevice)
            wifiDevice.scannerEnabled = false
    }

    Timer {
        id: scanClearTimer
        interval: 1600
        onTriggered: {
            adapter.scanning = false
            adapter.syncPanel()
        }
    }

    Timer {
        id: refreshAfterAction
        interval: 1500
        onTriggered: adapter.refresh()
    }
}
