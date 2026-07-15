.pragma library

function reconcileBackoffMs(completedAttempts) {
    return Math.min(10000, 1000 * Math.pow(2, Math.max(0, completedAttempts)))
}

function nextReconcileDelayMs(completedAttempts, nowMs, deadlineAtMs) {
    var remaining = Math.max(0, deadlineAtMs - nowMs)
    return Math.min(remaining, reconcileBackoffMs(completedAttempts))
}

function nextLayerProgress(prior, event, nowMs) {
    var previous = prior || {}
    var current = event || {}
    if (typeof current === "string") {
        try {
            current = JSON.parse(current)
        } catch (error) {
            current = {}
        }
    }
    if (!current || typeof current !== "object" || Array.isArray(current)) current = {}
    var previousDigest = String(previous.digest || "")
    var digest = current.digest !== undefined
        ? String(current.digest || "") : previousDigest
    var digestChanged = digest !== previousDigest
    var completed = digestChanged ? 0 : finiteNumber(previous.completed, 0)
    var total = digestChanged ? 0 : finiteNumber(previous.total, 0)
    var sampledAtMs = digestChanged ? 0 : finiteNumber(previous.sampledAtMs, 0)
    var rateBytesPerSecond = digestChanged ? 0
        : finiteNumber(previous.rateBytesPerSecond, 0)
    var etaSeconds = digestChanged ? 0 : finiteNumber(previous.etaSeconds, 0)
    var stableSamples = digestChanged ? 0 : finiteNumber(previous.stableSamples, 0)

    if (current.completed !== undefined && isFinite(Number(current.completed)))
        completed = Math.max(0, Number(current.completed))
    if (current.total !== undefined && isFinite(Number(current.total)))
        total = Math.max(0, Number(current.total))

    if (digestChanged) {
        if (current.completed !== undefined && isFinite(Number(current.completed)))
            sampledAtMs = finiteNumber(nowMs, 0)
    } else if (current.completed !== undefined && isFinite(Number(current.completed))) {
        var currentTime = finiteNumber(nowMs, 0)
        var bytesDelta = completed - finiteNumber(previous.completed, 0)
        var previousTime = finiteNumber(previous.sampledAtMs, 0)
        var timeDeltaSeconds = (currentTime - previousTime) / 1000
        rateBytesPerSecond = 0
        etaSeconds = 0
        if (previousTime > 0 && bytesDelta > 0 && timeDeltaSeconds > 0) {
            rateBytesPerSecond = bytesDelta / timeDeltaSeconds
            stableSamples += 1
            if (total > completed) etaSeconds = (total - completed) / rateBytesPerSecond
        }
        sampledAtMs = currentTime
    }

    return {
        digest: digest,
        completed: completed,
        total: total,
        sampledAtMs: sampledAtMs,
        rateBytesPerSecond: rateBytesPerSecond,
        etaSeconds: etaSeconds,
        stableSamples: stableSamples
    }
}

function currentLayerText(state) {
    var current = state || {}
    var completed = Math.max(0, finiteNumber(current.completed, 0))
    var total = Math.max(0, finiteNumber(current.total, 0))
    if (total <= 0) return "Current layer · Calculating..."

    var unit = byteUnit(total)
    var text = "Current layer · " + formatInUnit(completed, unit)
        + " / " + formatInUnit(total, unit) + " " + byteUnits()[unit]
    var rate = formatRate(current.rateBytesPerSecond)
    if (rate) text += " · " + rate
    if (finiteNumber(current.stableSamples, 0) < 2
            || finiteNumber(current.etaSeconds, 0) <= 0)
        return text + " · Calculating..."
    return text + " · about " + formatDuration(current.etaSeconds) + " remaining"
}

function finiteNumber(value, fallback) {
    var number = Number(value)
    return isFinite(number) ? number : fallback
}

function byteUnits() {
    return ["B", "KiB", "MiB", "GiB", "TiB"]
}

function byteUnit(bytes) {
    var value = Math.max(0, finiteNumber(bytes, 0))
    var unit = 0
    while (value >= 1024 && unit < byteUnits().length - 1) {
        value /= 1024
        unit += 1
    }
    return unit
}

function formatInUnit(bytes, unit) {
    var value = Math.max(0, finiteNumber(bytes, 0)) / Math.pow(1024, unit)
    return unit === 0 ? String(Math.round(value)) : value.toFixed(1)
}

function formatRate(bytesPerSecond) {
    var value = finiteNumber(bytesPerSecond, 0)
    if (value <= 0) return ""
    var unit = byteUnit(value)
    var scaled = value / Math.pow(1024, unit)
    var amount = Math.abs(scaled - Math.round(scaled)) < 0.05
        ? String(Math.round(scaled)) : scaled.toFixed(1)
    return amount + " " + byteUnits()[unit] + "/s"
}

function formatDuration(seconds) {
    var value = Math.max(0, Math.ceil(finiteNumber(seconds, 0)))
    if (value < 60) return value + "s"
    var minutes = Math.floor(value / 60)
    var remainingSeconds = value % 60
    if (minutes < 60) return minutes + "m " + remainingSeconds + "s"
    var hours = Math.floor(minutes / 60)
    return hours + "h " + (minutes % 60) + "m"
}
