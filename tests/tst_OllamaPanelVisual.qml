import QtQuick 2.15
import QtTest 1.3
import "../versions/V1/panels/ollama"
import "../versions/V1/panels/ollama/OllamaPanelLayout.js" as PanelLayout

TestCase {
    id: testCase
    name: "OllamaPanelVisual"
    when: windowShown

    width: 380
    height: 140

    property bool controlsLocked: false
    property bool confirmationVisible: false
    property bool configOpen: false

    QtObject {
        id: mockTheme

        property color paper: "#181616"
        property color ink: "#c5c9c5"
        property color sumi: "#8a8a82"
        property color seal: "#c4746e"
        property color sep: "#555555"
        property color fillHover: "#393939"
        property color fillIdle: "#222222"
        property color fillPrimaryHover: "#dc817a"
        property int tileRadius: 6
        property string mono: "monospace"
    }

    Item {
        id: modelRow
        width: parent.width
        height: 86

        OllamaDeleteButton {
            id: deleteButton
            anchors.right: parent.right
            anchors.rightMargin: 8
            theme: mockTheme
            controlEnabled: !testCase.controlsLocked
            confirmationVisible: testCase.confirmationVisible
        }
    }

    OllamaConfigurationToggle {
        id: configurationControl
        y: 96
        width: parent.width
        theme: mockTheme
        controlEnabled: !testCase.controlsLocked
        open: testCase.configOpen
    }

    function child(parent, name) {
        var item = findChild(parent, name)
        verify(item !== null, "missing production control child: " + name)
        return item
    }

    function init() {
        controlsLocked = false
        confirmationVisible = false
        configOpen = false
        deleteButton.hovered = false
        configurationControl.hovered = false
    }

    function test_actionRowYRemainsStableThroughConfirmation() {
        compare(PanelLayout.modelActionY(false), 15)
        compare(PanelLayout.modelActionY(true), 15)
        compare(deleteButton.y, PanelLayout.modelActionY(false))
        compare(deleteButton.confirmationVisible, false)

        var closedY = deleteButton.y
        confirmationVisible = true
        compare(deleteButton.confirmationVisible, true)
        compare(deleteButton.y, PanelLayout.modelActionY(true))
        compare(deleteButton.y, closedY)
    }

    function test_deleteControlUsesStableBoundsAndSemanticContrast() {
        var deleteGlyph = child(deleteButton, "modelDeleteGlyph")

        compare(deleteButton.width, 28)
        compare(deleteButton.height, 28)
        compare(deleteGlyph.width, 18)
        compare(deleteGlyph.height, 18)
        verify(deleteGlyph.paintedWidth <= deleteGlyph.width)
        verify(deleteGlyph.paintedHeight <= deleteGlyph.height)
        compare(deleteButton.color, mockTheme.fillIdle)
        compare(deleteGlyph.color, mockTheme.ink)

        var stableGeometry = Qt.rect(deleteButton.x, deleteButton.y,
                                     deleteButton.width, deleteButton.height)
        deleteButton.hovered = true
        tryCompare(deleteButton, "color", mockTheme.fillPrimaryHover)
        compare(deleteGlyph.color, mockTheme.paper)
        compare(Qt.rect(deleteButton.x, deleteButton.y,
                        deleteButton.width, deleteButton.height), stableGeometry)

        controlsLocked = true
        tryCompare(deleteButton, "color", mockTheme.fillIdle)
        compare(deleteGlyph.color, mockTheme.sumi)
        compare(Qt.rect(deleteButton.x, deleteButton.y,
                        deleteButton.width, deleteButton.height), stableGeometry)

        confirmationVisible = true
        compare(Qt.rect(deleteButton.x, deleteButton.y,
                        deleteButton.width, deleteButton.height), stableGeometry)
        verify(deleteGlyph.paintedWidth <= deleteGlyph.width)
        verify(deleteGlyph.paintedHeight <= deleteGlyph.height)
    }

    function test_configurationOpenAndHoverDoNotShiftHeading() {
        var group = child(configurationControl, "configurationHeadingGroup")
        var label = child(configurationControl, "configurationHeadingLabel")
        var indicator = child(configurationControl,
                              "configurationDisclosureIndicator")

        function groupCenter() {
            return group.mapToItem(configurationControl,
                                   group.width / 2, group.height / 2).x
        }

        var controlCenter = configurationControl.width / 2
        var closedCenter = groupCenter()
        var closedGroupWidth = group.width
        var closedLabelX = label.mapToItem(configurationControl, 0, 0).x
        var indicatorWidth = indicator.width
        compare(indicator.text, "\u25B8")
        verify(Math.abs(closedCenter - controlCenter) <= 1)

        configurationControl.hovered = true
        tryCompare(configurationControl, "color", mockTheme.fillHover)
        compare(groupCenter(), closedCenter)
        compare(group.width, closedGroupWidth)
        compare(label.mapToItem(configurationControl, 0, 0).x, closedLabelX)

        configOpen = true
        compare(indicator.text, "\u25BE")
        verify(configurationControl.hovered)
        verify(Math.abs(groupCenter() - controlCenter) <= 1)
        compare(groupCenter(), closedCenter)
        compare(group.width, closedGroupWidth)
        compare(label.mapToItem(configurationControl, 0, 0).x, closedLabelX)
        compare(indicator.width, indicatorWidth)

        controlsLocked = true
        verify(Math.abs(groupCenter() - controlCenter) <= 1)
        compare(group.width, closedGroupWidth)
        compare(indicator.width, indicatorWidth)
    }
}
