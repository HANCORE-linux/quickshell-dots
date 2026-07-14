import QtQuick 2.15
import QtTest 1.3

TestCase {
    id: testCase
    name: "OllamaPanelVisual"
    when: windowShown

    width: 380
    height: 120

    property bool controlsLocked: false
    property bool deleteHovered: false
    property bool confirmationVisible: false
    property bool configOpen: false

    readonly property color paper: "#181616"
    readonly property color ink: "#c5c9c5"
    readonly property color sumi: "#8a8a82"
    readonly property color fillIdle: "#222222"
    readonly property color fillPrimaryHover: "#dc817a"

    Rectangle {
        id: deleteButton
        objectName: "deleteButton"
        x: 320
        y: 15
        width: 28
        height: 28
        color: testCase.controlsLocked ? testCase.fillIdle
            : testCase.deleteHovered ? testCase.fillPrimaryHover : testCase.fillIdle

        Text {
            id: deleteGlyph
            objectName: "deleteGlyph"
            anchors.centerIn: parent
            width: 18
            height: 18
            text: "\uE872"
            color: testCase.controlsLocked ? testCase.sumi
                : testCase.deleteHovered ? testCase.paper : testCase.ink
            renderType: Text.QtRendering
            font.family: "Material Symbols Rounded"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        id: configurationControl
        objectName: "configurationControl"
        y: 60
        width: parent.width
        height: 28

        Row {
            id: configurationGroup
            objectName: "configurationGroup"
            anchors.centerIn: parent
            spacing: 4

            Text {
                id: configurationLabel
                objectName: "configurationLabel"
                text: "Configuration"
                font.family: "monospace"
                font.pixelSize: 11
            }

            Text {
                id: configurationIndicator
                objectName: "configurationIndicator"
                width: 12
                text: testCase.configOpen ? "\u25BE" : "\u25B8"
                font.family: "monospace"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    function init() {
        controlsLocked = false
        deleteHovered = false
        confirmationVisible = false
        configOpen = false
    }

    function test_deleteControlHasStableBoundsAndSemanticContrast() {
        compare(deleteButton.width, 28)
        compare(deleteButton.height, 28)
        compare(deleteGlyph.width, 18)
        compare(deleteGlyph.height, 18)
        verify(deleteGlyph.paintedWidth <= deleteGlyph.width)
        verify(deleteGlyph.paintedHeight <= deleteGlyph.height)
        compare(deleteButton.color, fillIdle)
        compare(deleteGlyph.color, ink)

        var stableWidth = deleteButton.width
        var stableHeight = deleteButton.height
        var stableX = deleteButton.x
        var stableY = deleteButton.y
        var stableGlyphWidth = deleteGlyph.width
        var stableGlyphHeight = deleteGlyph.height

        deleteHovered = true
        compare(deleteButton.color, fillPrimaryHover)
        compare(deleteGlyph.color, paper)
        compare(deleteButton.width, stableWidth)
        compare(deleteButton.height, stableHeight)
        compare(deleteButton.x, stableX)
        compare(deleteButton.y, stableY)
        compare(deleteGlyph.width, stableGlyphWidth)
        compare(deleteGlyph.height, stableGlyphHeight)

        controlsLocked = true
        compare(deleteButton.color, fillIdle)
        compare(deleteGlyph.color, sumi)
        compare(deleteButton.width, stableWidth)
        compare(deleteButton.height, stableHeight)
        compare(deleteButton.x, stableX)
        compare(deleteButton.y, stableY)

        confirmationVisible = true
        compare(deleteButton.width, stableWidth)
        compare(deleteButton.height, stableHeight)
        compare(deleteButton.x, stableX)
        compare(deleteButton.y, stableY)
        compare(deleteGlyph.width, stableGlyphWidth)
        compare(deleteGlyph.height, stableGlyphHeight)
        verify(deleteGlyph.paintedWidth <= deleteGlyph.width)
        verify(deleteGlyph.paintedHeight <= deleteGlyph.height)
    }

    function test_configurationHeadingRemainsCenteredWhenOpened() {
        function groupCenter() {
            return configurationGroup.mapToItem(configurationControl,
                                                configurationGroup.width / 2,
                                                configurationGroup.height / 2).x
        }

        var controlCenter = configurationControl.width / 2
        verify(Math.abs(groupCenter() - controlCenter) <= 1)
        var closedCenter = groupCenter()
        var closedGroupWidth = configurationGroup.width
        var closedLabelX = configurationLabel.mapToItem(configurationControl, 0, 0).x
        var indicatorWidth = configurationIndicator.width

        configOpen = true
        verify(Math.abs(groupCenter() - controlCenter) <= 1)
        compare(groupCenter(), closedCenter)
        compare(configurationGroup.width, closedGroupWidth)
        compare(configurationLabel.mapToItem(configurationControl, 0, 0).x,
                closedLabelX)
        compare(configurationIndicator.width, indicatorWidth)

        controlsLocked = true
        verify(Math.abs(groupCenter() - controlCenter) <= 1)
        compare(configurationGroup.width, closedGroupWidth)
        compare(configurationIndicator.width, indicatorWidth)
    }
}
