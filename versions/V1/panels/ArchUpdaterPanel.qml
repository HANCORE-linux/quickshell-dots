import QtQuick
import "../modules"
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: archPanel
    required property var root

    screen: root.activePopupScreen

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-arch-updater"

    readonly property int barBottom: 35
    readonly property int gap: 8

    Process {
        id: panelUpdateRunner
        // No default command: package updates and theme-terminal launches build
        // the command only on click, so an accidental start cannot run anything.
        command: []
    }

    // ── Theme-updates backend (this panel is the single instance in shell.qml,
    //    so the check runs ONCE, not per-monitor like the bar widgets would). The
    //    FileView publishes the read-only cache into root.themeUpd*; the button
    //    (Themes tab) bumps root.themeCheckTick to run the check script. ──
    function publishThemeState() {
        try {
            var j = JSON.parse(themeState.text())
            root.themeUpdTotal        = j.total      || 0
            root.themeUpdReachable    = j.reachable  || 0
            root.themeUpdOutdated     = j.outdated   || 0
            root.themeUpdLocalEdits   = j.localEdits || 0
            root.themeUpdDegraded     = !!j.degraded
            root.themeUpdCurrentStale = !!j.currentStale
            root.themeUpdChecked      = j.checked   || ""
            root.themeUpdList         = j.themes    || []
        } catch (e) {
            // keep the last good values on a malformed read
        }
    }

    FileView {
        id: themeState
        path: Quickshell.env("HOME") + "/.cache/qs-theme-updates.json"
        watchChanges: true
        onFileChanged: themeState.reload()
        onLoaded: archPanel.publishThemeState()
        // no onLoadFailed reset: absence just means "never checked" (themeUpdChecked stays "")
    }

    Process {
        id: themeCheckProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/bin/qs-theme-update-check.sh"]
        running: false
        onExited: {
            root.themeUpdChecking = false
            themeCheckWatchdog.stop()
            themeState.reload()   // pick up the freshly written cache immediately
        }
    }

    // unstick the button if the check ever hangs past its own 180s budget
    Timer {
        id: themeCheckWatchdog
        interval: 190000
        onTriggered: { root.themeUpdChecking = false; themeCheckProc.running = false }
    }

    property int themeCheckTrigger: root.themeCheckTick
    onThemeCheckTriggerChanged: {
        if (root.themeUpdChecking) return
        root.themeUpdChecking = true
        themeCheckWatchdog.restart()
        themeCheckProc.running = false
        themeCheckProc.running = true
    }

    property real reveal: root.archVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.archVisible ? 160 : 120
            easing.type: root.archVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001
    WlrLayershell.keyboardFocus: root.archVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeArchUpdatesPanel()
    }

    function refreshPackagesTabState() {
        archPanel.nowEpoch = Math.floor(Date.now() / 1000)
        root.archGateRescan()
        if (root.archUpdates.length === 0) root.archRefreshTick++
    }

    // Packages tab only: show the blacklist/protection status instantly (the gate
    // only reads a local file — no need to wait for the slow package check), and
    // kick a package check if there is no data yet. Opening Themes/Shell must not
    // start package work as a side effect.
    Connections {
        target: root
        function onArchVisibleChanged() {
            if (!root.archVisible) return
            if (root.activeUpdateTab === "packages") archPanel.refreshPackagesTabState()
        }
        function onActiveUpdateTabChanged() {
            if (root.archVisible && root.activeUpdateTab === "packages") archPanel.refreshPackagesTabState()
        }
        function onArchScanCheckedEpochChanged() {
            archPanel.nowEpoch = Math.floor(Date.now() / 1000)
        }
    }

    // pkg -> gate verdict, rebuilt once per gate run (avoids O(n²) per-row scans)
    readonly property var gateMap: {
        var m = ({})
        var r = root.archGateResults || []
        for (var i = 0; i < r.length; i++) m[r[i].pkg] = r[i]
        return m
    }

    // ── Full-repo update policy ──
    // AUR packages are never part of a pacman transaction. For official repo
    // packages, the safe boundary is all-or-nothing: if any repo package is not
    // scanned and OK, block the entire system upgrade. Never filter packages out
    // of pacman's transaction from this UI, because that can create an unsupported
    // partial upgrade.
    readonly property int repoUpdatePackages: {
        var n = 0, u = root.archUpdates || []
        for (var i = 0; i < u.length; i++)
            if (u[i].source !== "aur") n++
        return n
    }
    readonly property int repoOkPackages: {
        var n = 0, r = root.archGateResults || []
        for (var i = 0; i < r.length; i++)
            if (r[i].repo !== "aur" && r[i].verdict === "OK") n++
        return n
    }
    readonly property int aurReviewPackages: {
        var n = 0, r = root.archGateResults || []
        for (var i = 0; i < r.length; i++)
            if (r[i].repo === "aur" && r[i].verdict === "WARN") n++
        return n
    }
    readonly property int btnCount: aurReviewPackages > 0 ? 3 : 2
    property int nowEpoch: Math.floor(Date.now() / 1000)
    Timer {
        interval: 30000
        running: root.archVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: archPanel.nowEpoch = Math.floor(Date.now() / 1000)
    }
    readonly property bool repoScanFresh: root.archScanCheckedEpoch > 0
        && (nowEpoch - root.archScanCheckedEpoch) >= 0
        && (nowEpoch - root.archScanCheckedEpoch) <= root.archScanMaxAge
    readonly property bool repoScanMatchesUpdates: root.archScanSystemCount === repoUpdatePackages
    readonly property bool repoGateComplete: (root.archGateResults || []).length === (root.archUpdates || []).length
    readonly property bool repoGateAllowsFullUpgrade: repoUpdatePackages > 0
        && repoScanFresh
        && repoScanMatchesUpdates
        && repoGateComplete
        && repoOkPackages === repoUpdatePackages
        && (root.archGateState === "clean" || root.archGateState === "warn")
        && !root.archGateDegraded
    readonly property bool canUpdate: repoGateAllowsFullUpgrade
    readonly property string repoBlockReason: {
        if (repoUpdatePackages === 0) return "No pacman updates"
        if (!repoScanFresh) return "Repo upgrade blocked: refresh scan"
        if (!repoScanMatchesUpdates) return "Repo upgrade blocked: scan drift"
        if (root.archGateState === "scanning") return "Scanning packages"
        if (!repoGateComplete) return "Repo upgrade blocked: scan incomplete"
        if (root.archGateDegraded) return "Repo upgrade blocked: protection limited"
        if (root.archGateFail > 0 || root.archGateState === "blocked") return "Repo upgrade blocked: package blocked"
        if (repoOkPackages !== repoUpdatePackages) return "Repo upgrade blocked: unverified package"
        return ""
    }
    readonly property string repoBlockButtonText: {
        if (repoUpdatePackages === 0) return "No updates"
        if (!repoScanFresh) return "Refresh required"
        if (!repoScanMatchesUpdates) return "Scan drift"
        if (root.archGateState === "scanning") return "Scanning"
        if (!repoGateComplete) return "Scan incomplete"
        if (root.archGateDegraded) return "Protection limited"
        if (root.archGateFail > 0 || root.archGateState === "blocked") return "Package blocked"
        if (repoOkPackages !== repoUpdatePackages) return "Unverified package"
        return archPanel.repoBlockReason
    }
    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }
    function hexColor(c) {
        function h(v) {
            var x = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
            return x.length < 2 ? "0" + x : x
        }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function themedGumConfirmEnv() {
        return "env -u NO_COLOR"
            + " GUM_CONFIRM_PROMPT_FOREGROUND=" + shellQuote(hexColor(root.ink))
            + " GUM_CONFIRM_PROMPT_BACKGROUND=" + shellQuote(hexColor(root.bg))
            + " GUM_CONFIRM_SELECTED_FOREGROUND=" + shellQuote(hexColor(root.paper))
            + " GUM_CONFIRM_SELECTED_BACKGROUND=" + shellQuote(hexColor(root.seal))
            + " GUM_CONFIRM_UNSELECTED_FOREGROUND=" + shellQuote(hexColor(root.ink))
            + " GUM_CONFIRM_UNSELECTED_BACKGROUND=" + shellQuote(hexColor(root.bg))
    }

    // ── theme update = visible terminal, pinned to the checked commit ──
    // The check script records baseCommit/targetCommit. The apply script refuses
    // to move if the theme changed since the scan, if the upstream identity
    // changed, or if the saved target is no longer reachable.
    readonly property string themeCheckScript: Quickshell.env("HOME") + "/.config/quickshell/bin/qs-theme-update-check.sh"
    readonly property string themeApplyScript: Quickshell.env("HOME") + "/.config/quickshell/bin/qs-theme-apply-update.sh"

    function launchThemeTerminal(inner) {
        panelUpdateRunner.command = ["bash", "-c",
            "omarchy-launch-floating-terminal-with-presentation " + shellQuote(inner)]
        root.archVisible = false
        panelUpdateRunner.running = false
        panelUpdateRunner.running = true
    }

    function isPinnedThemeUpdate(t) {
        t = t || {}
        return !root.themeUpdChecking
            && t.state === "clean"
            && t.behind > 0
            && /^[A-Za-z0-9._-]+$/.test(t.name || "")
            && typeof t.baseCommit === "string" && t.baseCommit.length > 0
            && typeof t.targetCommit === "string" && t.targetCommit.length > 0
    }

    function cleanThemeNames() {
        var out = [], list = root.themeUpdList || []
        for (var i = 0; i < list.length; i++) {
            var t = list[i] || {}
            if (isPinnedThemeUpdate(t))
                out.push(t.name)
        }
        return out
    }
    function cleanThemeUpdateCount() {
        return cleanThemeNames().length
    }
    function updateAllThemes() {
        if (root.themeUpdChecking) return
        var names = cleanThemeNames()
        if (names.length <= 0) return
        launchThemeTerminal("set +e; "
            + shellQuote(themeApplyScript) + " --all; rc=$?; "
            + shellQuote(themeCheckScript) + "; exit $rc")
    }

    function updateOneTheme(name) {
        if (root.themeUpdChecking) return
        if (!/^[A-Za-z0-9._-]+$/.test(name)) return   // never build a command from a bad name
        launchThemeTerminal("set +e; "
            + shellQuote(themeApplyScript) + " " + shellQuote(name) + "; rc=$?; "
            + shellQuote(themeCheckScript) + "; exit $rc")
    }

    function viewThemeChanges(name) {
        if (!/^[A-Za-z0-9._-]+$/.test(name)) return
        var dir = Quickshell.env("HOME") + "/.config/omarchy/themes/" + name
        var git = "git -C " + shellQuote(dir)
                + " -c core.fsmonitor="
                + " -c core.hooksPath=/dev/null"
        var inner = "printf '%s\\n\\n' " + shellQuote("Theme changes: " + name) + "; "
                  + "up=$(" + git + " rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) "
                  + "|| { echo 'No upstream configured.'; exit 1; }; "
                  + "echo \"Upstream: $up\"; echo; "
                  + "echo 'Commits:'; "
                  + git + " --no-pager log --oneline --decorate HEAD..'@{upstream}' || true; "
                  + "echo; echo 'Changed files:'; "
                  + git + " --no-pager diff --no-ext-diff --no-textconv --stat HEAD..'@{upstream}' || true"
        launchThemeTerminal(inner)
    }

    // Re-apply the CURRENT theme (a separate, explicit action). A pinned update
    // only advances the theme's REPO; the live copy under current/theme is a
    // generated copy, so it stays stale until re-applied. Reads the name from
    // disk — no user-controlled string reaches the shell.
    function reapplyCurrentTheme() {
        var nameFile = root.themeNamePath
        var omarchyPath = root.omarchyInstallRoot || (Quickshell.env("HOME") + "/.local/share/omarchy")
        var inner = "n=$(tr -d '[:space:]' < " + shellQuote(nameFile) + "); "
                  + "[ -n \"$n\" ] || { echo 'no current theme'; exit 1; }; "
                  + themedGumConfirmEnv() + " gum confirm " + shellQuote("Re-apply the current theme to pick up its update?")
                  + " && OMARCHY_PATH=" + shellQuote(omarchyPath) + " omarchy-theme-set \"$n\""
        panelUpdateRunner.command = ["bash", "-c",
            "omarchy-launch-floating-terminal-with-presentation " + shellQuote(inner)]
        root.archVisible = false
        panelUpdateRunner.running = false
        panelUpdateRunner.running = true
    }

    // Reusable scroll-position thumb for the update lists: appears ONLY when the
    // list overflows, height is proportional to the visible fraction, tracks
    // contentY, AND is draggable with the mouse (drag translates to contentY —
    // we never bind-fight the y). One definition used by both tabs so they can
    // never drift apart (the F2 "fixed one variant, missed the sibling" lesson).
    component ScrollThumb: Item {
        id: scrollTrack
        required property var flick
        anchors.right: parent.right
        anchors.rightMargin: -6   // sit in the right gutter, clear of the full-width row separators
        width: 14
        height: flick.height
        visible: flick.contentHeight > flick.height + 1
        readonly property real thumbHeight: flick.contentHeight > 0
            ? Math.max(24, flick.height * flick.height / flick.contentHeight)
            : 0
        readonly property real thumbY: (flick.contentHeight > flick.height)
            ? (flick.height - thumbHeight) * (flick.contentY / (flick.contentHeight - flick.height))
            : 0

        Rectangle {
            id: thumb
            anchors.horizontalCenter: parent.horizontalCenter
            y: scrollTrack.thumbY
            width: (dragMa.containsMouse || dragMa.pressed) ? 6 : 3
            height: scrollTrack.thumbHeight
            radius: width / 2
            color: Qt.rgba(archPanel.root.ink.r, archPanel.root.ink.g, archPanel.root.ink.b,
                           (dragMa.containsMouse || dragMa.pressed) ? 0.5 : 0.28)
            Behavior on width { NumberAnimation { duration: 100 } }
        }

        // A wider stationary grab target. The visible thumb moves, but this track
        // stays fixed, so drag math is stable while contentY changes.
        MouseArea {
            id: dragMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property real startY: 0
            property real startContent: 0
            onPressed: (m) => {
                startY = m.y
                startContent = scrollTrack.flick.contentY
            }
            onPositionChanged: (m) => {
                if (!pressed) return
                var track = scrollTrack.flick.height - scrollTrack.thumbHeight
                if (track <= 0) return
                var scrollable = scrollTrack.flick.contentHeight - scrollTrack.flick.height
                var nc = startContent + (m.y - startY) * scrollable / track
                scrollTrack.flick.contentY = Math.max(0, Math.min(scrollable, nc))
            }
        }
    }

    Rectangle {
        id: card
        width: 520
        height: Math.min(col.implicitHeight + 24, 460)
        radius: reveal > 0.001 ? root.pillRadius : 0
        color: root.bg
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }

        x: Math.round(Math.max(6, Math.min(root.archBarX - width / 2, parent.width - width - 6)))
        y: root.barPosition === "bottom" ? (parent.height - barBottom - gap - height) : (barBottom + gap)
        opacity: archPanel.reveal
        focus: root.archVisible

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.closeArchUpdatesPanel();
                event.accepted = true;
            }
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
                UiText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Updates"
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 13
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }
                UiText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    id: closeX
                    text: "\u2715"
                    color: closeMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 12
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeArchUpdatesPanel()
                    }
                }
                Row {
                    anchors.right: closeX.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18
                    spacing: 8
                    UiText {
                        id: badgeToggleLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Badge Toggle:"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                    }
                    Repeater {
                        model: [
                            { id: "packages", label: "PKG" },
                            { id: "themes",   label: "Themes" },
                            { id: "shell",    label: "Shell" }
                        ]
                        Item {
                            id: badgeToggleItem
                            required property var modelData
                            readonly property bool active: modelData.id === "packages" ? root.archBadgePackages
                                : modelData.id === "themes" ? root.archBadgeThemes
                                : root.archBadgeShell
                            width: badgeToggleText.implicitWidth + 36
                            height: 18
                            UiText {
                                id: badgeToggleText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: badgeToggleItem.modelData.label
                                color: root.ink
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 30
                                height: 16
                                radius: 8
                                color: badgeToggleItem.active
                                    ? root.fillActive
                                    : badgeToggleMa.containsMouse ? root.fillHover : root.fillIdle
                                border.color: (badgeToggleItem.active || badgeToggleMa.containsMouse) ? root.seal : root.sep
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: badgeToggleItem.active ? parent.width - width - 3 : 3
                                    color: badgeToggleItem.active ? root.seal : root.sumi
                                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }
                            }
                            MouseArea {
                                id: badgeToggleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (badgeToggleItem.modelData.id === "packages")
                                        root.archBadgePackages = !root.archBadgePackages
                                    else if (badgeToggleItem.modelData.id === "themes")
                                        root.archBadgeThemes = !root.archBadgeThemes
                                    else
                                        root.archBadgeShell = !root.archBadgeShell
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── Packages ⟷ Themes ⟷ Shell tab switch (segmented, AiUsagePanel style) ──
            Row {
                width: parent.width
                height: 26
                spacing: 6
                Repeater {
                    model: [
                        { id: "packages", label: "Packages" },
                        { id: "themes", label: "Themes" },
                        { id: "shell", label: "Shell" }
                    ]
                    Rectangle {
                        required property var modelData
                        width: (parent.width - 12) / 3
                        height: 26; radius: root.tileRadius
                        readonly property bool active: root.activeUpdateTab === modelData.id
                        color: active ? root.fillActive : tabMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: (active || tabMa.containsMouse) ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: (parent.active || tabMa.containsMouse) ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 11
                            font.weight: parent.active ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeUpdateTab = parent.modelData.id
                        }
                    }
                }
            }

            // ══════════ PACKAGES TAB (existing content, unchanged) ══════════
            Column {
                id: packagesTab
                width: parent.width
                spacing: 8
                visible: root.activeUpdateTab === "packages"

            // ── one status line: counts + protection, "·"-separated, colored.
            //    A single RichText Text (NOT a Repeater) so it re-renders reliably
            //    whenever the gate state changes — a Repeater over a JS-array model
            //    failed to update segments when the array changed in place. The
            //    blacklist part is a link that opens the local list. ──
            Text {
                id: statusLine   // RichText, native-rendered
                width: parent.width
                visible: text.length > 0
                textFormat: Text.RichText
                renderType: Text.NativeRendering
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 10
                linkColor: root.ink
                text: {
                    function hx(c) {
                        function h(v) { var x = Math.round(v * 255).toString(16); return x.length < 2 ? "0" + x : x }
                        return "#" + h(c.r) + h(c.g) + h(c.b)
                    }
                    function seg(t, c) { return '<font color="' + hx(c) + '">' + t + '</font>' }
                    var p = []
                    if (root.archUpdates.length > 0) {
                        p.push(seg("✓ " + root.archGateOk + " OK", root.green))
                        if (root.archGateWarn > 0) p.push(seg("⚠ " + root.archGateWarn + " review", root.inkDeep))
                        if (root.archGateFail > 0) p.push(seg("✗ " + root.archGateFail + " blocked", root.seal))
                    }
                    if (root.archGateDegraded) p.push(seg("⚠ protection limited", root.seal))
                    if (root.archGateStale) p.push(seg("⚠ source stale", root.seal))
                    if (root.archGateMirrorsAgree && !root.archGateDegraded) p.push(seg("mirrors ✓", root.green))
                    if (root.archGateMirrorMismatch) p.push(seg("⚠ mirror mismatch", root.seal))
                    if (root.archGateBlacklist > 0) {
                        var b = "blacklist " + root.archGateBlacklist
                        if (root.archGateListDate !== "") b += " · " + root.archGateListDate
                        p.push('<a href="bl">' + seg(b, root.ink) + '</a>')   // only this part is clickable
                    }
                    return p.join(' <font color="' + hx(root.sumi) + '">·</font> ')
                }
                onLinkActivated: Quickshell.execDetached(["bash", "-c",
                    "omarchy-launch-floating-terminal-with-presentation 'less ~/.local/share/qs-aur-blacklist.txt'"])
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton   // cursor only — the Text handles the link click
                    hoverEnabled: true
                    cursorShape: statusLine.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }

            // ── escalation: a FAIL means the INSTALLED copy is on the list, i.e.
            // possibly already compromised; the full repo upgrade stays blocked ──
            UiText {
                visible: root.archGateFail > 0
                width: parent.width
                text: "⚠ installed copy may be compromised — run the infection checker"
                color: root.seal
                font.family: root.mono; font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            // ── column headers ──
            Row {
                width: parent.width
                spacing: 4
                UiText {
                    width: parent.width * 0.4
                    text: "Package"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                UiText {
                    width: parent.width * 0.3
                    text: "Installed"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
                UiText {
                    width: parent.width * 0.3
                    text: "Available"
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
                    font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
                }
            }

            // ── update list ──
            Item {
                width: parent.width
                height: Math.min(updatesCol.implicitHeight, 240)
                Flickable {
                    id: packagesFlick
                    anchors.fill: parent
                    contentHeight: updatesCol.implicitHeight
                    clip: true
                    interactive: updatesCol.implicitHeight > 240

                Column {
                    id: updatesCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.archUpdates

                        delegate: Item {
                            required property var modelData
                            required property int index

                            readonly property color srcColor: {
                                if (modelData.source === "system") return root.seal;
                                if (modelData.source === "aur") return root.indigo;
                                return root.sumi;
                            }

                            readonly property var gv: archPanel.gateMap[modelData.name]
                            readonly property bool vBlocked: gv !== undefined && gv.verdict === "FAIL"
                            readonly property bool vReview:  gv !== undefined && gv.verdict === "WARN"
                            readonly property bool vOk:      gv !== undefined && gv.verdict === "OK"
                            readonly property string vReason: (gv !== undefined && gv.reason) ? gv.reason : ""
                            readonly property bool showReason: vReason !== "" && (vBlocked || vReview)

                            width: parent.width
                            height: showReason ? 34 : 22
                            opacity: vBlocked ? 0.55 : 1.0

                            Row {
                                id: rowTop
                                width: parent.width
                                height: 22
                                spacing: 4
                                UiText {
                                    width: 14
                                    // neutral · until the gate has actually vouched —
                                    // unknown/scanning must NOT look like a green pass
                                    text: vBlocked ? "✗" : vReview ? "⚠" : vOk ? "✓" : "·"
                                    color: vBlocked ? root.seal : vReview ? root.inkDeep : vOk ? root.green : root.sumi
                                    font.family: root.mono; font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                UiText {
                                    width: parent.width * 0.4 - 18
                                    text: modelData.name
                                    color: vBlocked ? root.seal : srcColor
                                    font.family: root.mono; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                UiText {
                                    width: parent.width * 0.3
                                    text: modelData.oldVer
                                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                                    font.family: root.mono; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                                UiText {
                                    width: parent.width * 0.3
                                    text: modelData.newVer
                                    color: srcColor
                                    font.family: root.mono; font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            UiText {
                                visible: showReason
                                anchors.top: rowTop.bottom
                                x: 18
                                width: parent.width - 18
                                text: vReason
                                color: vBlocked ? root.seal : root.ink
                                font.family: root.mono; font.pixelSize: 9
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width - 16; height: 1
                                color: root.sep
                                visible: index < root.archUpdates.length - 1
                            }
                        }
                    }

                    UiText {
                        width: parent.width
                        visible: root.archUpdates.length === 0
                        text: "No updates available"
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
                        font.family: root.mono; font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 20
                    }
                }
                }
                ScrollThumb { flick: packagesFlick }
            }

            Rectangle { width: parent.width; height: 1; color: root.sep }

            // ── buttons ──
            Row {
                width: parent.width
                spacing: 8

                // Refresh
                Rectangle {
                    width: (parent.width - 8 * (archPanel.btnCount - 1)) / archPanel.btnCount
                    height: 28; radius: root.tileRadius
                    color: refreshMa.containsMouse ? root.fillHover : root.fillIdle
                    border.color: refreshMa.containsMouse ? root.seal : root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    UiText {
                        anchors.centerIn: parent
                        text: "Refresh"
                        color: refreshMa.containsMouse ? root.seal : root.ink
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        id: refreshMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.archRefreshTick++
                    }
                }

                // Update — full repo/system transaction via the checked apply helper;
                // AUR is never installed here.
                Rectangle {
                    width: (parent.width - 8 * (archPanel.btnCount - 1)) / archPanel.btnCount
                    height: 28; radius: root.tileRadius
                    opacity: archPanel.canUpdate ? 1.0 : 0.45
                    color: (updateMa.containsMouse && archPanel.canUpdate) ? root.fillPrimaryHover : root.seal
                    border.color: "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    UiText {
                        anchors.centerIn: parent
                        text: archPanel.canUpdate
                            ? "Full repo upgrade (" + archPanel.repoUpdatePackages + ")"
                            : archPanel.repoBlockButtonText
                        width: parent.width - 16
                        horizontalAlignment: Text.AlignHCenter
                        color: root.paper
                        font.family: root.mono; font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: updateMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: archPanel.canUpdate
                        cursorShape: archPanel.canUpdate ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            // Full repository upgrade only. The helper revalidates the
                            // checked scan, gate verdict and a fresh checkupdates scan
                            // before it can launch sudo pacman -Syu.
                            var prompt = "Run full repository upgrade for " + archPanel.repoUpdatePackages + " pacman packages?";
                            if (archPanel.aurReviewPackages > 0)
                                prompt += " " + archPanel.aurReviewPackages + " AUR review packages will be skipped.";
                            var applyScript = Quickshell.env("HOME") + "/.local/bin/qs-arch-apply-update.sh";
                            var updateCommand = archPanel.themedGumConfirmEnv()
                                + " gum confirm " + archPanel.shellQuote(prompt)
                                + " && " + archPanel.shellQuote(applyScript)
                                + " " + archPanel.shellQuote(root.archScanId)
                                + " " + archPanel.shellQuote(root.archScanHash)
                                + " " + archPanel.shellQuote(root.archScanSystemCount)
                                + " " + archPanel.shellQuote(root.archScanCheckedEpoch);
                            panelUpdateRunner.command = ["bash", "-c",
                                "omarchy-launch-floating-terminal-with-presentation "
                                    + archPanel.shellQuote(updateCommand)];
                            root.archVisible = false;
                            panelUpdateRunner.running = false;
                            panelUpdateRunner.running = true;
                        }
                    }
                }

                // Review — AUR needs a manual PKGBUILD look; this view installs nothing.
                Rectangle {
                    visible: archPanel.aurReviewPackages > 0
                    width: (parent.width - 8 * (archPanel.btnCount - 1)) / archPanel.btnCount
                    height: 28; radius: root.tileRadius
                    color: reviewMa.containsMouse ? root.fillHover : root.fillIdle
                    border.color: reviewMa.containsMouse ? root.seal : root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    UiText {
                        anchors.centerIn: parent
                        text: "Review " + archPanel.aurReviewPackages + " AUR"
                        color: reviewMa.containsMouse ? root.seal : root.ink
                        font.family: root.mono; font.pixelSize: 11
                    }
                    MouseArea {
                        id: reviewMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Display-only: list AUR updates, install nothing.
                            panelUpdateRunner.command = ["bash", "-c",
                                "omarchy-launch-floating-terminal-with-presentation 'echo \"AUR review — no packages are installed by this view.\"; echo; AUR=$(command -v paru || command -v yay || echo yay); \"$AUR\" -Qum; echo; echo \"Review each PKGBUILD before building these manually.\"'"];
                            root.archVisible = false;
                            panelUpdateRunner.running = false;
                            panelUpdateRunner.running = true;
                        }
                    }
                }
            }
            }
            // ══════════ END PACKAGES TAB ══════════

            // ══════════ THEMES TAB ══════════
            Column {
                id: themesTab
                width: parent.width
                spacing: 8
                visible: root.activeUpdateTab === "themes"

                // ── status line: counts + freshness (RichText, native) ──
                Text {
                    width: parent.width
                    textFormat: Text.RichText
                    renderType: Text.NativeRendering
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    font.family: root.mono; font.pixelSize: 10
                    text: {
                        function hx(c) { function h(v){var x=Math.round(v*255).toString(16); return x.length<2?"0"+x:x} return "#"+h(c.r)+h(c.g)+h(c.b) }
                        function seg(t,c){ return '<font color="'+hx(c)+'">'+t+'</font>' }
                        if (root.themeUpdChecked === "") return seg("never checked — run a scan", root.sumi)
                        var p = []
                        p.push(seg(root.themeUpdOutdated + (root.themeUpdOutdated === 1 ? " update found" : " updates found"),
                                   root.themeUpdOutdated>0?root.ink:root.sumi))
                        if (root.themeUpdLocalEdits>0) p.push(seg(root.themeUpdLocalEdits + " with local edits", root.inkDeep))
                        if (root.themeUpdDegraded) p.push(seg("⚠ check incomplete", root.seal))
                        var d = new Date(root.themeUpdChecked)
                        if (!isNaN(d.getTime())) p.push(seg("checked " + Qt.formatDateTime(d, "HH:mm"), root.sumi))
                        return p.join(' <font color="'+hx(root.sumi)+'">·</font> ')
                    }
                }

                // ── current theme became stale after its repo advanced ──
                Item {
                    visible: root.themeUpdCurrentStale
                    width: parent.width
                    height: 18
                    UiText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 84
                        text: "⟳ current theme updated — live copy is stale"
                        color: root.inkDeep
                        font.family: root.mono; font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -2   // match the update chip: onto the text's optical centre
                        width: 78; height: 18; radius: root.tileRadius
                        color: reapplyMa.containsMouse ? root.fillHover : root.fillIdle
                        border.color: reapplyMa.containsMouse ? root.seal : root.sep
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: "Re-apply"
                            color: reapplyMa.containsMouse ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 9
                        }
                        MouseArea {
                            id: reapplyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: archPanel.reapplyCurrentTheme()
                        }
                    }
                }

                // ── column headers ──
                Row {
                    width: parent.width
                    spacing: 6
                    UiText { width: parent.width - 220; text: "Theme";  color: Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.6); font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1 }
                    UiText { width: 60;  text: "Behind"; color: Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.6); font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1 }
                    UiText { width: 148; text: "State";  color: Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.6); font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1 }
                }

                // ── theme list (only outdated + unreachable themes are in the model) ──
                Item {
                    width: parent.width
                    height: Math.min(themesCol.implicitHeight, 240)
                    Flickable {
                        id: themesFlick
                        anchors.fill: parent
                        contentHeight: themesCol.implicitHeight
                        clip: true
                        interactive: themesCol.implicitHeight > 240

                    Column {
                        id: themesCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.themeUpdList

                            delegate: Item {
                                id: themeRow
                                required property var modelData
                                required property int index
                                readonly property bool isUnreach:   modelData.state === "unreachable"
                                readonly property bool isLocalEdits: modelData.state === "local-edits"
                                readonly property bool isClean:      modelData.state === "clean"
                                readonly property bool canViewChanges: modelData.behind > 0 && !isUnreach
                                readonly property var localFiles: modelData.files || []
                                readonly property string localReason: modelData.reason || ""
                                readonly property string localFileLabel: localFiles.length > 0
                                    ? localFiles[0] + (localFiles.length > 1 ? " +" + (localFiles.length - 1) : "")
                                    : localReason
                                readonly property string stateLabel: isUnreach ? "unreachable"
                                    : isLocalEdits ? ("blocked" + (localFileLabel !== "" ? ": " + localFileLabel : ""))
                                    : "clean"
                                // A per-theme update is pinned to the commit saved by the last
                                // scan. Local-edits/unreachable/old-schema rows stay review-only.
                                readonly property bool canPull: archPanel.isPinnedThemeUpdate(modelData)

                                width: parent.width
                                height: 22

                                Row {
                                    width: parent.width
                                    height: 22
                                    spacing: 6
                                    UiText {
                                        width: parent.width - 220
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name
                                        color: modelData.current ? root.seal : root.ink
                                        font.family: root.mono; font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                    Item {
                                        width: 60
                                        height: 22
                                        UiText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width
                                            text: isUnreach ? "—" : (modelData.behind + (modelData.behind === 1 ? " commit" : " commits"))
                                            color: behindMa.containsMouse && themeRow.canViewChanges ? root.seal : Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.7)
                                            font.family: root.mono; font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                        MouseArea {
                                            id: behindMa
                                            anchors.fill: parent
                                            hoverEnabled: themeRow.canViewChanges
                                            enabled: themeRow.canViewChanges
                                            cursorShape: themeRow.canViewChanges ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: archPanel.viewThemeChanges(modelData.name)
                                        }
                                    }
                                    // right slot: neutral state word + a per-theme "update" chip
                                    Item {
                                        width: 148
                                        height: 22
                                        UiText {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - (themeRow.canPull ? 76 : 16)
                                            text: themeRow.stateLabel
                                            color: isLocalEdits ? root.inkDeep : root.sumi
                                            font.family: root.mono; font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                        Rectangle {
                                            visible: themeRow.canPull
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: -2   // mono line-box sits high; nudge the button onto the text's optical centre
                                            anchors.rightMargin: 16
                                            width: 52; height: 18; radius: root.tileRadius
                                            color: pullMa.containsMouse ? root.fillPrimaryHover : root.seal
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            UiText {
                                                anchors.centerIn: parent
                                                text: "update"
                                                color: root.paper
                                                font.family: root.mono; font.pixelSize: 9
                                            }
                                            MouseArea {
                                                id: pullMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: archPanel.updateOneTheme(modelData.name)
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width - 16; height: 1
                                    color: root.sep
                                    visible: index < root.themeUpdList.length - 1
                                }
                            }
                        }

                        UiText {
                            width: parent.width
                            visible: root.themeUpdList.length === 0
                            text: root.themeUpdChecked === "" ? "Not checked yet" : "All themes up to date"
                            color: Qt.rgba(root.ink.r,root.ink.g,root.ink.b,0.5)
                            font.family: root.mono; font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: 20
                        }
                    }
                    }
                    ScrollThumb { flick: themesFlick }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                // ── buttons ──
                Row {
                    width: parent.width
                    spacing: 8

                    // Update clean — applies only clean themes with a saved target
                    // commit; blocked/local-edits stay untouched for review.
                    Rectangle {
                        readonly property int cleanCount: archPanel.cleanThemeUpdateCount()
                        readonly property bool canApply: cleanCount > 0 && !root.themeUpdChecking
                        width: (parent.width - 8) / 2
                        height: 28; radius: root.tileRadius
                        opacity: canApply ? 1.0 : 0.45
                        color: (allMa.containsMouse && canApply) ? root.fillPrimaryHover : root.seal
                        border.color: "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: root.themeUpdChecking ? "Checking…"
                                                  : parent.canApply ? (root.themeUpdLocalEdits > 0 ? "Update clean" : "Update all")
                                                  : root.themeUpdOutdated > 0 ? "Review first" : "No updates"
                            color: root.paper
                            font.family: root.mono; font.pixelSize: 11
                        }
                        MouseArea {
                            id: allMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.canApply
                            cursorShape: parent.canApply ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: archPanel.updateAllThemes()
                        }
                    }

                    // Check themes — runs the read-only check script; disabled while scanning
                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 28; radius: root.tileRadius
                        color: (checkMa.containsMouse && !root.themeUpdChecking) ? root.fillHover : root.fillIdle
                        border.color: (checkMa.containsMouse && !root.themeUpdChecking) ? root.seal : root.sep
                        border.width: 1
                        opacity: root.themeUpdChecking ? 0.5 : 1.0
                        Behavior on color { ColorAnimation { duration: 120 } }
                        UiText {
                            anchors.centerIn: parent
                            text: root.themeUpdChecking ? "Checking…" : "Check themes"
                            color: (checkMa.containsMouse && !root.themeUpdChecking) ? root.seal : root.ink
                            font.family: root.mono; font.pixelSize: 11
                        }
                        MouseArea {
                            id: checkMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.themeUpdChecking
                            cursorShape: root.themeUpdChecking ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: root.themeCheckTick++
                        }
                    }
                }
            }
            // ══════════ END THEMES TAB ══════════

            ShellUpdateTab {
                width: parent.width
                root: archPanel.root
                visible: root.activeUpdateTab === "shell"
            }
        }
    }
}
