import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Palette.js" as Palette

Item {
    id: theme

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/omarchy/current/theme/colors.toml"

    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color sealRaw:    "#c4746e"
    property color accentHint: sealRaw    // filled by palette; default = same as red
    property bool  useThemeAccent: false

    readonly property color seal: useThemeAccent ? accentHint : sealRaw

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
    property int barAnim: 0   // 0=off, 1=stream, 2=surge, 3=bolt

    readonly property bool anySplit: splitLeft || splitRight || splitArch
                                  || splitMon  || splitNet  || splitMprisL
    onAnySplitChanged: if (!anySplit) barAnim = 0

    // splitLeft/splitRight kept as constant-false (toggles removed); the clean
    // content-edge cuts are splitMon (Left) and splitMprisL (Right).
    function mergeAllSplits() {
        splitLeft = false; splitRight = false; splitArch = false;
        splitMon = false; splitNet = false; splitMprisL = false;
    }

    // ── Control-panel state persistence (splits / anim / accent) ──
    // Survives bar restarts via a tiny cache file; no extra deps (same Process+cat
    // pattern used elsewhere). _splitsLoaded gates saving so the initial restore
    // doesn't immediately write back over itself.
    readonly property string splitsCachePath: Quickshell.env("HOME") + "/.cache/quickshell_splits"
    property bool _splitsLoaded: false

    onSplitArchChanged:      if (_splitsLoaded) saveSplits()
    onSplitMonChanged:       if (_splitsLoaded) saveSplits()
    onSplitNetChanged:       if (_splitsLoaded) saveSplits()
    onSplitMprisLChanged:    if (_splitsLoaded) saveSplits()
    onBarAnimChanged:        if (_splitsLoaded) saveSplits()
    onUseThemeAccentChanged: if (_splitsLoaded) saveSplits()

    // Build the command imperatively (not as a binding): a bound `command` can
    // still hold the pre-toggle value when the Process runs, saving stale state.
    function saveSplits() {
        var line = (splitArch   ? "1" : "0") + " "
                 + (splitMon     ? "1" : "0") + " "
                 + (splitMprisL  ? "1" : "0") + " "
                 + (splitNet     ? "1" : "0") + " "
                 + barAnim + " "
                 + (useThemeAccent ? "1" : "0")
        splitSaveProc.command = ["bash", "-c",
            "mkdir -p \"$(dirname '" + splitsCachePath + "')\" && echo '" + line + "' > '" + splitsCachePath + "'"]
        splitSaveProc.running = false
        splitSaveProc.running = true
    }

    Process {
        id: splitLoadProc
        command: ["cat", theme.splitsCachePath]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split(" ")
                if (parts.length >= 5) {
                    theme.splitArch      = parts[0] === "1"
                    theme.splitMon       = parts[1] === "1"
                    theme.splitMprisL    = parts[2] === "1"
                    theme.splitNet       = parts[3] === "1"
                    var ba = parseInt(parts[4]); theme.barAnim = (ba >= 0 && ba <= 3) ? ba : 0
                    theme.useThemeAccent = parts.length >= 6 && parts[5] === "1"
                }
                theme._splitsLoaded = true
            }
        }
    }

    Process { id: splitSaveProc }   // command is set imperatively in saveSplits()

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

    // ── Launcher / Menu panel state ──
    property bool   omarchyMenuVisible:    false
    property bool   themePickerVisible:    false
    property bool   wallpaperPickerVisible: false
    property real   quickActionsBarX:      0
    property string launcherIconEffect: ""
    property color  launcherIconTint:   seal
    onControlVisibleChanged: if (!controlVisible) omarchyMenuVisible = false

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

    // ── Hyprland workspace dispatch (config-mode-aware) ──
    // Hyprland 0.55 added Lua configs but still supports classic hyprlang, and
    // BOTH ship the same version number — so the dispatch form depends on which
    // config is ACTIVE, not the version: classic wants "workspace N", Lua wants
    // hl.dsp.focus({ workspace = N }). Probe the mode once with a harmless token:
    // "hl.dsp" alone yields the Lua error "hl.dispatch: expected a dispatcher"
    // under Lua, or "Invalid dispatcher" under classic — neither switches.
    property bool hyprUsesLua: false
    Process {
        id: hyprDispatchProbe
        command: ["bash", "-c", "hyprctl dispatch 'hl.dsp' 2>&1 | grep -qi 'hl\\.dispatch' && echo lua || echo classic"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { theme.hyprUsesLua = (this.text.trim() === "lua") }
        }
    }
    function gotoWorkspace(id) {
        if (hyprUsesLua)
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
        else
            Hyprland.dispatch("workspace " + id)
    }

    // ── Arch Updater state ──
    property bool archVisible: false
    property var archUpdates: []
    property int archRefreshTick: 0

    // ── Tray state ──
    property bool trayVisible: false
    property var trayPinned: []
    property real trayBarX: 10

    // ── Tray context-menu state (themed menu, rendered by TrayMenu.qml) ──
    property bool trayMenuVisible: false
    property var  trayMenuHandle: null   // the QsMenuHandle of the clicked item
    property real trayMenuX: 0           // global x to anchor the menu under the icon
    function openTrayMenu(handle, x) {
        trayMenuHandle = handle
        trayMenuX = x
        trayMenuVisible = true
    }

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

    Process {
        id: qsJsonReader
        command: ["cat", Quickshell.env("HOME") + "/.config/omarchy/current/theme/quickshell.json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    if (j.launcher) {
                        theme.launcherIconEffect = j.launcher.iconEffect || ""
                        if (j.launcher.iconTint) theme.launcherIconTint = j.launcher.iconTint
                    } else {
                        theme.launcherIconEffect = ""
                    }
                } catch(e) {}
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
        function applyLauncher(payload: string): void {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { return; }
            theme.launcherIconEffect = (p && p.launcher && p.launcher.iconEffect)
                ? p.launcher.iconEffect : ""
            if (p && p.launcher && p.launcher.iconTint)
                theme.launcherIconTint = p.launcher.iconTint
        }
    }
}
