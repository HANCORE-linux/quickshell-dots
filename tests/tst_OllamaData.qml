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
        function sumLoadedVram(entries) { return OllamaDataLogic.sumLoadedVram(entries) }
        function errorMessage(response, fallback) { return OllamaDataLogic.errorMessage(response, fallback) }
        function successful(response) { return OllamaDataLogic.successful(response) }
        function buildRequest(method, path, payload) {
            return OllamaDataLogic.buildRequest(baseUrl, method, path, payload)
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
}
