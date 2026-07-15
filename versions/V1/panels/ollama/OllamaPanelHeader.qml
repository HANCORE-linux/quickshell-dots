import QtQuick
import "../../modules"

Item {
    id: header

    required property var root
    required property var data

    signal refreshRequested()
    signal closeRequested()

    width: parent ? parent.width : 0
    height: 24

    Item {
        parent: header
        anchors.fill: parent

        UiText {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "OLLAMA"
            color: header.root.ink
            font.family: header.root.mono
            font.pixelSize: 13
            font.letterSpacing: 2
            font.weight: Font.Medium
        }

        UiText {
            anchors.right: refreshButton.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: header.data.connected && header.data.version !== ""
                ? "v" + header.data.version : "OFFLINE"
            color: header.data.connected && header.data.version !== ""
                ? header.root.seal : header.root.sumi
            font.family: header.root.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }

        Item {
            id: refreshButton
            anchors.right: closeButton.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            opacity: refreshMa.enabled ? 1 : 0.35

            IconText {
                anchors.centerIn: parent
                text: "\uE5D5"
                color: refreshMa.containsMouse ? header.root.seal : header.root.sumi
                font.pixelSize: 14
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            MouseArea {
                id: refreshMa
                anchors.fill: parent
                enabled: !header.data.refreshRunning && !header.data.controlsLocked
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: refreshTip.show()
                onExited: refreshTip.hide()
                onEnabledChanged: if (!enabled) refreshTip.hide()
                onClicked: header.refreshRequested()
            }
            TooltipMixin {
                id: refreshTip
                root: header.root
                owner: refreshButton
                placement: "panel"
                text: "Refresh Ollama state"
            }
        }

        Item {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24

            UiText {
                anchors.centerIn: parent
                text: "\u2715"
                color: closeMa.containsMouse ? header.root.seal : header.root.sumi
                font.pixelSize: 12
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: closeTip.show()
                onExited: closeTip.hide()
                onClicked: header.closeRequested()
            }
            TooltipMixin {
                id: closeTip
                root: header.root
                owner: closeButton
                placement: "panel"
                text: "Close Ollama panel"
            }
        }
    }
}
