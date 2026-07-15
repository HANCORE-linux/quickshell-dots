import QtQuick 2.15
import QtTest 1.3
import "../versions/V1/modules/TooltipPosition.js" as Position

TestCase {
    name: "TooltipPosition"

    function test_topBarUsesInnerEdge() {
        compare(Position.barY("top", 1080, 30, 35, 6), 41)
    }

    function test_bottomBarUsesInnerEdge() {
        compare(Position.barY("bottom", 1080, 30, 35, 6), 1009)
    }

    function test_panelAnchorPrefersBelowAndClamps() {
        var point = Position.panelPoint(1260, 700, 28, 28, 180, 30,
                                        1280, 720, 6)
        verify(point.x >= 4 && point.x <= 1096)
        verify(point.y >= 4 && point.y <= 686)
    }

    function test_panelAnchorsAtAllEdges_data() {
        var rows = []
        var sizes = [
            { width: 1280, height: 720 },
            { width: 1920, height: 1080 },
            { width: 2560, height: 1440 }
        ]

        for (var i = 0; i < sizes.length; ++i) {
            var size = sizes[i]
            rows.push({ tag: size.width + "x" + size.height + "-top-left",
                        screenWidth: size.width, screenHeight: size.height,
                        anchorX: 0, anchorY: 0, expectedBelow: true })
            rows.push({ tag: size.width + "x" + size.height + "-top-right",
                        screenWidth: size.width, screenHeight: size.height,
                        anchorX: size.width - 28, anchorY: 0, expectedBelow: true })
            rows.push({ tag: size.width + "x" + size.height + "-bottom-left",
                        screenWidth: size.width, screenHeight: size.height,
                        anchorX: 0, anchorY: size.height - 28, expectedBelow: false })
            rows.push({ tag: size.width + "x" + size.height + "-bottom-right",
                        screenWidth: size.width, screenHeight: size.height,
                        anchorX: size.width - 28, anchorY: size.height - 28,
                        expectedBelow: false })
        }
        return rows
    }

    function test_panelAnchorsAtAllEdges(data) {
        var tooltipWidth = 180
        var tooltipHeight = 30
        var gap = 6
        var point = Position.panelPoint(data.anchorX, data.anchorY, 28, 28,
                                        tooltipWidth, tooltipHeight,
                                        data.screenWidth, data.screenHeight, gap)

        verify(point.x >= 4)
        verify(point.x <= data.screenWidth - tooltipWidth - 4)
        verify(point.y >= 4)
        verify(point.y <= data.screenHeight - tooltipHeight - 4)
        compare(point.y, data.expectedBelow
                ? data.anchorY + 28 + gap
                : data.anchorY - gap - tooltipHeight)
    }
}
