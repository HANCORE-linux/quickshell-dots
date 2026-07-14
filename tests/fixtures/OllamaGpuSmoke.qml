import QtQuick
import Quickshell
import Quickshell.Io
import "modules"

ShellRoot {
    id: testRoot

    property string testCase: Quickshell.env("OLLAMA_GPU_TEST_CASE")
    property int phase: 0
    property int historyBeforeInvalid: 0
    property bool finished: false

    function fail(message) {
        if (finished) return
        finished = true
        console.error("OLLAMA_GPU_FAIL: " + testCase + ": " + message)
        Qt.callLater(Qt.quit)
    }

    function pass() {
        if (finished) return
        finished = true
        console.log("OLLAMA_GPU_PASS: " + testCase)
        sampler.deactivate()
        Qt.callLater(Qt.quit)
    }

    function check(condition, message) {
        if (!condition) fail(message)
        return condition
    }

    function checkAmd() {
        if (phase === 0 && sampler.providerState === "active" && sampler.percent === 82) {
            if (!check(sampler.providerKind === "amdgpu-sysfs", "AMD provider selection")) return
            historyBeforeInvalid = sampler.history.length
            amdFirst.setText("invalid\n")
            amdSecond.setText("also-invalid\n")
            phase = 1
            phaseTimer.restart()
        } else if (phase === 1) {
            sampler.sampleNow()
            phase = 2
            phaseTimer.restart()
        } else if (phase === 2) {
            if (!check(sampler.history.length === historyBeforeInvalid,
                       "invalid AMD samples changed history")) return
            amdFirst.setText("33\n")
            amdSecond.setText("91\n")
            phase = 3
            phaseTimer.restart()
        } else if (phase === 3) {
            sampler.sampleNow()
            phase = 4
            phaseTimer.restart()
        } else if (phase === 4 && sampler.percent === 91) {
            if (!check(sampler.history.length > historyBeforeInvalid,
                       "valid AMD sample was not retained")) return
            pass()
        }
    }

    function checkNvidia() {
        if (phase === 0 && sampler.providerState === "active" && sampler.percent === 70) {
            if (!check(sampler.providerKind === "nvidia", "NVIDIA provider selection")) return
            phase = 1
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 1) {
            sampler.panelOpened()
            phase = 2
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 2) {
            if (!check(sampler.providerState === "active", "NVIDIA cadence restart")) return
            phase = 3
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 3) {
            pass()
        }
    }

    function checkBrokenNvidia() {
        if (phase === 0 && sampler.providerState === "unavailable") {
            if (!check(sampler.providerKind === "nvidia", "broken NVIDIA provider selection")) return
            if (!check(sampler.percent === -1, "broken NVIDIA percent")) return
            phase = 1
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 1) {
            sampler.redetect()
            phase = 2
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 2 && sampler.providerState === "unavailable") {
            pass()
        }
    }

    function checkNoSource() {
        if (phase === 0 && sampler.providerState === "unavailable") {
            if (!check(sampler.providerKind === "none", "no-source provider kind")) return
            if (!check(sampler.percent === -1, "no-source percent")) return
            phase = 1
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 1) {
            sampler.panelOpened()
            phase = 2
            phaseTimer.interval = 260
            phaseTimer.restart()
        } else if (phase === 2 && sampler.providerState === "unavailable") {
            pass()
        }
    }

    function checkHardwareAmd() {
        if (phase === 0 && sampler.providerState === "active" && sampler.percent >= 0) {
            if (!check(sampler.providerKind === "amdgpu-sysfs", "hardware AMD provider")) return
            historyBeforeInvalid = sampler.history.length
            sampler.panelOpened()
            sampler.sampleNow()
            phase = 1
            phaseTimer.interval = 250
            phaseTimer.restart()
        } else if (phase === 1 && sampler.history.length > historyBeforeInvalid) {
            pass()
        }
    }

    function advance() {
        if (finished) return
        if (testCase === "amd") checkAmd()
        else if (testCase === "nvidia") checkNvidia()
        else if (testCase === "broken-nvidia") checkBrokenNvidia()
        else if (testCase === "no-source") checkNoSource()
        else if (testCase === "hardware-amd") checkHardwareAmd()
        else fail("unknown test case")
    }

    OllamaGpuSampler {
        id: sampler
        sysfsRoot: Quickshell.env("OLLAMA_GPU_SYSFS_ROOT")
        nvidiaSmiExecutable: Quickshell.env("OLLAMA_GPU_NVIDIA_SMI")
        closedIntervalMs: 120
        openIntervalMs: 40
        onProviderStateChanged: Qt.callLater(testRoot.advance)
        onPercentChanged: Qt.callLater(testRoot.advance)
    }

    FileView {
        id: amdFirst
        path: sampler.sysfsRoot + "/class/drm/card0/device/gpu_busy_percent"
        printErrors: false
    }

    FileView {
        id: amdSecond
        path: sampler.sysfsRoot + "/class/drm/card3/device/gpu_busy_percent"
        printErrors: false
    }

    Timer {
        id: phaseTimer
        interval: 100
        repeat: false
        onTriggered: testRoot.advance()
    }

    Timer {
        interval: 5000
        running: !testRoot.finished
        repeat: false
        onTriggered: testRoot.fail("timed out in phase " + testRoot.phase
                                   + " state=" + sampler.providerState
                                   + " provider=" + sampler.providerKind
                                   + " percent=" + sampler.percent)
    }

    Component.onCompleted: {
        sampler.activate()
        phaseTimer.restart()
    }
}
