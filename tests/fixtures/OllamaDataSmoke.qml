import QtQuick
import Quickshell
import "../../versions/V1/modules"

ShellRoot {
    id: testRoot

    property var failures: []
    property bool smokeReady: false
    property bool runtimeConfigLoaded: false
    property bool runtimeConfigReloadStarted: false

    function check(condition, message) {
        if (!condition) failures.push(message)
    }

    function finish() {
        if (failures.length > 0) {
            console.error("OLLAMA_DATA_NATIVE_FAIL: " + failures.join(", "))
        } else {
            console.log("OLLAMA_DATA_NATIVE_PASS")
        }
        Qt.callLater(Qt.quit)
    }

    function startRuntimeConfigReload() {
        if (!smokeReady || !runtimeConfigLoaded || runtimeConfigReloadStarted) return
        runtimeConfigReloadStarted = true
        data.selectedKeepAlive = "5m"
        data.openRuntimeConfig()
    }

    OllamaData {
        id: data
        enabled: false
        onRuntimeConfigLoaded: {
            testRoot.runtimeConfigLoaded = true
            testRoot.startRuntimeConfigReload()
        }
        onRuntimeConfigReloaded: {
            check(data.selectedKeepAlive === "30m", "runtime config reload")
            finish()
        }
    }

    Component.onCompleted: {
        check(data.enabled === false, "enabled default")
        check(data.baseUrl === "http://127.0.0.1:11434", "base URL")
        check(data.operationInProgress === false, "operation default")
        check(data.operationState === "idle", "operation-state default")
        check(data.operationMessage === "", "operation-message default")
        check(data.controlsLocked === false, "controls-lock default")
        check(data.connected === false, "connection default")
        check(data.version === "", "version default")
        check(data.installedModels.length === 0, "installed models default")
        check(data.loadedModels.length === 0, "loaded models default")
        check(data.models.length === 0, "reconciled models default")
        check(data.gpuPercent === -1, "GPU default")
        check(data.loadedVramBytes === 0, "VRAM default")
        check(data.busy === false, "busy default")
        check(data.refreshRunning === false, "refresh-running default")
        check(data.pendingAction === "", "pending action default")
        check(data.pendingModel === "", "pending model default")
        check(data.lastError === "", "error default")
        check(data.versionError === "", "version-error default")
        check(data.tagsError === "", "tags-error default")
        check(data.loadedError === "", "loaded-error default")
        check(data.actionError === "", "action-error default")
        check(data.operationError === "", "operation-error default")
        check(data.displayError === "", "display-error default")

        check(data.selectedKeepAlive === "5m", "default keep alive")
        check(data.selectedNumCtx === null, "default num ctx")
        check(data.configDirty === false, "config dirty default")
        check(data.keepAliveStatus === "5m", "default keep alive status")
        check(typeof data.buildLoadPayload === "function", "buildLoadPayload method")
        check(typeof data.applyRuntimeConfiguration === "function", "applyRuntimeConfiguration method")

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

        // ── Integration: endpoint connected flags reset on failure ──────────
        // Epoch is 0 at this point; pass it as requestEpoch so guards pass.
        var epoch = data.refreshEpoch
        var okVersion = '{"version":"0.1.0"}\n200'
        var okTags    = '{"models":[{"name":"llama3:8b","size":1,"details":{}}]}\n200'
        var okLoaded  = '{"models":[{"name":"llama3:8b","size":1,"size_vram":1}]}\n200'
        var httpFail  = '{"error":"connection refused"}\n000'
        var badTags   = 'not-valid-json\n200'
        var badLoaded = '{"models":"invalid"}\n200'

        // 1. All three succeed → connected must be true
        data.applyVersion(okVersion, epoch)
        data.applyTags(okTags, epoch)
        data.applyLoaded(okLoaded, epoch)
        check(data.versionConnected === true,  "versionConnected true after success")
        check(data.tagsConnected === true,     "tagsConnected true after success")
        check(data.loadedConnected === true,   "loadedConnected true after success")
        check(data.connected === true,         "connected true when all succeed")

        // 2. All three fail → every flag and connected must be false
        data.applyVersion(httpFail, epoch)
        data.applyTags(httpFail, epoch)
        data.applyLoaded(httpFail, epoch)
        check(data.versionConnected === false, "versionConnected false after HTTP fail")
        check(data.tagsConnected === false,    "tagsConnected false after HTTP fail")
        check(data.loadedConnected === false,  "loadedConnected false after HTTP fail")
        check(data.connected === false,        "connected false when all fail")

        // 3. Succeed again, then fail with malformed response bodies
        data.applyVersion(okVersion, epoch)
        data.applyTags(okTags, epoch)
        data.applyLoaded(okLoaded, epoch)
        check(data.connected === true, "connected true before malformed test")

        data.applyTags(badTags, epoch)
        check(data.tagsConnected === false, "tagsConnected false after malformed tags")

        data.applyLoaded(badLoaded, epoch)
        check(data.loadedConnected === false, "loadedConnected false after malformed loaded")

        smokeReady = true
        data.reloadConfiguration()
    }
}
