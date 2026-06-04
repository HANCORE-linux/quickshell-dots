import QtQuick
import Quickshell

Item {
    id: rootMod
    required property var root

    implicitWidth: 26
    implicitHeight: 28

    Text {
        id: bellIcon
        anchors.centerIn: parent
        text: "\uE7F4"   // notifications (bell)
        font.family: "Material Symbols Rounded"
        font.pixelSize: 16
        color: root.notifCount > 0
            ? root.ink
            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // count badge — top-right, theme red with high-contrast text
    Rectangle {
        visible: root.notifCount > 0
        width: Math.max(12, badgeTxt.implicitWidth + 6)
        height: 12
        radius: 6
        color: root.seal
        anchors {
            verticalCenter: bellIcon.verticalCenter; verticalCenterOffset: -6
            horizontalCenter: bellIcon.horizontalCenter; horizontalCenterOffset: 7
        }
        Text {
            id: badgeTxt
            anchors.centerIn: parent
            text: root.notifCount > 99 ? "99" : root.notifCount
            color: "#ffffff"
            font.family: root.mono
            font.pixelSize: 8
            font.weight: Font.Bold
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.notifVisible = !root.notifVisible
    }
}
