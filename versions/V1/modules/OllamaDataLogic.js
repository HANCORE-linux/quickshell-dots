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
    if (!source || !Array.isArray(source.models))
        throw new Error("Invalid installed-model response")

    var result = []
    for (var i = 0; i < source.models.length; i++) {
        var entry = source.models[i] || {}
        var name = String(entry.name || entry.model || "").trim()
        if (!name) throw new Error("Installed model is missing its name")
        var details = entry.details || {}
        result.push({
            name: name,
            size: Number(entry.size || 0),
            modifiedAt: String(entry.modified_at || ""),
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
            expiresAt: String(entry.expires_at || ""),
            contextLength: Number(entry.context_length || 0)
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

function ejectQueue(entries, selectedName) {
    var selected = String(selectedName || "")
    if (!selected) return []
    for (var i = 0; i < entries.length; i++) {
        if (String(entries[i].name || "") === selected) return [selected]
    }
    return []
}

function parseEditorCommand(editor) {
    var value = String(editor || "").trim()
    if (!value) return { valid: false, argv: [], error: "EDITOR is empty" }
    if (/[;&|`$<>(){}\[\]\\'"\n\r]/.test(value)) {
        return { valid: false, argv: [], error: "EDITOR contains unsafe shell syntax" }
    }
    var argv = value.split(/\s+/)
    if (!/^[A-Za-z_][A-Za-z0-9_-]*$/.test(argv[0])) {
        return { valid: false, argv: [], error: "EDITOR must start with an executable" }
    }
    if (/^(alias|bash|bg|bind|break|builtin|caller|case|cd|command|compgen|complete|compopt|continue|coproc|dash|declare|dirs|disown|do|done|echo|elif|else|enable|env|esac|eval|exec|exit|export|false|fc|fg|fi|fish|for|function|getopts|hash|help|history|if|in|jobs|kill|let|local|logout|mapfile|popd|printf|pushd|pwd|read|readarray|readonly|return|select|set|sh|shift|shopt|source|suspend|test|then|time|times|trap|true|type|typeset|ulimit|umask|unalias|unset|until|wait|while|zsh)$/.test(argv[0])) {
        return { valid: false, argv: [], error: "EDITOR cannot run a shell" }
    }
    for (var i = 1; i < argv.length; i++) {
        if (!/^--?[A-Za-z0-9][A-Za-z0-9._-]*$/.test(argv[i])) {
            return { valid: false, argv: [], error: "EDITOR arguments must be options" }
        }
    }
    return { valid: true, argv: argv, error: "" }
}

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
}

function buildEditorShellCommand(argv, runtimeConfigPath) {
    var command = []
    for (var i = 0; i < argv.length; i++) command.push(shellQuote(argv[i]))
    command.push(shellQuote(runtimeConfigPath))
    return command.join(" ")
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

function buildLoadPayload(modelName, keepAlive, numCtx) {
    var payload = {
        model: String(modelName || ""),
        prompt: "",
        stream: false,
        keep_alive: keepAlive
    }
    if (numCtx !== undefined && numCtx !== null) {
        payload.options = { num_ctx: Number(numCtx) }
    }
    return payload
}

function normalizeHost(host) {
    var h = String(host || "")
    return h.replace(/\/+$/, "")
}

function validateContextLength(contextLength, numCtx) {
    if (numCtx === undefined || numCtx === null) return { valid: true, error: "" }
    var expected = Number(numCtx)
    var actual = Number(contextLength || 0)
    if (actual === expected) return { valid: true, error: "" }
    return {
        valid: false,
        error: "Context mismatch: expected " + expected + ", got " + actual
    }
}

function loadVerificationState(entries, selectedName, numCtx) {
    var loadState = exclusiveLoadState(entries, selectedName)
    if (!loadState.valid) {
        return { valid: false, retry: true, error: loadState.error }
    }
    var contextState = validateContextLength(entries[0].contextLength, numCtx)
    if (!contextState.valid) {
        return { valid: false, retry: false, error: contextState.error }
    }
    return { valid: true, retry: false, error: "" }
}

function pullResultState(exitCode, lastLine) {
    var parsed
    try {
        parsed = JSON.parse(String(lastLine || ""))
    } catch (error) {
        return {
            valid: false,
            error: Number(exitCode) === 0 ? "Invalid Ollama pull response" : "Download failed"
        }
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        return { valid: false, error: "Invalid Ollama pull response" }
    if (parsed.error !== undefined && String(parsed.error).length > 0)
        return { valid: false, error: String(parsed.error) }
    if (Number(exitCode) !== 0)
        return { valid: false, error: "Download failed" }
    if (parsed.status !== "success")
        return { valid: false, error: "Ollama pull did not complete" }
    return { valid: true, error: "" }
}

function normalizePullInput(raw) {
    var text = String(raw || "").trim()
    if (!text) return { valid: false, model: "", error: "Model name is required" }
    if (/[;&|`$<>(){}\[\]\\'"\n\r]/.test(text)) {
        return { valid: false, model: "", error: "Model name contains unsafe shell syntax" }
    }

    var tokens = text.split(/\s+/)
    var model = ""
    if (tokens[0].toLowerCase() === "ollama") {
        if (tokens.length !== 3 || !/^(pull|run)$/i.test(tokens[1])) {
            return { valid: false, model: "", error: "Use ollama pull or ollama run with one model name" }
        }
        model = tokens[2]
    } else {
        if (tokens.length !== 1) {
            return { valid: false, model: "", error: "Enter one model name" }
        }
        model = tokens[0]
    }
    if (!/^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(model) || model.charAt(0) === "-") {
        return { valid: false, model: "", error: "Model name contains unsupported characters" }
    }
    return { valid: true, model: model, error: "" }
}

function pullEventState(raw, prior) {
    var previous = prior || {}
    var event
    try {
        event = typeof raw === "string" ? JSON.parse(raw) : raw
    } catch (error) {
        return {
            status: "Download failed", detail: "", digest: "", completed: 0, total: 0,
            error: "Invalid Ollama pull event", terminal: true
        }
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) {
        return {
            status: "Download failed", detail: "", digest: "", completed: 0, total: 0,
            error: "Invalid Ollama pull event", terminal: true
        }
    }
    if (event.error !== undefined && String(event.error).length > 0) {
        return {
            status: "Download failed", detail: "", digest: "", completed: 0, total: 0,
            error: String(event.error), terminal: true
        }
    }

    var sourceStatus = String(event.status || "").toLowerCase()
    var digest = event.digest !== undefined ? String(event.digest) : String(previous.digest || "")
    var completed = isFinite(Number(event.completed)) ? Number(event.completed) : Number(previous.completed || 0)
    var total = isFinite(Number(event.total)) ? Number(event.total) : Number(previous.total || 0)
    var status = "Preparing download"
    var detail = ""
    var terminal = false

    if (sourceStatus === "pulling manifest") status = "Fetching manifest"
    else if (sourceStatus === "downloading") {
        status = "Downloading"
        if (total > 0 && completed >= 0) detail = String(Math.floor(completed * 100 / total)) + "%"
    } else if (sourceStatus.indexOf("verifying") === 0) status = "Verifying download"
    else if (sourceStatus === "writing manifest") status = "Writing manifest"
    else if (sourceStatus === "success") {
        status = "Download complete"
        terminal = true
    }

    return {
        status: status, detail: detail, digest: digest, completed: completed, total: total,
        error: "", terminal: terminal
    }
}

function pullRateState(prior, digest, completed, nowMs) {
    var previous = prior || {}
    var currentDigest = String(digest || "")
    var currentCompleted = Number(completed)
    var currentTime = Number(nowMs)
    var total = Number(previous.total)
    var rate = 0
    var eta = 0
    var previousCompleted = Number(previous.completed)
    var previousTime = Number(previous.sampledAtMs)

    if (String(previous.digest || "") === currentDigest
            && isFinite(currentCompleted) && isFinite(currentTime)
            && isFinite(previousCompleted) && isFinite(previousTime)) {
        var bytesDelta = currentCompleted - previousCompleted
        var timeDeltaSeconds = (currentTime - previousTime) / 1000
        if (bytesDelta > 0 && timeDeltaSeconds > 0) {
            rate = bytesDelta / timeDeltaSeconds
            if (isFinite(total) && total > currentCompleted) eta = (total - currentCompleted) / rate
        }
    }

    return {
        digest: currentDigest,
        completed: isFinite(currentCompleted) ? currentCompleted : 0,
        total: isFinite(total) ? total : 0,
        sampledAtMs: isFinite(currentTime) ? currentTime : 0,
        rateBytesPerSecond: rate,
        etaSeconds: eta
    }
}

function formatBytes(bytes) {
    var value = Number(bytes)
    if (!isFinite(value) || value <= 0) return "0 B"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var unit = 0
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024
        unit += 1
    }
    return unit === 0 ? Math.round(value) + " " + units[unit]
        : value.toFixed(1) + " " + units[unit]
}

function formatRate(bytesPerSecond) {
    return Number(bytesPerSecond) > 0 ? formatBytes(bytesPerSecond) + "/s" : ""
}

function formatElapsed(seconds) {
    var value = Math.max(0, Math.ceil(Number(seconds) || 0))
    if (value < 60) return value + "s"
    var minutes = Math.floor(value / 60)
    var remainingSeconds = value % 60
    if (minutes < 60) return minutes + "m " + remainingSeconds + "s"
    var hours = Math.floor(minutes / 60)
    return hours + "h " + (minutes % 60) + "m"
}

function formatEta(seconds) {
    return Number(seconds) > 0 ? "about " + formatElapsed(seconds) : ""
}

function pullProgressText(completed, total, rateBytesPerSecond, etaSeconds, stableSamples) {
    var current = Math.max(0, Number(completed) || 0)
    var maximum = Math.max(0, Number(total) || 0)
    if (maximum <= 0) return "Calculating..."
    var result = formatBytes(current) + " / " + formatBytes(maximum)
    var rate = formatRate(rateBytesPerSecond)
    if (rate) result += " · " + rate
    var eta = Number(stableSamples) >= 2 ? formatEta(etaSeconds) : "Calculating..."
    if (eta) result += " · " + eta
    return result
}

function pullResultText(state, error, elapsedSeconds) {
    if (state === "success") return "Completed in " + formatElapsed(elapsedSeconds)
    if (state === "failed") return "Pull failed" + (error ? ": " + String(error) : "")
    if (state === "cancelled") return "Pull cancelled"
    return ""
}

function runtimeConfigState(raw) {
    var cfg
    try {
        cfg = JSON.parse(String(raw || ""))
    } catch (error) {
        return { valid: false }
    }
    if (!cfg || typeof cfg !== "object" || Array.isArray(cfg))
        return { valid: false }
    var keep = cfg.keepAlive
    if (keep !== "5m" && keep !== "30m" && keep !== -1)
        return { valid: false }
    var context = cfg.numCtx
    if (context !== null && !(typeof context === "number" && context > 0))
        return { valid: false }
    return {
        valid: true,
        keepAlive: keep,
        numCtx: context,
        dirty: cfg.dirty === true
    }
}

function parseContextInput(raw) {
    var text = String(raw || "").trim()
    var match = /^([1-9][0-9]*)([Kk])?$/.exec(text)
    if (!match) return null
    var value = Number(match[1]) * (match[2] ? 1024 : 1)
    return isFinite(value) && value > 0 ? value : null
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

function aggregateError(actionError, versionError, tagsError, loadedError) {
    return String(actionError || "") || String(versionError || "")
        || String(tagsError || "") || String(loadedError || "")
}

function aggregateConnected(versionConnected, tagsConnected, loadedConnected) {
    return Boolean(versionConnected || tagsConnected || loadedConnected)
}

function maxGpuPercent(raw) {
    var lines = String(raw || "").split("\n")
    var max = -1
    for (var i = 0; i < lines.length; i++) {
        var value = parseInt(lines[i].trim(), 10)
        if (!isNaN(value) && value >= 0 && value <= 100) {
            if (value > max) max = value
        }
    }
    return max
}
