import QtQuick
import Quickshell.Io
import "OllamaDataLogic.js" as OllamaDataLogic
import "OllamaPullLogic.js" as OllamaPullLogic

Item {
    id: pull

    property string baseUrl: "http://127.0.0.1:11434"
    property bool blocked: false
    property int pullAttempt: 0
    property string pullState: "idle"
    readonly property bool pullBusy: pullState === "streaming" || pullState === "cancelling"
        || pullState === "reconciling"
    readonly property bool pullCanCancel: pullState === "streaming" || pullState === "cancelling"
    readonly property bool controlsLocked: blocked || pullBusy
    property string pullModelName: ""
    property double pullProgress: 0
    property int pullPercent: 0
    property string pullStatus: ""
    property string pullError: ""
    property string pullDigest: ""
    property double pullCompletedBytes: 0
    property double pullTotalBytes: 0
    property var pullRate: ({ digest: "", completed: 0, total: 0, sampledAtMs: 0,
                              rateBytesPerSecond: 0, etaSeconds: 0 })
    property int pullStableRateSamples: 0
    property double pullStartedAtMs: 0
    property double pullElapsedSeconds: 0
    property string pullLastLine: ""
    property int pullReconcileAttempts: 0
    property double pullReconcileStartedAtMs: 0
    property double pullReconcileDeadlineAtMs: 0
    property var reconciliationClock: systemReconciliationClock

    readonly property string pullProgressText: OllamaPullLogic.currentLayerText({
        completed: pullCompletedBytes,
        total: pullTotalBytes,
        rateBytesPerSecond: pullRate.rateBytesPerSecond,
        etaSeconds: pullRate.etaSeconds,
        stableSamples: pullStableRateSamples
    })
    readonly property string pullResultText: OllamaDataLogic.pullResultText(
        pullState, pullError, pullElapsedSeconds)

    signal installedModelsAccepted(var models)
    signal tagsFailureAccepted(string message)
    signal loadedRefreshRequested()
    signal refreshEpochInvalidationRequested()
    signal tagsRefreshResetRequested()
    signal operationErrorClearRequested()

    QtObject {
        id: systemReconciliationClock
        function nowMs() { return Date.now() }
        function timerIntervalMs(logicalMs) { return logicalMs }
        function delayElapsed(logicalMs) {}
    }

    function decodeResponse(raw) {
        return OllamaDataLogic.decodeResponse(raw)
    }

    function buildRequest(method, path, payload, maxTime) {
        return OllamaDataLogic.buildRequest(baseUrl, method, path, payload, maxTime)
    }

    function pullModel(name) {
        if (controlsLocked || !name) return
        var input = OllamaDataLogic.normalizePullInput(name)
        if (!input.valid) {
            pullError = input.error
            pullState = "failed"
            pullStatus = "Failed"
            return
        }
        operationErrorClearRequested()
        pullAttempt += 1
        pullState = "streaming"
        pullModelName = input.model
        pullProgress = 0
        pullPercent = 0
        pullStatus = "Connecting..."
        pullError = ""
        pullDigest = ""
        pullCompletedBytes = 0
        pullTotalBytes = 0
        pullRate = { digest: "", completed: 0, total: 0, sampledAtMs: 0,
            rateBytesPerSecond: 0, etaSeconds: 0 }
        pullStableRateSamples = 0
        pullStartedAtMs = Date.now()
        pullElapsedSeconds = 0
        pullLastLine = ""
        pullReconcileAttempts = 0
        pullReconcileStartedAtMs = 0
        pullReconcileDeadlineAtMs = 0
        pullReconcileTimer.stop()
        pullResultTimer.stop()
        pullProc.attempt = pullAttempt
        pullProc.command = [
            "curl", "-sS", "--fail-with-body", "--no-buffer",
            "--connect-timeout", "3", "--max-time", "3600",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-H", "Accept: application/json",
            "--data-binary", JSON.stringify({ model: input.model, stream: true }),
            baseUrl + "/api/pull"
        ]
        pullProc.running = true
    }

    function applyPullProgress(attempt, raw) {
        if (raw === undefined) {
            raw = attempt
            attempt = pullProc.attempt
        }
        if (attempt !== pullAttempt || pullState !== "streaming") return
        var text = String(raw || "").trim()
        if (!text) return
        try {
            var event = OllamaDataLogic.pullEventState(text, {
                digest: pullDigest, completed: pullCompletedBytes, total: pullTotalBytes
            })
            pullStatus = event.status
            var layer = OllamaPullLogic.nextLayerProgress({
                digest: pullDigest,
                completed: pullCompletedBytes,
                total: pullTotalBytes,
                sampledAtMs: pullRate.sampledAtMs,
                rateBytesPerSecond: pullRate.rateBytesPerSecond,
                etaSeconds: pullRate.etaSeconds,
                stableSamples: pullStableRateSamples
            }, text, Date.now())
            pullDigest = layer.digest
            pullCompletedBytes = layer.completed
            pullTotalBytes = layer.total
            pullRate = {
                digest: layer.digest,
                completed: layer.completed,
                total: layer.total,
                sampledAtMs: layer.sampledAtMs,
                rateBytesPerSecond: layer.rateBytesPerSecond,
                etaSeconds: layer.etaSeconds
            }
            pullStableRateSamples = layer.stableSamples
            if (layer.total > 0) {
                pullProgress = Math.min(1, layer.completed / layer.total)
                pullPercent = Math.round(pullProgress * 100)
            } else {
                pullProgress = 0
                pullPercent = 0
            }
        } catch (error) {}
    }

    function cancelPull() {
        if (pullState !== "streaming") return
        pullState = "cancelling"
        pullStatus = "Cancelling locally..."
        pullReconcileTimer.stop()
        pullProc.running = false
    }

    function failPullReconciliation() {
        pullReconcileTimer.stop()
        pullState = "failed"
        pullStatus = "Failed"
        pullError = "Pull finalization timed out: model was not listed"
        pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
    }

    function schedulePullReconciliation(attempt) {
        if (attempt !== pullAttempt || pullState !== "reconciling") return
        var nowMs = reconciliationClock.nowMs()
        if (nowMs >= pullReconcileDeadlineAtMs) {
            failPullReconciliation()
            return
        }
        var logicalDelayMs = OllamaPullLogic.nextReconcileDelayMs(
            pullReconcileAttempts, nowMs, pullReconcileDeadlineAtMs)
        pullReconcileTimer.attempt = attempt
        pullReconcileTimer.logicalDelayMs = logicalDelayMs
        pullReconcileTimer.interval = Math.max(1,
            reconciliationClock.timerIntervalMs(logicalDelayMs))
        pullReconcileTimer.restart()
    }

    function finishPull(attempt, exitCode) {
        if (attempt !== pullAttempt) return
        if (pullState === "cancelling") {
            pullReconcileTimer.stop()
            pullState = "cancelled"
            pullStatus = "Cancelled locally"
            pullError = ""
            pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
            return
        }
        if (pullState !== "streaming") return
        var state = OllamaDataLogic.pullResultState(exitCode, pullLastLine)
        if (state.valid) {
            pullProgress = 1
            pullState = "reconciling"
            pullStatus = "Finalizing..."
            pullReconcileStartedAtMs = reconciliationClock.nowMs()
            pullReconcileDeadlineAtMs = pullReconcileStartedAtMs + 180000
            refreshEpochInvalidationRequested()
            tagsRefreshResetRequested()
            pullReconcileAttempts = 0
            schedulePullReconciliation(attempt)
            loadedRefreshRequested()
        } else {
            pullError = state.error
            pullStatus = "Failed"
            pullState = "failed"
            pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
        }
    }

    function requestPullReconciliation(attempt) {
        if (attempt !== pullAttempt || pullState !== "reconciling") return
        if (reconciliationClock.nowMs() >= pullReconcileDeadlineAtMs) {
            failPullReconciliation()
            return
        }
        if (pullReconcileProc.running) {
            schedulePullReconciliation(attempt)
            return
        }
        pullReconcileAttempts += 1
        pullReconcileProc.attempt = attempt
        pullReconcileProc.command = buildRequest("GET", "/api/tags")
        pullReconcileProc.running = true
    }

    function handlePullTags(attempt, raw) {
        if (attempt !== pullAttempt || pullState !== "reconciling") return
        if (reconciliationClock.nowMs() >= pullReconcileDeadlineAtMs) {
            failPullReconciliation()
            return
        }
        var response = decodeResponse(raw)
        if (!OllamaDataLogic.successful(response)) {
            tagsFailureAccepted(OllamaDataLogic.errorMessage(
                response, "Unable to list Ollama models"))
            schedulePullReconciliation(attempt)
            return
        }
        var models
        try {
            models = OllamaDataLogic.parseTags(response.body)
        } catch (error) {
            tagsFailureAccepted("Invalid Ollama model response")
            schedulePullReconciliation(attempt)
            return
        }

        installedModelsAccepted(models)
        var visible = false
        for (var i = 0; i < models.length; i++) {
            if (models[i].name === pullModelName) {
                visible = true
                break
            }
        }
        if (!visible) {
            schedulePullReconciliation(attempt)
            return
        }
        pullState = "success"
        pullStatus = "Done"
        pullError = ""
        pullElapsedSeconds = Math.max(0, (Date.now() - pullStartedAtMs) / 1000)
        pullResultTimer.restart()
    }

    Process {
        id: pullProc
        property int attempt: 0
        property bool _exited: false
        stdout: SplitParser {
            onRead: function(line) {
                var text = String(line || "").trim()
                if (!text || pullProc.attempt !== pull.pullAttempt) return
                pull.pullLastLine = text
                pull.applyPullProgress(text)
            }
        }
        onExited: function(code) {
            _exited = true
            pull.finishPull(attempt, code)
        }
        onRunningChanged: {
            if (running) { _exited = false; return }
            if (!_exited && attempt === pull.pullAttempt && pull.pullState === "streaming") {
                pull.pullError = "Download failed"
                pull.pullStatus = "Failed"
                pull.pullState = "failed"
                pull.pullElapsedSeconds = Math.max(0,
                    (Date.now() - pull.pullStartedAtMs) / 1000)
            }
        }
    }

    Process {
        id: pullReconcileProc
        property int attempt: 0
        property bool streamDone: false
        onStarted: streamDone = false
        stdout: StdioCollector {
            onStreamFinished: {
                pullReconcileProc.streamDone = true
                pull.handlePullTags(pullReconcileProc.attempt, this.text)
            }
        }
        onExited: {
            if (!streamDone) pull.handlePullTags(attempt, "")
        }
    }

    Timer {
        id: pullReconcileTimer
        property int attempt: 0
        property double logicalDelayMs: 0
        interval: 1000
        repeat: false
        onTriggered: {
            if (attempt !== pull.pullAttempt || pull.pullState !== "reconciling") return
            pull.reconciliationClock.delayElapsed(logicalDelayMs)
            pull.requestPullReconciliation(attempt)
        }
    }

    Timer {
        id: pullResultTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (pull.pullState !== "success") return
            pull.pullState = "idle"
            pull.pullStatus = ""
            pull.pullElapsedSeconds = 0
        }
    }
}
