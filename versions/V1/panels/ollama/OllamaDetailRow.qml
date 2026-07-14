import QtQuick
import "../../modules"

Row {
    id: detailRow

    required property var root
    property string k: ""
    property string v: ""

    width: parent ? parent.width : 0

    UiText {
        width: parent.width * 0.45
        text: detailRow.k
        color: detailRow.root.sumiHi
        font.family: detailRow.root.mono
        font.pixelSize: 11
    }
    UiText {
        width: parent.width * 0.55
        text: detailRow.v
        color: detailRow.root.ink
        font.family: detailRow.root.mono
        font.pixelSize: 11
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }
}
