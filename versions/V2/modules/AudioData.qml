import QtQuick
import Quickshell.Io

// Shared default-sink probe: volume / muted / output-port type.
// Used by AudioWidget (poll: true → refresh every `interval`) and by
// VolumePanel (on-demand via refresh() when it opens). Centralizes the
// pactl command + parsing that previously lived duplicated in both files.
Item {
    id: audio

    property bool poll:     false   // auto-refresh on a timer when true
    property int  interval: 3000

    property int    volume:   50
    property bool   muted:    false
    property string portType: "default"

    function refresh() { proc.lines = []; proc.running = false; proc.running = true }

    Process {
        id: proc
        running: false
        command: ["bash", "-c",
            "export LC_ALL=C; " +
            "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '[0-9]+(?=%)' | head -1; " +
            "pactl get-sink-mute   @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}'; " +
            "pactl list sinks 2>/dev/null | grep -A80 \"Name: $(pactl get-default-sink)\" | grep 'Active Port' | awk '{print $NF}'"
        ]
        stdout: SplitParser {
            onRead: function(line) { proc.lines.push(line.trim()) }
        }
        onExited: {
            if (proc.lines.length >= 2) {
                audio.volume = parseInt(proc.lines[0]) || 0
                audio.muted  = (proc.lines[1] === "yes")
                var port = proc.lines[2] || ""
                if (port.includes("headphone"))    audio.portType = "headphone"
                else if (port.includes("headset")) audio.portType = "headset"
                else                               audio.portType = "default"
            }
            proc.lines = []
        }
        property var lines: []
    }

    Timer {
        interval: audio.interval; running: audio.poll; repeat: true; triggeredOnStart: true
        onTriggered: audio.refresh()
    }
}
