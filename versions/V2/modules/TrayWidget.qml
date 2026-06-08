import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Item {
    id: rootMod
    required property var root

    implicitWidth: trayRow.implicitWidth
    implicitHeight: 28
    visible: trayRow.implicitWidth > 0

    function toggleHide(item) {
        root.trayToggleHide(item)
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayDelegate
                required property SystemTrayItem modelData

                implicitWidth: 24
                implicitHeight: 28
                visible: root.trayPinned.indexOf(modelData.id) >= 0

                Image {
                    anchors.centerIn: parent
                    source: modelData.icon
                    sourceSize.width: 12
                    sourceSize.height: 12
                    width: 12
                    height: 12
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (e) => {
                        if (e.button === Qt.LeftButton)
                            modelData.activate()
                        else if (e.button === Qt.RightButton)
                            rootMod.toggleHide(modelData)
                        else if (e.button === Qt.MiddleButton) {
                            if (modelData.hasMenu) {
                                var gp = trayDelegate.mapToItem(null, 0, 0)
                                root.openTrayMenu(modelData.menu, gp.x - 98)
                            }
                        }
                    }
                }
            }
        }

        // ── toggle: more_horiz icon + seal count badge ──
        Item {
            id: toggleBtn
            implicitWidth: 22
            implicitHeight: 28
            visible: totalCount > root.trayPinned.length

            readonly property int hiddenCount: Math.max(0, totalCount - root.trayPinned.length)
            readonly property int totalCount:  SystemTray.items.values.length
            readonly property string tooltipText: totalCount + (totalCount === 1 ? " app" : " apps")
                                                  + (hiddenCount > 0 ? " · " + hiddenCount + " hidden" : "")

            TooltipMixin { id: tip; root: rootMod.root; owner: toggleBtn; text: toggleBtn.tooltipText }

            Text {
                id: moreIcon
                anchors.centerIn: parent
                text: "\uE5D3"   // more_horiz
                font.family: "Material Symbols Rounded"
                font.pixelSize: 16
                color: toggleMa.containsMouse
                    ? root.ink
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7)
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            // count badge — top-right
            Rectangle {
                id: toggleBadge
                visible: toggleBtn.hiddenCount > 0
                width: Math.max(12, toggleBadgeTxt.implicitWidth + 6)
                height: 12
                radius: 6
                color: root.seal
                anchors.verticalCenter: moreIcon.verticalCenter
                anchors.verticalCenterOffset: -6
                anchors.horizontalCenter: moreIcon.horizontalCenter
                anchors.horizontalCenterOffset: 7
                Text {
                    id: toggleBadgeTxt
                    anchors.centerIn: parent
                    text: toggleBtn.hiddenCount
                    color: root.paper
                    font.family: root.mono
                    font.pixelSize: 7
                    font.weight: Font.Bold
                }
            }

            MouseArea {
                id: toggleMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: tip.show()
                onExited: { tip.hide() }
                onClicked: { tip.hide(); root.trayVisible = !root.trayVisible }
            }
        }
    }
}
