import QtQuick
import Quickshell.Networking
import Quickshell.Io

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
    property var savedProfiles: []
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

    // Classify the AP security so the panel can pick the right join flow. Collapsing every
    // non-open type to "psk" (as before) sent enterprise/WEP/OWE/unknown networks through the
    // inline passphrase prompt, which cannot actually authenticate them.
    function securityName(network) {
        if (!network)
            return "unknown"
        switch (network.security) {
        case WifiSecurityType.Open:
            return "open"
        case WifiSecurityType.WpaPsk:
        case WifiSecurityType.Wpa2Psk:
        case WifiSecurityType.Sae:          // WPA/WPA2/WPA3-Personal: a single passphrase
            return "psk"
        case WifiSecurityType.Owe:
            return "owe"                     // enhanced-open: no passphrase, needs NM to negotiate
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep:
            return "wep"                     // legacy key, not a wpa-psk secret
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Wpa3SuiteB192:
        case WifiSecurityType.Leap:
            return "enterprise"              // 802.1X: identity/cert, never a bare passphrase
        default:
            return "unknown"
        }
    }

    // Only WPA-Personal passphrase types can be joined via network.connectWithPsk(psk).
    // Everything else must go through the full NetworkManager settings flow.
    function supportsInlinePsk(sec) {
        return sec === "psk"
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
                sig: signalBars(network.signalStrength),
                visible: true,
                profileUuid: ""
            })
        }


        for (var p = 0; p < savedProfiles.length; p++) {
            var profile = savedProfiles[p]
            var represented = false
            for (var n = 0; n < nets.length; n++) {
                if (nets[n].ssid === profile.name) {
                    represented = true
                    if (!nets[n].known) {
                        nets[n].known = true
                        nets[n].profileUuid = profile.uuid
                    }
                    break
                }
            }
            if (!represented) {
                nets.push({
                    network: null,
                    conn: false,
                    known: true,
                    ssid: profile.name,
                    sec: "saved",
                    sig: 0,
                    visible: false,
                    profileUuid: profile.uuid
                })
            }
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
        if (!entry)
            return

        if (!entry.network && entry.profileUuid) {
            runProfileAction("connect", entry)
            return
        }
        if (!entry.network)
            return

        if (entry.sec === "open" || entry.known || entry.conn) {
            entry.network.connect()
            refreshAfterAction.restart()
            return
        }

        // Only WPA-Personal networks can be joined with an inline passphrase; enterprise, WEP,
        // OWE and unknown types would get an incorrect PSK prompt, so hand them to NM settings.
        if (supportsInlinePsk(entry.sec)) {
            if (panel && panel.root)
                panel.beginNmPassword(entry)
            return
        }

        if (panel) {
            panel.networkActionError = "This network type needs Wi-Fi settings to connect"
            if (typeof panel.openWifiSettings === "function")
                panel.openWifiSettings()
        }
    }

    function forgetNetwork(entry) {
        if (!entry || !entry.known)
            return
        if (entry.network && (entry.network.known || !entry.profileUuid)) {
            entry.network.forget()
            refreshAfterAction.restart()
        } else if (entry.profileUuid) {
            runProfileAction("forget", entry)
        }
    }

    function runProfileAction(action, entry) {
        if (!entry || !entry.profileUuid || profileAction.running)
            return
        if (panel)
            panel.networkActionError = ""
        profileAction.action = action
        profileAction.command = action === "connect"
            ? ["nmcli", "--wait", "20", "connection", "up", "uuid", entry.profileUuid]
            : ["nmcli", "--wait", "20", "connection", "delete", "uuid", entry.profileUuid]
        profileAction.running = true
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
        if (!profileList.running)
            profileList.running = true
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

    Process {
        id: profileList
        // Quickshell exposes saved settings only through currently visible
        // WifiNetwork objects. Query NetworkManager for the missing profiles,
        // using the actual 802.11 SSID rather than the editable connection id.
        command: ["bash", "-c",
            "nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do " +
            "case \"$type\" in 802-11-wireless|wifi) ;; *) continue ;; esac; " +
            "ssid=$(nmcli --escape no -g 802-11-wireless.ssid connection show uuid \"$uuid\" | head -n 1); " +
            "[ -n \"$ssid\" ] || continue; " +
            "printf '%s\\t%s\\n' \"$uuid\" \"$ssid\"; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var profiles = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i] === "")
                        continue
                    var fields = lines[i].split("\t")
                    if (fields.length >= 2)
                        profiles.push({ uuid: fields[0], name: fields.slice(1).join("\t") })
                }
                adapter.savedProfiles = profiles
                adapter.syncNetworks()
            }
        }
    }

    Process {
        id: profileAction
        property string action: ""
        stdout: StdioCollector { id: profileActionOut; waitForEnd: true }
        stderr: StdioCollector { id: profileActionErr; waitForEnd: true }
        onExited: function(exitCode) {
            if (exitCode !== 0 && adapter.panel) {
                var message = profileActionErr.text.trim()
                adapter.panel.networkActionError = message !== ""
                    ? message.split("\n")[0]
                    : (action === "connect" ? "Connection failed" : "Could not forget network")
            }
            profileList.running = false
            profileList.running = true
            refreshAfterAction.restart()
        }
    }

    Timer {
        id: refreshAfterAction
        interval: 1500
        onTriggered: adapter.refresh()
    }
}
