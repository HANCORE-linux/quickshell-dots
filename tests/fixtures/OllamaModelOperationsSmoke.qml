import QtQuick
import Quickshell
import "modules"

ShellRoot {
    id: testRoot

    property var failures: []
    property int acceptedModels: 0

    function check(condition, message) {
        if (!condition) failures.push(message)
    }

    function finish() {
        if (failures.length > 0)
            console.error("OLLAMA_MODEL_OPERATIONS_NATIVE_FAIL: " + failures.join(", "))
        else
            console.log("OLLAMA_MODEL_OPERATIONS_NATIVE_PASS")
        Qt.callLater(Qt.quit)
    }

    OllamaModelOperations {
        id: operations
        onLoadedModelsAccepted: function(models) { testRoot.acceptedModels += 1 }
    }

    Component.onCompleted: {
        check(operations.operationState === "idle", "operation state default")
        check(!operations.operationInProgress, "operation progress default")
        check(!operations.busy, "busy default")
        check(typeof operations.loadModel === "function", "load method")
        check(typeof operations.ejectModel === "function", "eject method")
        check(typeof operations.deleteModel === "function", "delete method")
        check(typeof operations.applyRuntimeConfiguration === "function", "apply method")

        operations.operationId = 7
        operations.operationInProgress = true
        operations.busy = true
        operations.operationState = "checking"
        operations.pendingModel = "current:model"

        operations.handleOperationModels(
            "initial", 6, 0,
            '{"models":[{"name":"stale:model","size":1,"size_vram":1}]}\n200')
        operations.handleLoadExit(6, 0, '{"done":true}\n200')
        check(testRoot.acceptedModels === 0, "stale completion published models")
        check(operations.operationState === "checking", "stale completion changed state")
        check(operations.pendingModel === "current:model", "stale completion changed model")

        operations.handleUnloadExit(7, "timed:model", -1, true)
        check(operations.operationState === "error", "timeout did not enter error state")
        check(operations.operationError
              === "Timed out unloading Ollama model: timed:model", "timeout error")
        check(operations.operationInProgress, "timeout cleared operation before refresh")

        // Prevent the deferred failure refresh from reaching a real endpoint.
        operations.operationInProgress = false
        finish()
    }
}
