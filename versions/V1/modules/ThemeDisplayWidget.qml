import QtQuick
import Quickshell

Item {
    id: rootMod
    required property var root

    implicitWidth: 22
    implicitHeight: 28

    Text {
        anchors.centerIn: parent
        // 󰖔  U+F0194  monitor / display icon (Nerd Font)
        text: String.fromCodePoint(0xF0194)
        font.family: root.mono
        font.pixelSize: 14
        color: (root.themePickerVisible || root.wallpaperPickerVisible)
            ? root.seal
            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.65)
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    TooltipMixin {
        id: tip; root: rootMod.root; owner: rootMod
        text: "L: Theme  R: Wallpaper"
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: tip.show()
        onExited:  tip.hide()
        onClicked: function(mouse) {
            tip.hide()
            if (mouse.button === Qt.RightButton) {
                root.themePickerVisible    = false
                root.wallpaperPickerVisible = !root.wallpaperPickerVisible
            } else {
                root.wallpaperPickerVisible = false
                root.themePickerVisible     = !root.themePickerVisible
            }
        }
    }
}
