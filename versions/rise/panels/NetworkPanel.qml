import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: netPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-network"

    readonly property int barBottom: 37
    readonly property int gap: 8

    property string mode:  "none"   // wifi | ethernet | none
    property string ssid:  ""
    property int    signal: 0
    property string iface: ""
    property string ipAddr: ""
    property string freq:  ""

    property string wdev:   ""      // wifi device name (e.g. wlan0)
    property bool   hasWifi: false
    property bool   scanning: false
    property var    networks: []    // [{conn, ssid, sec, sig}]
    property var    known:   []     // known ssids

    function scan() {
        if (scanning) return
        scanning = true
        scanProc.running = false
        scanProc.running = true
    }

    function connectTo(ssid, sec) {
        var isKnown = known.indexOf(ssid) >= 0
        if (sec === "open" || isKnown) {
            connectProc.command = ["bash", "-c",
                "DEV=$(for d in /sys/class/net/*/wireless; do basename \"$(dirname \"$d\")\"; break; done); " +
                "iwctl station \"$DEV\" connect \"" + ssid.replace(/"/g, '') + "\" 2>/dev/null"]
            connectProc.running = false
            connectProc.running = true
            // re-scan shortly to reflect new connection
            rescanTimer.restart()
        } else {
            // unknown secured network — needs passphrase → open impala
            root.networkVisible = false
            wifiRunner.running = false
            wifiRunner.running = true
        }
    }

    property real reveal: root.networkVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.networkVisible ? 160 : 120
            easing.type: root.networkVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.networkVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.networkVisible = false }

    Rectangle {
        id: card
        width: 300
        height: col.implicitHeight + 24
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: parent.width - width - 6
        y: barBottom + gap
        opacity: netPanel.reveal
        focus: root.networkVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.networkVisible = false; event.accepted = true }
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
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Network"
                    color: root.ink; font.family: root.mono; font.pixelSize: 13
                    font.letterSpacing: 2; font.weight: Font.Medium
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: root.sumi; font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.networkVisible = false }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── status ──
            Item {
                width: parent.width
                height: 30
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: {
                        if (netPanel.mode === "wifi")     return netPanel.signal + "%"
                        if (netPanel.mode === "ethernet") return "Connected"
                        return "Offline"
                    }
                    color: netPanel.mode === "none" ? root.sumi : root.seal
                    font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 8; radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    Rectangle {
                        width: parent.width * (netPanel.mode === "wifi" ? netPanel.signal / 100 : (netPanel.mode === "ethernet" ? 1 : 0))
                        height: parent.height; radius: 4; color: root.seal
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // ── details ──
            Column {
                width: parent.width
                spacing: 4
                Row {
                    width: parent.width
                    visible: netPanel.mode === "wifi"
                    Text { text: "SSID"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: netPanel.ssid; color: root.ink; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.6; elide: Text.ElideRight }
                }
                Row {
                    width: parent.width
                    Text { text: "Type"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text {
                        text: netPanel.mode === "wifi" ? "Wi-Fi" : (netPanel.mode === "ethernet" ? "Ethernet" : "—")
                        color: root.ink; font.family: root.mono; font.pixelSize: 11
                    }
                }
                Row {
                    width: parent.width
                    visible: netPanel.iface !== ""
                    Text { text: "Interface"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: netPanel.iface; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: netPanel.ipAddr !== ""
                    Text { text: "IP"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: netPanel.ipAddr; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
                Row {
                    width: parent.width
                    visible: netPanel.mode === "wifi" && netPanel.freq !== ""
                    Text { text: "Frequency"; color: root.sumi; font.family: root.mono; font.pixelSize: 11; width: parent.width * 0.4 }
                    Text { text: netPanel.freq; color: root.ink; font.family: root.mono; font.pixelSize: 11 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep; visible: netPanel.hasWifi }

            // ── available networks ──
            Item {
                width: parent.width
                height: 16
                visible: netPanel.hasWifi
                Text {
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "AVAILABLE NETWORKS"
                    color: root.sumi; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: netPanel.scanning ? "scanning…" : "rescan"
                    color: root.seal; font.family: root.mono; font.pixelSize: 10
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: netPanel.scan() }
                }
            }

            // scrollable network list
            Flickable {
                width: parent.width
                height: Math.min(netList.implicitHeight, 180)
                contentHeight: netList.implicitHeight
                clip: true
                visible: netPanel.hasWifi
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: netList
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: netPanel.networks
                        delegate: Rectangle {
                            required property var modelData
                            width: netList.width
                            height: 30; radius: 4
                            color: modelData.conn ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                                                   : (nma.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06) : "transparent")
                            border.color: modelData.conn ? root.seal : "transparent"
                            border.width: modelData.conn ? 1 : 0

                            Row {
                                anchors.left: parent.left; anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    text: modelData.sec === "open" ? "\uE898" : "\uE897"
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 12
                                    color: root.sumi
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.ssid
                                    color: modelData.conn ? root.seal : root.ink
                                    font.family: root.mono; font.pixelSize: 11
                                    font.weight: modelData.conn ? Font.Medium : Font.Normal
                                    width: 170; elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // signal bars
                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater {
                                    model: 4
                                    delegate: Rectangle {
                                        required property int index
                                        width: 3; height: 4 + index * 2; radius: 1
                                        anchors.bottom: parent.bottom
                                        color: index < modelData.sig
                                            ? (modelData.conn ? root.seal : root.ink)
                                            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.18)
                                    }
                                }
                            }

                            MouseArea {
                                id: nma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: netPanel.connectTo(modelData.ssid, modelData.sec)
                            }
                        }
                    }

                    Text {
                        visible: !netPanel.scanning && netPanel.networks.length === 0
                        width: netList.width; horizontalAlignment: Text.AlignHCenter
                        text: "No networks found"
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
                        font.family: root.mono; font.pixelSize: 11
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── button ──
            Rectangle {
                width: parent.width
                height: 28; radius: 4; color: root.seal
                Text { anchors.centerIn: parent; text: "Network settings"; color: root.paper; font.family: root.mono; font.pixelSize: 11 }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { root.networkVisible = false; wifiRunner.running = false; wifiRunner.running = true }
                }
            }
        }
    }

    Process {
        id: netData
        command: ["bash", "-c",
            "IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"dev\"){print $(i+1); exit}}'); " +
            "if [ -z \"$IFACE\" ]; then echo NONE; exit; fi; " +
            "IPADDR=$(ip -o -4 addr show dev \"$IFACE\" 2>/dev/null | awk '{split($4,a,\"/\"); print a[1]; exit}'); " +
            "if [ -d \"/sys/class/net/$IFACE/wireless\" ]; then " +
            "  LINK=$(iw dev \"$IFACE\" link 2>/dev/null); " +
            "  SSID=$(printf '%s\\n' \"$LINK\" | sed -n 's/^\\s*SSID: //p' | head -1); " +
            "  SIG=$(printf '%s\\n' \"$LINK\" | awk '/signal:/ {print int($2); exit}'); " +
            "  FRQ=$(printf '%s\\n' \"$LINK\" | awk '/freq:/ {print $2 \" MHz\"; exit}'); " +
            "  QUAL=$(awk -v s=\"$SIG\" 'BEGIN{q=int((s+110)*100/70);if(q<0)q=0;if(q>100)q=100;print q}'); " +
            "  printf 'WIFI\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$SSID\" \"$QUAL\" \"$IFACE\" \"$IPADDR\" \"$FRQ\"; " +
            "else printf 'ETHERNET\\t%s\\t%s\\n' \"$IFACE\" \"$IPADDR\"; fi"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split("\t")
                if (parts[0] === "WIFI") {
                    netPanel.mode = "wifi"; netPanel.ssid = parts[1] || ""
                    netPanel.signal = parseInt(parts[2]) || 0; netPanel.iface = parts[3] || ""
                    netPanel.ipAddr = parts[4] || ""; netPanel.freq = parts[5] || ""
                } else if (parts[0] === "ETHERNET") {
                    netPanel.mode = "ethernet"; netPanel.iface = parts[1] || ""; netPanel.ipAddr = parts[2] || ""
                    netPanel.ssid = ""; netPanel.freq = ""
                } else {
                    netPanel.mode = "none"; netPanel.iface = ""; netPanel.ipAddr = ""; netPanel.ssid = ""
                }
            }
        }
    }

    Process { id: wifiRunner; command: ["bash", "-c", "omarchy-launch-wifi"] }

    // detect wifi device presence
    Process {
        id: devProbe
        command: ["bash", "-c", "for d in /sys/class/net/*/wireless; do basename \"$(dirname \"$d\")\"; break; done 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var d = this.text.trim()
                netPanel.wdev = d
                netPanel.hasWifi = d !== ""
                if (netPanel.hasWifi) netPanel.scan()
            }
        }
    }

    // scan + list available networks (and known networks)
    Process {
        id: scanProc
        command: ["bash", "-c",
            "DEV=$(for d in /sys/class/net/*/wireless; do basename \"$(dirname \"$d\")\"; break; done); " +
            "[ -z \"$DEV\" ] && exit; " +
            "rfkill unblock wifi 2>/dev/null; " +
            "iwctl station \"$DEV\" scan >/dev/null 2>&1; sleep 1.5; " +
            "iwctl known-networks list 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g; s/\\r//g' | " +
            "  awk '/^[[:space:]]*-+[[:space:]]*$/ {s++; next} s>=2 && NF>0 { sub(/^[[:space:]]+/,\"\"); sub(/[[:space:]][[:space:]]+.*$/,\"\"); if(length) print \"KNOWN\\t\" $0 }'; " +
            "iwctl station \"$DEV\" get-networks 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g; s/\\r//g' | " +
            "  awk '" +
            "    /^[[:space:]]*-+[[:space:]]*$/ { seps++; next } " +
            "    seps>=2 && NF>0 { " +
            "      line=$0; conn=0; " +
            "      if (line ~ /^[[:space:]]*>/) conn=1; " +
            "      sub(/^[[:space:]]*>?[[:space:]]*/, \"\", line); " +
            "      if (match(line, /[[:space:]]+(open|psk|8021x|wep)[[:space:]]+\\*+[[:space:]]*$/)) { " +
            "        tail=substr(line, RSTART); ssid=substr(line, 1, RSTART-1); " +
            "        gsub(/[[:space:]]+$/, \"\", ssid); " +
            "        n=split(tail, a, /[[:space:]]+/); sec=\"\"; sig=0; " +
            "        for(i=1;i<=n;i++){ if(a[i] ~ /^(open|psk|8021x|wep)$/) sec=a[i]; if(a[i] ~ /^\\*+$/) sig=length(a[i]) } " +
            "        print \"NET\\t\" conn \"\\t\" ssid \"\\t\" sec \"\\t\" sig " +
            "      } " +
            "    }'"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var nets = [], kn = []
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].split("\t")
                    if (p[0] === "KNOWN" && p[1]) {
                        kn.push(p[1].trim())
                    } else if (p[0] === "NET" && p.length >= 5) {
                        nets.push({ conn: p[1] === "1", ssid: p[2], sec: p[3], sig: parseInt(p[4]) || 0 })
                    }
                }
                // connected first, then by signal
                nets.sort(function(a, b) { return (b.conn - a.conn) || (b.sig - a.sig) })
                netPanel.networks = nets
                netPanel.known = kn
                netPanel.scanning = false
            }
        }
    }

    Process { id: connectProc; command: ["bash", "-c", "true"] }

    Timer { id: rescanTimer; interval: 1500; onTriggered: { netData.running = false; netData.running = true; netPanel.scan() } }

    onVisibleChanged: {
        if (visible) {
            netData.running = false; netData.running = true
            devProbe.running = false; devProbe.running = true
        }
    }
}
