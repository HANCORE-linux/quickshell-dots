.pragma library

function decodeResponse(raw) {
    var text = String(raw || "")
    var separator = text.lastIndexOf("\n")
    if (separator < 0) return { status: 0, body: text }
    var status = parseInt(text.slice(separator + 1).trim())
    return { status: isNaN(status) ? 0 : status, body: text.slice(0, separator) }
}

function buildRequest(baseUrl, method, path, payload, maxTime) {
    var timeout = Number(maxTime) > 0 ? String(maxTime) : "5"
    var command = [
        "curl", "-sS", "--connect-timeout", "1", "--max-time", timeout,
        "-X", method, "-H", "Accept: application/json", "-w", "\n%{http_code}"
    ]
    if (payload !== undefined && payload !== null) {
        command.push("-H", "Content-Type: application/json", "--data-binary", JSON.stringify(payload))
    }
    command.push(baseUrl + path)
    return command
}

function parseTags(body) {
    var source = JSON.parse(body)
    var result = []
    var entries = source.models || []
    for (var i = 0; i < entries.length; i++) {
        var details = entries[i].details || {}
        result.push({
            name: String(entries[i].name || entries[i].model || ""),
            size: Number(entries[i].size || 0),
            modifiedAt: String(entries[i].modified_at || ""),
            parameterSize: String(details.parameter_size || ""),
            quantization: String(details.quantization_level || "")
        })
    }
    return result
}

function parseLoaded(body) {
    var source = JSON.parse(body)
    if (!source || !Array.isArray(source.models))
        throw new Error("Invalid loaded-model response")

    var result = []
    for (var i = 0; i < source.models.length; i++) {
        var entry = source.models[i] || {}
        var name = String(entry.name || entry.model || "")
        if (!name) throw new Error("Loaded model is missing its name")
        result.push({
            name: name,
            size: Number(entry.size || 0),
            sizeVram: Number(entry.size_vram || 0),
            expiresAt: String(entry.expires_at || "")
        })
    }
    return result
}

function sumLoadedVram(entries) {
    var total = 0
    for (var i = 0; i < entries.length; i++) total += Number(entries[i].sizeVram || 0)
    return total
}

function reconcileModels(installed, loaded) {
    var loadedByName = {}
    for (var i = 0; i < loaded.length; i++) loadedByName[loaded[i].name] = loaded[i]
    var result = []
    for (var j = 0; j < installed.length; j++) {
        var current = installed[j]
        var active = loadedByName[current.name]
        result.push({
            name: current.name,
            size: current.size,
            modifiedAt: current.modifiedAt,
            parameterSize: current.parameterSize,
            quantization: current.quantization,
            loaded: active !== undefined,
            sizeVram: active ? active.sizeVram : 0,
            expiresAt: active ? active.expiresAt : ""
        })
    }
    return result
}

function errorMessage(response, fallback) {
    try {
        var parsed = JSON.parse(response.body || "{}")
        if (parsed.error !== undefined && parsed.error !== null) {
            var message = String(parsed.error)
            if (message.length > 0) return message
        }
    } catch (error) {}
    return fallback
}

function successful(response) {
    return response.status >= 200 && response.status < 300
        && errorMessage(response, "") === ""
}

function versionState(raw, currentVersion) {
    var response = decodeResponse(raw)
    var ollamaError = errorMessage(response, "")
    if (ollamaError) {
        return {
            connected: false,
            version: currentVersion || "",
            lastError: ollamaError
        }
    }
    if (!successful(response)) {
        return {
            connected: false,
            version: "",
            lastError: errorMessage(response, "Unable to reach Ollama")
        }
    }
    try {
        return {
            connected: true,
            version: String(JSON.parse(response.body).version || ""),
            lastError: ""
        }
    } catch (error) {
        return {
            connected: false,
            version: "",
            lastError: "Invalid Ollama version response"
        }
    }
}

function conflictingModelNames(entries, selectedName) {
    var selected = String(selectedName || "")
    var result = []
    for (var i = 0; i < entries.length; i++) {
        var name = String(entries[i].name || "")
        if (name && name !== selected && result.indexOf(name) < 0) {
            result.push(name)
        }
    }
    return result
}

function exclusiveLoadState(entries, selectedName) {
    var selected = String(selectedName || "")
    if (entries.length === 1 && String(entries[0].name || "") === selected)
        return { valid: true, error: "" }
    if (entries.length === 0)
        return { valid: false, error: "Selected model is not loaded" }
    if (entries.length > 1)
        return { valid: false, error: "Multiple Ollama models remain loaded" }
    return {
        valid: false,
        error: "Unexpected Ollama model is loaded: " + String(entries[0].name || "unknown")
    }
}

function generateResponseState(body) {
    var parsed
    try {
        parsed = JSON.parse(String(body || ""))
    } catch (error) {
        return { valid: false, error: "Invalid Ollama generate response" }
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        return { valid: false, error: "Invalid Ollama generate response" }
    if (parsed.done !== true)
        return { valid: false, error: "Ollama generate did not complete" }
    return { valid: true, error: "" }
}

function operationMessage(state, modelName) {
    var name = String(modelName || "")
    if (state === "checking") return "Checking loaded models..."
    if (state === "unloading") return "Unloading previous model..."
    if (state === "verifyingUnload") return "Verifying model unload..."
    if (state === "loading") return "Loading " + name + "..."
    if (state === "verifyingLoad") return "Verifying " + name + "..."
    return ""
}

function beginActionState(actionName, name) {
    return { busy: true, pendingAction: actionName, pendingModel: name }
}

function clearActionState() {
    return { busy: false, pendingAction: "", pendingModel: "" }
}
