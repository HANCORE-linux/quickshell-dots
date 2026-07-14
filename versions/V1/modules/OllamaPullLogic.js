.pragma library

function reconcileBackoffMs(completedAttempts) {
    return Math.min(10000, 1000 * Math.pow(2, Math.max(0, completedAttempts)))
}

function nextReconcileDelayMs(completedAttempts, nowMs, deadlineAtMs) {
    var remaining = Math.max(0, deadlineAtMs - nowMs)
    return Math.min(remaining, reconcileBackoffMs(completedAttempts))
}
