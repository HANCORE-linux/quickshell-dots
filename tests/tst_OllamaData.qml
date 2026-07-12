import QtQuick 2.15
import QtTest 1.3
import "../versions/V1/modules/OllamaDataLogic.js" as OllamaDataLogic

TestCase {
    name: "OllamaData"

    QtObject {
        id: data

        property string baseUrl: "http://localhost:11434"
        property bool connected: false
        property string version: ""
        property var installedModels: []
        property var loadedModels: []
        property bool busy: false
        property string pendingAction: ""
        property string pendingModel: ""
        property string lastError: ""

        readonly property var models: OllamaDataLogic.reconcileModels(installedModels, loadedModels)

        function decodeResponse(raw) { return OllamaDataLogic.decodeResponse(raw) }
        function parseTags(body) { return OllamaDataLogic.parseTags(body) }
        function parseLoaded(body) { return OllamaDataLogic.parseLoaded(body) }
        function buildLoadPayload(modelName, keepAlive, numCtx) {
            return OllamaDataLogic.buildLoadPayload(modelName, keepAlive, numCtx)
        }
        function normalizeHost(host) {
            return OllamaDataLogic.normalizeHost(host)
        }
        function validateContextLength(contextLength, numCtx) {
            return OllamaDataLogic.validateContextLength(contextLength, numCtx)
        }
        function loadVerificationState(entries, selectedName, numCtx) {
            return OllamaDataLogic.loadVerificationState(entries, selectedName, numCtx)
        }
        function conflictingModelNames(entries, selectedName) {
            return OllamaDataLogic.conflictingModelNames(entries, selectedName)
        }
        function exclusiveLoadState(entries, selectedName) {
            return OllamaDataLogic.exclusiveLoadState(entries, selectedName)
        }
        function operationMessage(state, modelName) {
            return OllamaDataLogic.operationMessage(state, modelName)
        }
        function generateResponseState(body) {
            return OllamaDataLogic.generateResponseState(body)
        }
        function pullResultState(exitCode, lastLine) {
            return OllamaDataLogic.pullResultState(exitCode, lastLine)
        }
        function runtimeConfigState(raw) {
            return OllamaDataLogic.runtimeConfigState(raw)
        }
        function parseContextInput(raw) {
            return OllamaDataLogic.parseContextInput(raw)
        }
        function aggregateError(action, versionE, tags, loaded) {
            return OllamaDataLogic.aggregateError(action, versionE, tags, loaded)
        }
        function aggregateConnected(vConn, tConn, lConn) {
            return OllamaDataLogic.aggregateConnected(vConn, tConn, lConn)
        }
        function maxGpuPercent(raw) {
            return OllamaDataLogic.maxGpuPercent(raw)
        }
        function sumLoadedVram(entries) { return OllamaDataLogic.sumLoadedVram(entries) }
        function errorMessage(response, fallback) { return OllamaDataLogic.errorMessage(response, fallback) }
        function successful(response) { return OllamaDataLogic.successful(response) }
        function buildRequest(method, path, payload, maxTime) {
            return OllamaDataLogic.buildRequest(baseUrl, method, path, payload, maxTime)
        }
        function applyVersion(raw) {
            var state = OllamaDataLogic.versionState(raw, version)
            connected = state.connected
            version = state.version
            lastError = state.lastError
        }
        function beginActionState(actionName, name) {
            var state = OllamaDataLogic.beginActionState(actionName, name)
            busy = state.busy
            pendingAction = state.pendingAction
            pendingModel = state.pendingModel
        }
        function clearActionState() {
            var state = OllamaDataLogic.clearActionState()
            busy = state.busy
            pendingAction = state.pendingAction
            pendingModel = state.pendingModel
        }
    }

    function test_decodeResponse() {
        var response = data.decodeResponse('{"version":"0.31.2"}\n200')
        compare(response.status, 200)
        compare(JSON.parse(response.body).version, "0.31.2")
    }

    function test_parseTags() {
        var models = data.parseTags('{"models":[{"name":"qwen3:8b","size":5220000000,"details":{"parameter_size":"8B","quantization_level":"Q6_K"}}]}')
        compare(models.length, 1)
        compare(models[0].name, "qwen3:8b")
        compare(models[0].parameterSize, "8B")
        compare(models[0].quantization, "Q6_K")
    }

    function test_parseLoadedAndVram() {
        var models = data.parseLoaded('{"models":[{"name":"qwen3:8b","size":5220000000,"size_vram":5000000000}]}')
        compare(models.length, 1)
        compare(models[0].sizeVram, 5000000000)
        compare(data.sumLoadedVram(models), 5000000000)
    }

    function test_preservesLongTaggedNames() {
        var name = "hf.co/usuario/modelo-GGUF:Q6_K"
        var models = data.parseLoaded(JSON.stringify({
            models: [{ name: name, size: 1, size_vram: 1 }]
        }))
        compare(models[0].name, name)
    }

    function test_rejectsMalformedLoadedResponse() {
        function didThrow(callback) {
            try { callback() } catch (error) { return true }
            return false
        }
        verify(didThrow(function() { data.parseLoaded("{}") }))
        verify(didThrow(function() { data.parseLoaded('{"models":"invalid"}') }))
        verify(didThrow(function() { data.parseLoaded('{"models":[{}]}') }))
    }

    function test_selectsOnlyUniqueConflictingModels() {
        var selected = "hf.co/user/model-GGUF:Q6_K"
        var entries = [
            { name: selected },
            { name: "qwen3:8b" },
            { name: "qwen3:8b" },
            { name: "gemma3:Q8_0" }
        ]
        compare(JSON.stringify(data.conflictingModelNames(entries, selected)),
                JSON.stringify(["qwen3:8b", "gemma3:Q8_0"]))
    }

    function test_preservesInheritedPropertyModelNames() {
        var entries = [
            { name: "constructor" },
            { name: "qwen3:8b" },
            { name: "toString" },
            { name: "constructor" },
            { name: "toString" }
        ]
        compare(JSON.stringify(data.conflictingModelNames(entries, "selected:latest")),
                JSON.stringify(["constructor", "qwen3:8b", "toString"]))
    }

    function test_requiresExactlyOneSelectedModel() {
        var selected = "qwen3:8b"
        verify(data.exclusiveLoadState([{ name: selected }], selected).valid)
        compare(data.exclusiveLoadState([], selected).error, "Selected model is not loaded")
        compare(data.exclusiveLoadState([{ name: "gemma3:4b" }], selected).error,
                "Unexpected Ollama model is loaded: gemma3:4b")
        compare(data.exclusiveLoadState([{ name: selected }, { name: "gemma3:4b" }], selected).error,
                "Multiple Ollama models remain loaded")
    }

    function test_mapsOperationMessages() {
        compare(data.operationMessage("checking", "qwen3:8b"), "Checking loaded models...")
        compare(data.operationMessage("unloading", "qwen3:8b"), "Unloading previous model...")
        compare(data.operationMessage("verifyingUnload", "qwen3:8b"), "Verifying model unload...")
        compare(data.operationMessage("loading", "qwen3:8b"), "Loading qwen3:8b...")
        compare(data.operationMessage("verifyingLoad", "qwen3:8b"), "Verifying qwen3:8b...")
    }

    function test_requiresCompletedGenerateResponse() {
        verify(data.generateResponseState('{"done":true}').valid)
        compare(data.generateResponseState("").error, "Invalid Ollama generate response")
        compare(data.generateResponseState("not json").error, "Invalid Ollama generate response")
        compare(data.generateResponseState("[]").error, "Invalid Ollama generate response")
        compare(data.generateResponseState("{}").error, "Ollama generate did not complete")
        compare(data.generateResponseState('{"done":false}').error,
                "Ollama generate did not complete")
    }

    function test_reconcilesLoadedModels() {
        data.installedModels = data.parseTags('{"models":[{"name":"qwen3:8b","size":1,"details":{}}]}')
        data.loadedModels = data.parseLoaded('{"models":[{"name":"qwen3:8b","size":1,"size_vram":1}]}')
        compare(data.models.length, 1)
        compare(data.models[0].loaded, true)
    }

    function test_extractsOllamaError() {
        compare(data.errorMessage({ status: 404, body: '{"error":"model not found"}' }, "request failed"), "model not found")
    }

    function test_marksVersionConnectionFailure() {
        data.connected = true
        data.applyVersion("\n000")
        compare(data.connected, false)
        compare(data.lastError, "Unable to reach Ollama")
    }

    function test_preservesVersionOnSuccessfulHttpOllamaError() {
        data.connected = true
        data.version = "0.31.2"
        data.applyVersion('{"error":"version unavailable"}\n200')
        compare(data.connected, false)
        compare(data.version, "0.31.2")
        compare(data.lastError, "version unavailable")
    }

    function test_rejectsSuccessfulHttpActionWithOllamaError() {
        var response = data.decodeResponse('{"error":"model failed to load"}\n200')
        compare(data.successful(response), false)
        compare(data.errorMessage(response, "request failed"), "model failed to load")
    }

    function test_actionStateAlwaysClears() {
        data.beginActionState("load", "qwen3:8b")
        compare(data.busy, true)
        compare(data.pendingModel, "qwen3:8b")
        data.clearActionState()
        compare(data.busy, false)
        compare(data.pendingAction, "")
        compare(data.pendingModel, "")
    }

    function test_buildsSafeLoadRequest() {
        var command = data.buildRequest("POST", "/api/generate", {
            model: "registry/model:tag",
            stream: false,
            keep_alive: -1
        })
        compare(command[0], "curl")
        verify(command.indexOf("bash") < 0)
        verify(command.indexOf("http://localhost:11434/api/generate") >= 0)
        verify(command.indexOf(JSON.stringify({ model: "registry/model:tag", stream: false, keep_alive: -1 })) >= 0)
    }

    function test_respectsCustomMaxTime() {
        var command = data.buildRequest("GET", "/api/version", undefined, "120")
        var maxTimeIdx = command.indexOf("--max-time")
        compare(maxTimeIdx >= 0, true)
        compare(command[maxTimeIdx + 1], "120")
    }

    function test_buildLoadPayloadWithKeepAliveAndContext() {
        var p = data.buildLoadPayload("gemma4:latest", "30m", 16384)
        compare(p.model, "gemma4:latest")
        compare(p.prompt, "")
        compare(p.stream, false)
        compare(p.keep_alive, "30m")
        compare(p.options.num_ctx, 16384)
    }

    function test_buildLoadPayloadOmitsNumCtxForAuto() {
        var p = data.buildLoadPayload("gemma4:latest", "5m", null)
        verify(p.options === undefined)
    }

    function test_buildLoadPayloadUsesNegativeOneForInfinite() {
        var p = data.buildLoadPayload("gemma4:latest", -1, null)
        compare(p.keep_alive, -1)
    }

    function test_normalizesHost() {
        compare(data.normalizeHost("http://localhost:11434"), "http://localhost:11434")
        compare(data.normalizeHost("http://localhost:11434/"), "http://localhost:11434")
    }

    function test_parseLoadedIncludesContextLength() {
        var models = data.parseLoaded('{"models":[{"name":"qwen3:8b","size":1,"size_vram":1,"context_length":16384}]}')
        compare(models[0].contextLength, 16384)
    }

    function test_validatesMatchingContextLength() {
        verify(data.validateContextLength(16384, 16384).valid)
        compare(data.validateContextLength(8192, 16384).error, "Context mismatch: expected 16384, got 8192")
        verify(data.validateContextLength(4096, null).valid)
    }

    function test_retriesEmptyLoadVerificationBeforeCheckingContext() {
        var state = data.loadVerificationState([], "qwen3:8b", 16384)
        compare(state.valid, false)
        compare(state.retry, true)
        compare(state.error, "Selected model is not loaded")
    }

    function test_acceptsMatchingLoadVerificationContext() {
        var state = data.loadVerificationState([
            { name: "qwen3:8b", contextLength: 16384 }
        ], "qwen3:8b", 16384)
        compare(state.valid, true)
        compare(state.retry, false)
    }

    function test_rejectsMismatchedLoadVerificationContext() {
        var state = data.loadVerificationState([
            { name: "qwen3:8b", contextLength: 8192 }
        ], "qwen3:8b", 16384)
        compare(state.valid, false)
        compare(state.retry, false)
        compare(state.error, "Context mismatch: expected 16384, got 8192")
    }

    function test_acceptsSuccessfulPullResult() {
        var state = data.pullResultState(0, '{"status":"success"}')
        compare(state.valid, true)
        compare(state.error, "")
    }

    function test_rejectsOllamaPullError() {
        var state = data.pullResultState(0, '{"error":"model not found"}')
        compare(state.valid, false)
        compare(state.error, "model not found")
    }

    function test_rejectsMalformedPullResult() {
        var state = data.pullResultState(0, "not json")
        compare(state.valid, false)
        compare(state.error, "Invalid Ollama pull response")
    }

    function test_rejectsFailedCurlPull() {
        var state = data.pullResultState(22, '{"error":"server unavailable"}')
        compare(state.valid, false)
        compare(state.error, "server unavailable")
    }

    function test_restoresPendingRuntimeConfiguration() {
        var state = data.runtimeConfigState('{"keepAlive":-1,"numCtx":16384,"dirty":true}')
        compare(state.valid, true)
        compare(state.keepAlive, -1)
        compare(typeof state.keepAlive, "number")
        compare(state.numCtx, 16384)
        compare(state.dirty, true)
    }

    function test_oldRuntimeConfigurationDefaultsToClean() {
        var state = data.runtimeConfigState('{"keepAlive":"5m","numCtx":null}')
        compare(state.valid, true)
        compare(state.dirty, false)
    }

    function test_acceptsCompleteCustomContextInput() {
        compare(data.parseContextInput("16K"), 16384)
        compare(data.parseContextInput("4096"), 4096)
    }

    function test_rejectsPartialCustomContextInput() {
        compare(data.parseContextInput("16junk"), null)
        compare(data.parseContextInput("K"), null)
        compare(data.parseContextInput("0"), null)
    }

    function test_aggregateErrorActionPrecedence() {
        compare(data.aggregateError("action failed", "", "", ""), "action failed")
    }

    function test_aggregateErrorVersionPrecedence() {
        compare(data.aggregateError("", "version failed", "", ""), "version failed")
    }

    function test_aggregateErrorTagsPrecedence() {
        compare(data.aggregateError("", "", "tags failed", ""), "tags failed")
    }

    function test_aggregateErrorLoadedFallback() {
        compare(data.aggregateError("", "", "", "loaded failed"), "loaded failed")
    }

    function test_aggregateErrorActionOverridesRefresh() {
        compare(data.aggregateError("action failed", "", "tags failed", "loaded failed"), "action failed")
    }

    function test_aggregateErrorClearWhenAllEmpty() {
        compare(data.aggregateError("", "", "", ""), "")
    }

    function test_aggregateConnectedAnyTrue() {
        verify(data.aggregateConnected(true, false, false))
        verify(data.aggregateConnected(false, true, false))
        verify(data.aggregateConnected(false, false, true))
    }

    function test_aggregateConnectedAllFalse() {
        verify(!data.aggregateConnected(false, false, false))
    }

    function test_maxGpuReturnsMaxOfMultiple() {
        compare(data.maxGpuPercent("12\n87\n44"), 87)
    }

    function test_maxGpuIgnoresInvalidLines() {
        compare(data.maxGpuPercent("N/A\n55\nbad"), 55)
    }

    function test_maxGpuRejectsOutOfRange() {
        compare(data.maxGpuPercent("150\n-5\n30"), 30)
    }

    function test_maxGpuEmptyInputReturnsMinusOne() {
        compare(data.maxGpuPercent(""), -1)
    }

    function test_maxGpuAllInvalidReturnsMinusOne() {
        compare(data.maxGpuPercent("N/A\nfoo"), -1)
    }
}
