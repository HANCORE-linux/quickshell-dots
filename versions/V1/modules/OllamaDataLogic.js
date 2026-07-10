.pragma library

function decodeResponse(raw) {
    var text = String(raw || "")
    var separator = text.lastIndexOf("\n")
    if (separator < 0) return { status: 0, body: text }
    var status = parseInt(text.slice(separator + 1).trim())
    return { status: isNaN(status) ? 0 : status, body: text.slice(0, separator) }
}

function buildRequest(baseUrl, method, path, payload) {
    var command = [
        "curl", "-sS", "--connect-timeout", "1", "--max-time", "5",
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
    var result = []
    var entries = source.models || []
    for (var i = 0; i < entries.length; i++) {
        result.push({
            name: String(entries[i].name || entries[i].model || ""),
            size: Number(entries[i].size || 0),
            sizeVram: Number(entries[i].size_vram || 0),
            expiresAt: String(entries[i].expires_at || "")
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
        if (parsed.error) return String(parsed.error)
    } catch (error) {}
    return fallback
}

function successful(response) {
    return response.status >= 200 && response.status < 300
}

function versionState(raw) {
    var response = decodeResponse(raw)
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

function beginActionState(actionName, name) {
    return { busy: true, pendingAction: actionName, pendingModel: name }
}

function clearActionState() {
    return { busy: false, pendingAction: "", pendingModel: "" }
}
