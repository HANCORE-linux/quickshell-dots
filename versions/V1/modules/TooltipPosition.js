function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
}

function barY(position, screenHeight, tooltipHeight, barBottom, gap) {
    return position === "bottom"
        ? screenHeight - barBottom - gap - tooltipHeight
        : barBottom + gap
}

function panelPoint(anchorX, anchorY, anchorWidth, anchorHeight,
                    tooltipWidth, tooltipHeight, screenWidth, screenHeight, gap) {
    var x = clamp(anchorX + anchorWidth / 2 - tooltipWidth / 2,
                  4, screenWidth - tooltipWidth - 4)
    var below = anchorY + anchorHeight + gap
    var y = below + tooltipHeight <= screenHeight - 4
        ? below : anchorY - gap - tooltipHeight
    return { x: x, y: clamp(y, 4, screenHeight - tooltipHeight - 4) }
}
