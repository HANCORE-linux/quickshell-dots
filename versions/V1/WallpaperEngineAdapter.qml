pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// Single owner of all `omarchy-we` interaction for the "animated" (Wallpaper
// Engine) picker mode. Centralizes the capability probe, entry fetch, JSON
// validation, atomic caching, error state, apply, and renderer teardown so the
// three picker styles delegate here instead of each duplicating a shell
// pipeline.
//
// Capability/version contract: `omarchy-we ipc version` must exit 0 and report
// an `ipc` number >= requiredContract, otherwise the feature stays disabled.
// See github.com/dkgamer02ai/omarchy-wallpaper-engine.
QtObject {
    id: adapter

    // ── capability ──
    readonly property int requiredContract: 1
    property bool checked: false      // version probe finished
    property bool available: false    // omarchy-we present + compatible
    property int contract: 0

    // ── data (consumed by the picker panels) ──
    // rowsText is a sanitized "id \t preview \t \t label" feed — every field is
    // stripped of tabs/newlines/control chars before joining, so no metadata can
    // corrupt the row format (structured JSON in, safe rows out).
    property string rowsText: ""
    property string currentId: ""
    property bool loading: false
    property bool loaded: false       // a successful entries fetch populated rowsText
    property string errorText: ""     // non-empty => last fetch failed (show, don't treat as empty)

    readonly property string cacheDir: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string cachePath: cacheDir + "/quickshell-wallpaper-engine.tsv"

    signal ready()            // rowsText / currentId / errorText updated
    signal applied(bool ok)   // an apply() finished

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function sane(s) {
        var t = String(s === undefined || s === null ? "" : s)
        var out = ""
        for (var i = 0; i < t.length; i++) {
            var c = t.charCodeAt(i)
            out += (c < 32) ? " " : t[i]   // drop tabs/newlines/control chars
        }
        return out.replace(/ +/g, " ").trim()
    }

    // Validate + sanitize structured entries into safe TSV rows.
    function rowsFromEntries(arr) {
        var out = []
        for (var i = 0; i < arr.length; i++) {
            var e = arr[i]
            if (!e || typeof e !== "object") continue
            var id = adapter.sane(e.id)
            var preview = adapter.sane(e.preview)
            if (id === "" || preview === "") continue        // require id + a preview image
            var title = adapter.sane(e.title) || id
            var type = adapter.sane(e.type)
            var label = type !== "" ? (title + " (" + type + ")") : title
            out.push(id + "\t" + preview + "\t\t" + label)
        }
        return out.join("\n")
    }

    // ── capability probe ──
    function checkAvailability() {
        if (versionProc.running) return
        versionProc.running = true
    }

    property Process versionProc: Process {
        command: ["omarchy-we", "ipc", "version"]
        stdout: StdioCollector { id: versionOut }
        onExited: (exitCode) => {
            adapter.checked = true
            if (exitCode !== 0) { adapter.available = false; return }
            try {
                var d = JSON.parse(String(versionOut.text || "{}"))
                adapter.contract = Number(d.ipc) || 0
                adapter.available = adapter.contract >= adapter.requiredContract
            } catch (e) {
                adapter.available = false
            }
        }
    }

    // ── load: instant cache paint, then a validated live refresh ──
    function refresh() {
        adapter.loading = true
        currentProc.running = false; currentProc.running = true
        cacheReadProc.running = false; cacheReadProc.running = true
        entriesProc.running = false; entriesProc.running = true
    }

    property Process cacheReadProc: Process {
        command: ["cat", adapter.cachePath]
        stdout: StdioCollector { id: cacheOut }
        onExited: (exitCode) => {
            // Only paint from cache before the live result lands, and never over an error.
            if (exitCode === 0 && !adapter.loaded && adapter.errorText === "") {
                var t = String(cacheOut.text || "").trim()
                if (t !== "") { adapter.rowsText = t; adapter.ready() }
            }
        }
    }

    property Process currentProc: Process {
        command: ["omarchy-we", "ipc", "current"]
        stdout: StdioCollector { id: currentOut }
        onExited: (exitCode) => {
            if (exitCode !== 0) return
            try {
                var d = JSON.parse(String(currentOut.text || "{}"))
                adapter.currentId = adapter.sane(d.id)
                adapter.ready()
            } catch (e) { /* keep previous currentId */ }
        }
    }

    property Process entriesProc: Process {
        command: ["omarchy-we", "ipc", "entries"]
        stdout: StdioCollector { id: entriesOut }
        stderr: StdioCollector { id: entriesErr }
        onExited: (exitCode) => {
            adapter.loading = false
            if (exitCode !== 0) {
                adapter.errorText = adapter.sane(entriesErr.text) || ("omarchy-we ipc entries failed (exit " + exitCode + ")")
                adapter.ready()
                return
            }
            var arr
            try { arr = JSON.parse(String(entriesOut.text || "[]")) }
            catch (e) { adapter.errorText = "omarchy-we returned malformed JSON"; adapter.ready(); return }
            if (!Array.isArray(arr)) { adapter.errorText = "omarchy-we returned unexpected data"; adapter.ready(); return }

            adapter.rowsText = adapter.rowsFromEntries(arr)
            adapter.loaded = true
            adapter.errorText = ""
            adapter.ready()

            // Atomic cache replacement: temp file + rename, only after a validated response.
            cacheWriteProc.command = ["bash", "-c",
                "d=" + adapter.shq(adapter.cacheDir) + "; mkdir -p \"$d\"; " +
                "t=" + adapter.shq(adapter.cachePath) + ".$$; " +
                "printf '%s' \"$1\" > \"$t\" && mv -f \"$t\" " + adapter.shq(adapter.cachePath),
                "omarchy-we", adapter.rowsText]
            cacheWriteProc.running = false; cacheWriteProc.running = true
        }
    }

    property Process cacheWriteProc: Process { command: [] }

    // ── actions ──
    function apply(id) {
        if (!id) return
        applyProc.command = ["omarchy-we", "ipc", "set", String(id)]
        applyProc.running = false; applyProc.running = true
    }
    property Process applyProc: Process {
        command: []
        onExited: (exitCode) => {
            adapter.applied(exitCode === 0)
            // A failed `set` would otherwise close the picker silently; surface it.
            if (exitCode !== 0) {
                notifyProc.command = ["bash", "-c",
                    "command -v omarchy-notification-send >/dev/null 2>&1 " +
                    "&& omarchy-notification-send 'Wallpaper Engine: failed to apply wallpaper' -t 3000 " +
                    "|| notify-send 'Wallpaper Engine' 'Failed to apply wallpaper' 2>/dev/null || true"]
                notifyProc.running = false; notifyProc.running = true
            }
        }
    }
    property Process notifyProc: Process { command: [] }

    // Tear down the renderer when switching back to a static wallpaper. The
    // caller sets the static background itself, so this only kills the renderer.
    function stopRenderer() { stopProc.running = false; stopProc.running = true }
    property Process stopProc: Process { command: ["omarchy-we", "ipc", "kill"] }

    Component.onCompleted: adapter.checkAvailability()
}
