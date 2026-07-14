.pragma library

function parsePercent(value) {
    var text = String(value === undefined || value === null ? "" : value).trim()
    if (!/^(?:\d+(?:\.\d+)?|\.\d+)$/.test(text)) return -1
    var percent = Number(text)
    if (!isFinite(percent) || percent < 0 || percent > 100) return -1
    return Math.round(percent)
}

function driverFromUevent(value) {
    var lines = String(value || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].indexOf("DRIVER=") === 0)
            return lines[i].slice(7).trim().toLowerCase()
    }
    return ""
}

function drmCardIndices(value) {
    var lines = String(value || "").split(/\r?\n/)
    var result = []
    for (var i = 0; i < lines.length; i++) {
        var match = /^card(\d+)$/.exec(lines[i].trim())
        if (!match) continue
        var cardIndex = Number(match[1])
        if (result.indexOf(cardIndex) < 0) result.push(cardIndex)
    }
    result.sort(function(a, b) { return a - b })
    return result
}

function providerSelection(records) {
    var amdSources = []
    var initialPercent = -1
    var hasNvidia = false
    for (var i = 0; i < records.length; i++) {
        var record = records[i] || {}
        var driver = driverFromUevent(record.uevent)
        var vendor = String(record.vendor || "").trim().toLowerCase()
        var percent = parsePercent(record.busy)
        if (driver === "amdgpu" && record.busyReadable === true) {
            amdSources.push(record.probeIndex)
            if (percent >= 0) initialPercent = Math.max(initialPercent, percent)
        }
        if (driver === "nvidia" || vendor === "0x10de") hasNvidia = true
    }
    if (amdSources.length > 0) {
        return {
            kind: "amdgpu-sysfs",
            amdSources: amdSources,
            initialPercent: initialPercent
        }
    }
    return {
        kind: hasNvidia ? "nvidia" : "none",
        amdSources: [],
        initialPercent: -1
    }
}

function nvidiaEntry(value) {
    var fields = String(value || "").trim().split(",")
    if (fields.length !== 2) return { valid: false, index: -1, percent: -1 }
    var indexText = fields[0].trim()
    if (!/^\d+$/.test(indexText)) return { valid: false, index: -1, percent: -1 }
    var percent = parsePercent(fields[1])
    return { valid: percent >= 0, index: Number(indexText), percent: percent }
}

function appendHistory(history, percent, maxSamples) {
    if (percent < 0) return history
    var result = history.slice()
    result.push(percent / 100)
    while (result.length > maxSamples) result.shift()
    return result
}
