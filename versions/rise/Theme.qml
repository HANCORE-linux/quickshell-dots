import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

Item {
    id: theme

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"

    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color sealRaw: "#c4746e"

    readonly property color seal: sealRaw

    readonly property string mono:  "JetBrainsMono Nerd Font"

    // ── transparency knobs (0.0 = fully transparent, 1.0 = opaque) ──
    property real barOpacity:  0.94   // große Insel / Split-Sektionen
    property real pillOpacity: 0.45   // einzelne Widget-Pillen (workspace, mem, cpu, …)

    readonly property color bg:     Qt.rgba(paper.r, paper.g, paper.b, barOpacity)
    readonly property color pill:   Qt.rgba(paper.r, paper.g, paper.b, pillOpacity)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color accent: seal
    readonly property color warn:   seal
    readonly property color sep:    Qt.rgba(ink.r, ink.g, ink.b, 0.18)

    property string lastAppliedName: ""

    // ── Tooltip state ──
    property string tooltipText: ""
    property real tooltipX: 0
    property real tooltipY: 0
    property bool tooltipShown: false
    property var tooltipOwner: null   // the widget currently owning the tooltip

    function showTooltip(text, x, y, owner) {
        if (!text) return;
        tooltipText = text;
        tooltipX = x;
        tooltipY = y;
        tooltipOwner = owner !== undefined ? owner : null;
        tooltipShown = true;
    }

    // hide only if the caller owns the current tooltip (owner match is stable
    // even when the tooltip text changes, e.g. a live timer). A null/undefined
    // owner force-hides. Legacy string args fall back to a text match.
    function hideTooltip(owner) {
        if (owner === undefined || owner === null) {
            tooltipShown = false; tooltipOwner = null;
        } else if (typeof owner === "object") {
            if (tooltipOwner === owner) { tooltipShown = false; tooltipOwner = null; }
        } else if (tooltipText === owner) {
            tooltipShown = false; tooltipOwner = null;
        }
    }

    // safety net: if the owning widget disappears while its tooltip is shown
    // (e.g. ScreenRecord stops mid-hover, so onExited never fires), force-hide.
    readonly property bool _tooltipOwnerVisible: tooltipOwner ? tooltipOwner.visible : true
    on_TooltipOwnerVisibleChanged: if (!_tooltipOwnerVisible) { tooltipShown = false; tooltipOwner = null; }

    // ── Calendar state ──
    property bool calendarVisible: false
    property int calendarMonthOffset: 0
    property int calendarTick: 0
    property int selectedDay: 0

    readonly property var calendarCells: {
        calendarTick;
        const now = new Date();
        const first = new Date(now.getFullYear(), now.getMonth() + calendarMonthOffset, 1);
        const year = first.getFullYear();
        const month = first.getMonth();
        const lastDay = new Date(year, month + 1, 0).getDate();
        const startDay = (first.getDay() + 6) % 7;
        const today = new Date();
        const isCurrentMonth = year === today.getFullYear() && month === today.getMonth();
        const cells = [];
        for (let i = 0; i < startDay; i++) cells.push({day: 0, today: false});
        for (let d = 1; d <= lastDay; d++) {
            cells.push({day: d, today: isCurrentMonth && d === today.getDate()});
        }
        while (cells.length < 42) cells.push({day: 0, today: false});
        return cells;
    }

    readonly property string calendarMonthName: {
        const months = ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                        "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"];
        const now = new Date();
        return months[(now.getMonth() + calendarMonthOffset + 12000) % 12];
    }

    readonly property string calendarYear: {
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + calendarMonthOffset, 1);
        return String(d.getFullYear());
    }

    function openCalendar() {
        calendarMonthOffset = 0;
        calendarTick++;
        selectedDay = (new Date()).getDate();
        calendarVisible = true;
    }

    // ── CPU panel state ──
    property bool cpuVisible: false

    // ── Memory panel state ──
    property bool memVisible: false

    // ── Volume panel state ──
    property bool volVisible: false

    // ── Control center state ──
    property bool controlVisible: false

    // ── Split state (controlled by Bar + ControlPanel) ──
    property bool splitLeft:   false
    property bool splitRight:  false
    property bool splitArch:   false
    property bool splitMon:    false
    property bool splitNet:    false
    property bool splitMprisL: false

    // splitLeft/splitRight kept as constant-false (toggles removed); the clean
    // content-edge cuts are splitMon (Left) and splitMprisL (Right).
    function mergeAllSplits() {
        splitLeft = false; splitRight = false; splitArch = false;
        splitMon = false; splitNet = false; splitMprisL = false;
    }

    // ── module enable flags (controlled by ControlPanel) ──
    property bool modWorkspace:  true
    property bool modStatus:     true
    property bool modMemory:     true
    property bool modCpu:        true
    property bool modVolume:     true
    property bool modWeather:    true
    property bool modNetwork:    true
    property bool modPower:      true
    property bool modBluetooth:  true
    property bool modBattery:    true
    property bool modBrightness: true
    property bool modMedia:      true

    // ── New widget panel states ──
    property bool networkVisible:   false
    property bool bluetoothVisible: false
    property bool batteryVisible:   false
    property bool brightnessVisible: false
    property bool mprisVisible:     false
    property bool weatherVisible:   false
    property bool workspaceVisible: false

    // ── Notification state ──
    property bool notifVisible: false
    property int  notifCount:   0
    property real notifBarX:    0

    // ── Power Profile state ──
    property bool powerProfileVisible: false
    property string powerProfileCurrent: ""

    Process {
        id: initPowerProfile
        command: ["bash", "-c", "powerprofilesctl get 2>/dev/null || echo balanced"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim()
                if (p) theme.powerProfileCurrent = p
            }
        }
    }

    // ── Arch Updater state ──
    property bool archVisible: false
    property var archUpdates: []
    property int archRefreshTick: 0

    // ── Tray state ──
    property bool trayVisible: false
    property var trayPinned: []
    property real trayBarX: 10

    function trayIsHidden(item) {
        return trayPinned.indexOf(item.id) < 0
    }

    // toggle: hidden items get pinned (shown in bar); pinned items get unpinned (back to panel)
    function trayToggleHide(item) {
        var key = item.id
        if (!key) return
        var i = trayPinned.indexOf(key)
        if (i >= 0) {
            var a = trayPinned.slice(0, i)
            var b = trayPinned.slice(i + 1)
            trayPinned = a.concat(b)
            trayVisible = false
        } else {
            trayPinned = trayPinned.concat([key])
        }
    }

    Process {
        id: paletteReader
        command: ["cat", theme.colorsPath]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                Palette.apply(theme, Palette.parse(this.text));
            }
        }
    }

    IpcHandler {
        target: "theme"
        function apply(payload: string): void {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { console.warn("theme.apply: bad payload —", e); return; }
            if (!p || !p.colors) return;
            Palette.apply(theme, Palette.mapKeys(p.colors));
            theme.lastAppliedName = p.name || "";
        }
        function reload(): void {
            paletteReader.running = false;
            paletteReader.running = true;
        }
    }
}
