import QtQuick
import Quickshell
import "modules"

ShellRoot {
    id: testRoot

    property var failures: []

    function check(condition, message) {
        if (!condition) failures.push(message)
    }

    OllamaData {
        id: data
        enabled: false
    }

    Component.onCompleted: {
        check(data.enabled === false, "enabled default")
        check(data.baseUrl === "http://localhost:11434", "base URL")
        check(data.connected === false, "connection default")
        check(data.version === "", "version default")
        check(data.installedModels.length === 0, "installed models default")
        check(data.loadedModels.length === 0, "loaded models default")
        check(data.models.length === 0, "reconciled models default")
        check(data.gpuPercent === -1, "GPU default")
        check(data.loadedVramBytes === 0, "VRAM default")
        check(data.busy === false, "busy default")
        check(data.pendingAction === "", "pending action default")
        check(data.pendingModel === "", "pending model default")
        check(data.lastError === "", "error default")
        check(data.configPath === "/etc/systemd/system/ollama.service.d/override.conf", "config path")

        var response = data.decodeResponse('{"version":"0.31.2"}\n200')
        check(response.status === 200, "response status helper")
        check(JSON.parse(response.body).version === "0.31.2", "response body helper")

        var errorResponse = data.decodeResponse('{"error":"fixture error"}\n200')
        check(data.successful(errorResponse) === false, "Ollama error helper")

        var tags = data.parseTags('{"models":[{"name":"qwen3:8b","details":{}}]}')
        check(tags.length === 1 && tags[0].name === "qwen3:8b", "tags helper")

        var command = data.buildRequest("POST", "/api/generate", {
            model: "registry/model:tag",
            stream: false,
            keep_alive: -1
        })
        check(command[0] === "curl" && command.indexOf("bash") < 0, "safe request helper")

        var methods = [
            "refreshAll", "refreshVersion", "refreshTags", "refreshLoaded",
            "loadModel", "ejectModel", "openConfiguration", "reloadConfiguration",
            "decodeResponse", "parseTags", "parseLoaded", "sumLoadedVram",
            "reconcileModels", "errorMessage", "successful", "buildRequest"
        ]
        for (var i = 0; i < methods.length; i++) {
            check(typeof data[methods[i]] === "function", methods[i] + " method")
        }

        if (failures.length > 0) {
            console.error("OLLAMA_DATA_NATIVE_FAIL: " + failures.join(", "))
        } else {
            console.log("OLLAMA_DATA_NATIVE_PASS")
        }
    }
}
