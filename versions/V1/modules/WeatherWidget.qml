import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: rootMod
    required property var root

    property string weatherIcon: "·"
    property string weatherPlace: ""
    property string weatherTemp: ""
    property string weatherDesc: ""
    property bool weatherLoaded: false
    property bool weatherUnavailable: false

    readonly property string tooltipText: weatherUnavailable
        ? "Weather offline"
        : (weatherLoaded
            ? (weatherPlace ? weatherPlace + " · " : "") + weatherTemp + "°C" + (weatherDesc ? " / " + weatherDesc : "")
            : "Weather…")

    implicitWidth: ico.implicitWidth
    implicitHeight: 28

    Process {
        id: weatherProc
        running: false
        command: ["bash", "-c",
            "d=$(curl -fsS --max-time 5 'https://wttr.in?format=j1' 2>/dev/null); "
            + 'if [ -z "$d" ]; then echo "ERR"; exit; fi; '
            + 'echo "$d" | jq -r \'[.current_condition[0].weatherCode, .current_condition[0].temp_C, .current_condition[0].FeelsLikeC, .current_condition[0].weatherDesc[0].value, .nearest_area[0].areaName[0].value] | map(tostring) | join("|")\''
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim()
                if (txt === "ERR" || txt === "") {
                    rootMod.weatherUnavailable = true
                    rootMod.weatherLoaded = false
                    return
                }
                const p = txt.split("|")
                if (p.length < 5) {
                    rootMod.weatherUnavailable = true
                    rootMod.weatherLoaded = false
                    return
                }
                rootMod.weatherIcon = rootMod.glyphForCode(p[0])
                rootMod.weatherTemp = p[1]
                rootMod.weatherDesc = p[3]
                rootMod.weatherPlace = p[4]
                rootMod.weatherLoaded = true
                rootMod.weatherUnavailable = false
            }
        }
    }

    Timer {
        interval: 1800000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { weatherProc.running = false; weatherProc.running = true }
    }

    function glyphForCode(code) {
        const n = parseInt(code) || 0
        if (n === 113) return String.fromCodePoint(0xe30d)
        if (n === 116) return String.fromCodePoint(0xe302)
        if (n === 119 || n === 122) return String.fromCodePoint(0xe33d)
        if (n === 143 || n === 248 || n === 260) return String.fromCodePoint(0xe313)
        if (n === 176 || n === 263 || n === 353) return String.fromCodePoint(0xe308)
        if (n === 266 || n === 293 || n === 296) return String.fromCodePoint(0xe318)
        if (n === 179 || n === 227 || n === 230 || n === 323 || n === 326 || n === 368) return String.fromCodePoint(0xe30a)
        if (n === 182 || n === 185 || n === 281 || n === 284 || n === 311 || n === 314 || n === 317 || n === 320 || n === 350 || n === 362 || n === 365 || n === 374 || n === 377) return String.fromCodePoint(0xe3ad)
        if (n === 200 || n === 386 || n === 389 || n === 392 || n === 395) return String.fromCodePoint(0xe31d)
        if (n === 329 || n === 332 || n === 335 || n === 338 || n === 371) return String.fromCodePoint(0xe31a)
        return String.fromCodePoint(0xe33d)
    }

    Text {
        id: ico
        anchors.centerIn: parent
        text: rootMod.weatherUnavailable ? "?"
              : (rootMod.weatherLoaded ? rootMod.weatherIcon : "·")
        color: rootMod.weatherUnavailable
               ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
               : root.ink
        font.family: root.mono
        font.pixelSize: 14
    }

    Process {
        id: clickRunner
        command: ["bash", "-c", "notify-send -u low \"$(omarchy-weather-status)\""]
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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: { if (rootMod.tooltipText) tipDelay.restart(); }
        onExited: { tipDelay.stop(); root.hideTooltip(rootMod); }
        onClicked: (e) => {
            tipDelay.stop();
            root.hideTooltip(rootMod);
            if (e.button === Qt.RightButton) {
                weatherProc.running = false;
                weatherProc.running = true;
            } else {
                root.weatherVisible = !root.weatherVisible;
            }
        }
    }
}
