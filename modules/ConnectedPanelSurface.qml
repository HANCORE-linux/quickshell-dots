import QtQuick

// Semantic shared name for the confirmed connected panel silhouette.
// AiPanelSurface remains the single rendering implementation so every panel
// uses exactly the same antialiased geometry. Publish the actually rendered
// tip position as well: at screen edges the surface clamps it away from the
// rounded card corner, and the bar notch must follow that resolved position.
AiPanelSurface {
    readonly property real resolvedTargetX: parent ? parent.x + centerX : targetX

    function publishResolvedTarget() {
        if (reveal > 0.001 && root && resolvedTargetX > 0)
            root.setPanelInsetX(resolvedTargetX)
    }

    onResolvedTargetXChanged: publishResolvedTarget()
    onRevealChanged: publishResolvedTarget()
}
