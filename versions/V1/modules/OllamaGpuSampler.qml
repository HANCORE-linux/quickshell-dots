import QtQuick
import Quickshell.Io
import "OllamaGpuLogic.js" as OllamaGpuLogic

Item {
    id: sampler

    property string sysfsRoot: "/sys"
    property string nvidiaSmiExecutable: "nvidia-smi"
    property int closedIntervalMs: 15000
    property int openIntervalMs: 2000
    property int maxSamples: 30

    readonly property string providerKind: _providerKind
    readonly property string providerState: _providerState
    readonly property int percent: _percent
    readonly property var history: _history

    property string _providerKind: "none"
    property string _providerState: "undetected"
    property int _percent: -1
    property var _history: []
    property bool _active: false
    property bool _panelOpen: false
    property int _detectionEpoch: 0
    property int _detectionPending: 0
    property var _detectionRecords: []
    property var _amdSourceIndices: []
    property int _sampleEpoch: 0
    property int _samplePending: 0
    property int _sampleMaximum: -1
    property bool _nvidiaExpectedRunning: false
    property bool _nvidiaIntentionalStop: false
    property bool _nvidiaRestartAfterStop: false
    property int _nvidiaLastIndex: -1
    property int _nvidiaMaximum: -1
    property bool _nvidiaHasSample: false
    readonly property int _cadence: _panelOpen ? openIntervalMs : closedIntervalMs

    function activate() {
        if (_active) return
        _active = true
        redetect()
    }

    function deactivate() {
        if (!_active && _providerState === "undetected") return
        _active = false
        amdTimer.stop()
        stopNvidia(false)
        _detectionEpoch += 1
        _sampleEpoch += 1
        _samplePending = 0
        _providerKind = "none"
        _providerState = "undetected"
        _percent = -1
    }

    function redetect() {
        if (!_active || _providerState === "detecting") return
        amdTimer.stop()
        stopNvidia(false)
        _detectionEpoch += 1
        _sampleEpoch += 1
        _samplePending = 0
        _detectionPending = 0
        _detectionRecords = []
        _amdSourceIndices = []
        _providerKind = "none"
        _providerState = "detecting"
        _percent = -1
        var epoch = _detectionEpoch
        enumerateDrm(epoch)
    }

    function enumerateDrm(epoch) {
        drmEnumerationProc.detectionEpoch = epoch
        drmEnumerationProc.command = ["ls", "-1", sysfsRoot + "/class/drm"]
        drmEnumerationProc.running = true
    }

    function drmEnumerated(epoch, exitCode, output) {
        if (epoch !== _detectionEpoch || _providerState !== "detecting") return
        cardModel.clear()
        var cards = exitCode === 0 ? OllamaGpuLogic.drmCardIndices(output) : []
        for (var i = 0; i < cards.length; i++) cardModel.append({ cardNumber: cards[i] })
        _detectionPending = cards.length
        if (_detectionPending === 0) {
            finishDetection()
            return
        }
        Qt.callLater(function() { sampler.startDetectionProbes(epoch) })
    }

    function startDetectionProbes(epoch) {
        if (epoch !== _detectionEpoch || _providerState !== "detecting") return
        for (var i = 0; i < cardProbes.count; i++) {
            var probe = cardProbes.itemAt(i)
            if (probe) probe.beginDetection(epoch)
            else cardDetectionComplete(epoch, i, "", "", "", "", false)
        }
    }

    function cardDetectionComplete(epoch, probeIndex, cardNumber, uevent, vendor, busy,
                                   busyReadable) {
        if (epoch !== _detectionEpoch || _providerState !== "detecting") return
        _detectionRecords[probeIndex] = {
            probeIndex: probeIndex,
            cardNumber: cardNumber,
            uevent: uevent,
            vendor: vendor,
            busy: busy,
            busyReadable: busyReadable
        }
        _detectionPending -= 1
        if (_detectionPending !== 0) return

        finishDetection()
    }

    function finishDetection() {
        var selected = OllamaGpuLogic.providerSelection(_detectionRecords)
        _providerKind = selected.kind
        if (selected.kind === "amdgpu-sysfs") {
            _amdSourceIndices = selected.amdSources
            _providerState = "active"
            publishPercent(selected.initialPercent)
            amdTimer.start()
        } else if (selected.kind === "nvidia") {
            startNvidia()
        } else {
            _providerState = "unavailable"
        }
    }

    function sampleNow() {
        if (!_active || _providerState !== "active") return
        if (_providerKind === "nvidia") return
        if (_providerKind !== "amdgpu-sysfs" || _samplePending > 0) return
        _sampleEpoch += 1
        _samplePending = _amdSourceIndices.length
        _sampleMaximum = -1
        var epoch = _sampleEpoch
        for (var i = 0; i < _amdSourceIndices.length; i++) {
            var probe = cardProbes.itemAt(_amdSourceIndices[i])
            if (probe) probe.requestSample(epoch)
            else reportAmdSample(epoch, -1)
        }
    }

    function reportAmdSample(epoch, value) {
        if (epoch !== _sampleEpoch || _samplePending <= 0) return
        var parsed = OllamaGpuLogic.parsePercent(value)
        if (parsed >= 0) _sampleMaximum = Math.max(_sampleMaximum, parsed)
        _samplePending -= 1
        if (_samplePending !== 0) return
        if (_sampleMaximum >= 0) publishPercent(_sampleMaximum)
        else _percent = -1
    }

    function publishPercent(value) {
        var parsed = OllamaGpuLogic.parsePercent(value)
        if (parsed < 0) return
        _percent = parsed
        _history = OllamaGpuLogic.appendHistory(_history, parsed, maxSamples)
    }

    function panelOpened() {
        var changed = !_panelOpen
        _panelOpen = true
        if (!_active) return
        if (_providerState === "unavailable") redetect()
        else if (changed && _providerKind === "nvidia" && _providerState === "active")
            restartNvidia()
    }

    function panelClosed() {
        var changed = _panelOpen
        _panelOpen = false
        if (changed && _active && _providerKind === "nvidia" && _providerState === "active")
            restartNvidia()
    }

    function resetNvidiaBatch() {
        _nvidiaLastIndex = -1
        _nvidiaMaximum = -1
        _nvidiaHasSample = false
    }

    function startNvidia() {
        if (!_active || _providerKind !== "nvidia") return
        resetNvidiaBatch()
        var cadence = _cadence
        nvidiaProc.command = [
            nvidiaSmiExecutable,
            "--query-gpu=index,utilization.gpu",
            "--format=csv,noheader,nounits",
            "--loop-ms=" + cadence
        ]
        _nvidiaExpectedRunning = true
        nvidiaProc.running = true
    }

    function restartNvidia() {
        if (nvidiaProc.running || _nvidiaExpectedRunning) stopNvidia(true)
        else startNvidia()
    }

    function stopNvidia(restartAfterStop) {
        _nvidiaRestartAfterStop = restartAfterStop
        if (nvidiaProc.running || _nvidiaExpectedRunning) {
            _nvidiaIntentionalStop = true
            nvidiaProc.running = false
        } else {
            _nvidiaIntentionalStop = false
            if (restartAfterStop) startNvidia()
        }
    }

    function nvidiaStopped() {
        _nvidiaExpectedRunning = false
        if (_nvidiaIntentionalStop) {
            var restart = _nvidiaRestartAfterStop
            _nvidiaIntentionalStop = false
            _nvidiaRestartAfterStop = false
            if (restart && _active && _providerKind === "nvidia") startNvidia()
            return
        }
        if (!_active || _providerKind !== "nvidia") return
        _providerState = "unavailable"
        _percent = -1
    }

    function acceptNvidiaLine(line) {
        var entry = OllamaGpuLogic.nvidiaEntry(line)
        if (!entry.valid) return
        if (_nvidiaHasSample && entry.index <= _nvidiaLastIndex) {
            publishPercent(_nvidiaMaximum)
            _nvidiaMaximum = -1
        }
        _nvidiaMaximum = Math.max(_nvidiaMaximum, entry.percent)
        _nvidiaLastIndex = entry.index
        _nvidiaHasSample = true
    }

    Repeater {
        id: cardProbes
        model: ListModel { id: cardModel }

        Item {
            id: cardProbe
            required property int index
            required property int cardNumber
            property int detectionEpoch: -1
            property bool ueventDone: false
            property bool vendorDone: false
            property bool busyDone: false
            property bool busyReadable: false
            property string ueventText: ""
            property string vendorText: ""
            property string busyText: ""
            property int sampleEpoch: -1
            property bool samplePending: false

            function beginDetection(epoch) {
                detectionEpoch = epoch
                ueventDone = false
                vendorDone = false
                busyDone = false
                busyReadable = false
                ueventText = ""
                vendorText = ""
                busyText = ""
                ueventFile.reload()
                vendorFile.reload()
                busyFile.reload()
            }

            function completeDetectionIfReady() {
                if (!ueventDone || !vendorDone || !busyDone) return
                sampler.cardDetectionComplete(detectionEpoch, index, cardNumber,
                                              ueventText, vendorText, busyText,
                                              busyReadable)
            }

            function requestSample(epoch) {
                sampleEpoch = epoch
                samplePending = true
                busyFile.reload()
            }

            function busyLoaded(value, readable) {
                busyText = value
                busyReadable = readable
                busyDone = true
                completeDetectionIfReady()
                if (!samplePending) return
                samplePending = false
                sampler.reportAmdSample(sampleEpoch, value)
            }

            FileView {
                id: ueventFile
                path: sampler.sysfsRoot + "/class/drm/card" + cardProbe.cardNumber + "/device/uevent"
                printErrors: false
                onLoaded: {
                    cardProbe.ueventText = String(this.text() || "")
                    cardProbe.ueventDone = true
                    cardProbe.completeDetectionIfReady()
                }
                onLoadFailed: {
                    cardProbe.ueventText = ""
                    cardProbe.ueventDone = true
                    cardProbe.completeDetectionIfReady()
                }
            }

            FileView {
                id: vendorFile
                path: sampler.sysfsRoot + "/class/drm/card" + cardProbe.cardNumber + "/device/vendor"
                printErrors: false
                onLoaded: {
                    cardProbe.vendorText = String(this.text() || "")
                    cardProbe.vendorDone = true
                    cardProbe.completeDetectionIfReady()
                }
                onLoadFailed: {
                    cardProbe.vendorText = ""
                    cardProbe.vendorDone = true
                    cardProbe.completeDetectionIfReady()
                }
            }

            FileView {
                id: busyFile
                path: sampler.sysfsRoot + "/class/drm/card" + cardProbe.cardNumber
                      + "/device/gpu_busy_percent"
                printErrors: false
                onLoaded: cardProbe.busyLoaded(String(this.text() || ""), true)
                onLoadFailed: cardProbe.busyLoaded("", false)
            }
        }
    }

    Timer {
        id: amdTimer
        interval: sampler._cadence
        repeat: true
        triggeredOnStart: false
        onTriggered: sampler.sampleNow()
    }

    Process {
        id: drmEnumerationProc
        property int detectionEpoch: -1
        property bool exitSeen: false
        property bool streamDone: false
        property int resultCode: -1
        property string output: ""

        function completeIfReady() {
            if (!exitSeen || !streamDone) return
            sampler.drmEnumerated(detectionEpoch, resultCode, output)
        }

        onStarted: {
            exitSeen = false
            streamDone = false
            resultCode = -1
            output = ""
        }
        onExited: function(code) {
            resultCode = code
            exitSeen = true
            completeIfReady()
        }
        stdout: StdioCollector {
            onStreamFinished: {
                drmEnumerationProc.output = this.text
                drmEnumerationProc.streamDone = true
                drmEnumerationProc.completeIfReady()
            }
        }
    }

    Process {
        id: nvidiaProc
        onStarted: {
            if (sampler._nvidiaExpectedRunning && sampler._active
                    && sampler._providerKind === "nvidia")
                sampler._providerState = "active"
        }
        onRunningChanged: {
            if (!running && sampler._nvidiaExpectedRunning)
                sampler.nvidiaStopped()
        }
        stdout: SplitParser {
            onRead: function(line) { sampler.acceptNvidiaLine(line) }
        }
    }
}
