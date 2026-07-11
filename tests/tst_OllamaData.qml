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
}
