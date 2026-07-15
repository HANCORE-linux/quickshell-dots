function serialize(order) {
    return order.left.join(",") + "|" + order.center.join(",") + "|" + order.right.join(",")
}

function decode(serialized, knownIds, regionSizes, addedId) {
    var parts = String(serialized || "").split("|")
    if (parts.length !== 3) return null

    var order = {
        left: parts[0] === "" ? [] : parts[0].split(","),
        center: parts[1] === "" ? [] : parts[1].split(","),
        right: parts[2] === "" ? [] : parts[2].split(",")
    }
    var total = order.left.length + order.center.length + order.right.length

    if (total === knownIds.length - 1 && order.left.length === regionSizes[0] - 1) {
        var legacySeen = {}
        var legacyAll = order.left.concat(order.center, order.right)
        for (var legacyIndex = 0; legacyIndex < legacyAll.length; legacyIndex++) {
            legacySeen[legacyAll[legacyIndex]] = true
        }
        if (!legacySeen[addedId]) order.left.push(addedId)
    }

    if (order.left.length !== regionSizes[0]
            || order.center.length !== regionSizes[1]
            || order.right.length !== regionSizes[2]) return null

    var all = order.left.concat(order.center, order.right)
    if (all.length !== knownIds.length) return null

    var allowed = {}
    var seen = {}
    for (var i = 0; i < knownIds.length; i++) allowed[knownIds[i]] = true
    for (var j = 0; j < all.length; j++) {
        if (!allowed[all[j]] || seen[all[j]]) return null
        seen[all[j]] = true
    }
    return Object.keys(seen).length === knownIds.length ? order : null
}
