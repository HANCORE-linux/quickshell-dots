import QtQuick
import Quickshell
import Quickshell.Io
import "modules"

ShellRoot {
    id: testRoot

    property string markerName: ""
    property bool finished: false

    function fail(message) {
        if (finished) return
        finished = true
        console.error("OLLAMA_LIFECYCLE_FAIL: " + message)
        Qt.callLater(Qt.quit)
    }

    function waitFor(milliseconds) {
        phaseTimer.interval = milliseconds
        phaseTimer.restart()
    }

    function mark(name) {
        if (markerProc.running) {
            fail("marker process already running")
            return
        }
        markerName = name
        markerProc.command = data.buildRequest("GET", "/test/phase/" + name)
        markerProc.running = true
    }

    function markerComplete(code) {
        if (code !== 0) {
            fail("marker request failed: " + markerName)
            return
        }

        if (markerName === "disabled-end") {
            data.enabled = true
            waitFor(300)
        } else if (markerName === "enable-closed-end") {
            waitFor(360)
        } else if (markerName === "closed-steady-end") {
            data.panelVisible = true
            data.refreshAll()
            waitFor(520)
        } else if (markerName === "open-end") {
            data.panelVisible = false
            waitFor(360)
        } else if (markerName === "close-end") {
            data.refreshAll()
            waitFor(300)
        } else if (markerName === "manual-end") {
            waitFor(360)
        } else if (markerName === "manual-steady-end") {
            waitFor(1)
        } else if (markerName === "delayed-open-start") {
            data.panelVisible = true
            data.refreshAll()
            waitFor(180)
        } else if (markerName === "delayed-close-start") {
            waitFor(450)
        } else if (markerName === "delayed-close-end") {
            waitFor(1)
        } else if (markerName === "manual-pending-open-start") {
            data.panelVisible = true
            data.refreshAll()
            waitFor(70)
        } else if (markerName === "manual-pending-close-start") {
            data.refreshAll()
            waitFor(450)
        } else if (markerName === "manual-pending-close-end") {
            waitFor(1)
        } else if (markerName === "done") {
            finished = true
            console.log("OLLAMA_LIFECYCLE_SEQUENCE_PASS")
            Qt.callLater(Qt.quit)
        } else {
            fail("unknown marker: " + markerName)
        }
    }

    OllamaData {
        id: data
        enabled: false
        panelVisible: false
        baseUrl: Quickshell.env("OLLAMA_LIFECYCLE_TEST_URL")
    }

    Process {
        id: markerProc
        onExited: function(code) { testRoot.markerComplete(code) }
    }

    Timer {
        id: phaseTimer
        repeat: false
        onTriggered: {
            if (testRoot.markerName === "") testRoot.mark("disabled-end")
            else if (testRoot.markerName === "disabled-end") testRoot.mark("enable-closed-end")
            else if (testRoot.markerName === "enable-closed-end") testRoot.mark("closed-steady-end")
            else if (testRoot.markerName === "closed-steady-end") testRoot.mark("open-end")
            else if (testRoot.markerName === "open-end") testRoot.mark("close-end")
            else if (testRoot.markerName === "close-end") testRoot.mark("manual-end")
            else if (testRoot.markerName === "manual-end") testRoot.mark("manual-steady-end")
            else if (testRoot.markerName === "manual-steady-end")
                testRoot.mark("delayed-open-start")
            else if (testRoot.markerName === "delayed-open-start") {
                data.panelVisible = false
                testRoot.mark("delayed-close-start")
            } else if (testRoot.markerName === "delayed-close-start")
                testRoot.mark("delayed-close-end")
            else if (testRoot.markerName === "delayed-close-end")
                testRoot.mark("manual-pending-open-start")
            else if (testRoot.markerName === "manual-pending-open-start") {
                data.panelVisible = false
                testRoot.mark("manual-pending-close-start")
            } else if (testRoot.markerName === "manual-pending-close-start")
                testRoot.mark("manual-pending-close-end")
            else if (testRoot.markerName === "manual-pending-close-end")
                testRoot.mark("done")
            else testRoot.fail("unexpected phase after " + testRoot.markerName)
        }
    }

    Timer {
        interval: 8000
        running: !testRoot.finished
        repeat: false
        onTriggered: testRoot.fail("timed out after " + testRoot.markerName)
    }

    Component.onCompleted: waitFor(250)
}
