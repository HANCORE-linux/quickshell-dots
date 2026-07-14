import QtQuick
import Quickshell
import "modules"

ShellRoot {
    id: testRoot

    property string testCase: Quickshell.env("OLLAMA_PULL_TEST_CASE")
    property string modelName: "fixture:model"
    property bool cancelRequested: false
    property bool sawFinalizing: false
    property bool retryStarted: false
    property bool deadlineAdvanced: false
    property bool sawSecondLayerReset: false
    property bool sawSecondLayerProgress: false
    property bool finished: false

    QtObject {
        id: testClock
        property double virtualNowMs: 0
        function nowMs() { return virtualNowMs }
        function timerIntervalMs(logicalMs) { return Math.max(1, logicalMs / 1000) }
        function delayElapsed(logicalMs) { virtualNowMs += logicalMs }
    }

    function fail(message) {
        if (finished) return
        finished = true
        console.error("OLLAMA_PULL_INTEGRATION_FAIL: " + message)
        Qt.callLater(Qt.quit)
    }

    function pass() {
        if (finished) return
        finished = true
        console.log("OLLAMA_PULL_INTEGRATION_PASS: " + testCase)
        Qt.callLater(Qt.quit)
    }

    OllamaData {
        id: data
        enabled: false
        baseUrl: Quickshell.env("OLLAMA_PULL_TEST_URL")
    }

    Timer {
        interval: 50
        running: !testRoot.finished
        repeat: true
        onTriggered: {
            if (data.pullStatus === "Finalizing...") testRoot.sawFinalizing = true

            if (testRoot.testCase === "multi-digest") {
                var userFacing = data.pullStatus + " " + data.pullProgressText
                if (userFacing.indexOf("sha256:") >= 0)
                    testRoot.fail("user-facing status exposed a raw digest")
                if (data.pullDigest === "sha256:bbbbbbbb") {
                    if (!testRoot.sawSecondLayerReset) {
                        if (data.pullCompletedBytes !== 0 || data.pullTotalBytes !== 0
                                || data.pullRate.rateBytesPerSecond !== 0
                                || data.pullRate.etaSeconds !== 0
                                || data.pullStableRateSamples !== 0) {
                            testRoot.fail("second layer retained first-layer progress")
                        } else {
                            testRoot.sawSecondLayerReset = true
                        }
                    } else if (data.pullCompletedBytes === 25
                            && data.pullTotalBytes === 200) {
                        testRoot.sawSecondLayerProgress = true
                    }
                }
            }

            if ((testRoot.testCase === "cancel" || testRoot.testCase === "retry")
                    && data.pullState === "streaming"
                    && !testRoot.cancelRequested) {
                testRoot.cancelRequested = true
                data.cancelPull()
            }

            if (testRoot.testCase === "cancel" && testRoot.cancelRequested
                    && data.pullState === "cancelled") {
                if (data.pullBusy) testRoot.fail("cancelled attempt remains busy")
                else testRoot.pass()
            }

            if (testRoot.testCase === "reconcile-cancel" && data.pullState === "reconciling"
                    && data.pullReconcileAttempts > 0 && !testRoot.cancelRequested) {
                testRoot.cancelRequested = true
                data.cancelPull()
                if (data.pullState !== "reconciling")
                    testRoot.fail("cancel changed reconciliation state to " + data.pullState)
            }
            if (testRoot.testCase === "reconcile-cancel" && testRoot.cancelRequested
                    && data.pullState !== "reconciling" && data.pullState !== "success") {
                testRoot.fail("reconciliation did not continue after cancel: " + data.pullState)
            }

            if (testRoot.testCase === "late-response" && data.pullState === "reconciling"
                    && data.pullReconcileAttempts > 0 && !testRoot.deadlineAdvanced) {
                testRoot.deadlineAdvanced = true
                testClock.virtualNowMs = data.pullReconcileDeadlineAtMs
            }

            if ((testRoot.testCase === "delayed" || testRoot.testCase === "success")
                    && data.pullState === "success") {
                if (!testRoot.sawFinalizing) testRoot.fail("success skipped finalizing")
                else testRoot.pass()
            }

            if (testRoot.testCase === "multi-digest" && data.pullState === "success") {
                if (!testRoot.sawSecondLayerReset)
                    testRoot.fail("second layer reset was not observed")
                else if (!testRoot.sawSecondLayerProgress)
                    testRoot.fail("second layer progress was not observed")
                else if (data.pullProgressText.indexOf("Current layer") !== 0)
                    testRoot.fail("progress is not labeled as the current layer")
                else testRoot.pass()
            }

            if (testRoot.testCase === "delayed-125s" && data.pullState === "success") {
                if (!testRoot.sawFinalizing) testRoot.fail("success skipped finalizing")
                else if (testClock.virtualNowMs < 125000)
                    testRoot.fail("success occurred before 125 logical seconds")
                else testRoot.pass()
            } else if (testRoot.testCase === "delayed-125s" && data.pullState === "failed") {
                testRoot.fail("reconciliation failed before the 16th tags check")
            }

            if (testRoot.testCase === "reconcile-cancel" && data.pullState === "success") {
                if (!testRoot.cancelRequested) testRoot.fail("success occurred before cancel was tested")
                else if (!testRoot.sawFinalizing) testRoot.fail("success skipped finalizing")
                else testRoot.pass()
            }

            if (testRoot.testCase === "timeout" && data.pullState === "failed") {
                if (data.pullError.indexOf("finalization") < 0)
                    testRoot.fail("timeout was not a finalization error")
                else if (testClock.virtualNowMs < 180000)
                    testRoot.fail("timeout occurred before 180000 logical ms")
                else testRoot.pass()
            }

            if (testRoot.testCase === "late-response" && data.pullState === "success") {
                testRoot.fail("response arriving at the deadline revived success")
            } else if (testRoot.testCase === "late-response" && data.pullState === "failed") {
                if (!testRoot.deadlineAdvanced)
                    testRoot.fail("late response failed before the clock reached the deadline")
                else if (testClock.virtualNowMs < 180000)
                    testRoot.fail("late response failed before 180000 logical ms")
                else if (data.installedModels.length !== 0)
                    testRoot.fail("late response committed models after the deadline")
                else testRoot.pass()
            }

            if (testRoot.testCase === "retry" && data.pullState === "cancelled" && !retryStarted) {
                retryStarted = true
                data.pullModel(modelName)
            } else if (testRoot.testCase === "retry" && retryStarted && data.pullState === "success") {
                testRoot.pass()
            }
        }
    }

    Timer {
        interval: 15000
        running: !testRoot.finished
        onTriggered: testRoot.fail("timed out in state " + data.pullState)
    }

    Component.onCompleted: {
        if (data.hasOwnProperty("reconciliationClock")
                && (testCase === "delayed-125s" || testCase === "timeout"
                    || testCase === "reconcile-cancel" || testCase === "late-response")) {
            data.reconciliationClock = testClock
        }
        data.pullModel(modelName)
    }
}
