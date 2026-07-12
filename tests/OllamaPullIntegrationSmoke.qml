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
    property bool finished: false

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

            if ((testRoot.testCase === "delayed" || testRoot.testCase === "success")
                    && data.pullState === "success") {
                if (!testRoot.sawFinalizing) testRoot.fail("success skipped finalizing")
                else testRoot.pass()
            }

            if (testRoot.testCase === "timeout" && data.pullState === "failed") {
                if (data.pullError.indexOf("finalization") < 0)
                    testRoot.fail("timeout was not a finalization error")
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

    Component.onCompleted: data.pullModel(modelName)
}
