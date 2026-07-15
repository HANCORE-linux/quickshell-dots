import QtQuick
import "../../modules"

Column {
    id: pullSection

    required property var root
    required property var data

    signal pullRequested(string name)
    signal cancelRequested()

    width: parent ? parent.width : 0
    spacing: 8

    Column {
        parent: pullSection
        width: parent.width
        height: 78
        spacing: 6

        Row {
            width: parent.width
            height: 32
            spacing: 6
            visible: !pullSection.data.pullBusy

            Rectangle {
                width: parent.width - pullButton.width - parent.spacing
                height: 32
                radius: pullSection.root.tileRadius
                color: pullSection.root.fillIdle
                border.color: pullSection.root.sep
                border.width: 1

                TextInput {
                    id: pullInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    font.family: pullSection.root.mono
                    font.pixelSize: 11
                    color: pullSection.root.ink
                    clip: true
                    selectByMouse: true
                }

                UiText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: "Model name or URL..."
                    color: pullSection.root.sumiHi
                    font.family: pullSection.root.mono
                    font.pixelSize: 11
                    visible: !pullInput.text && !pullInput.activeFocus
                }
            }

            Rectangle {
                id: pullButton
                width: 64
                height: 32
                radius: pullSection.root.tileRadius
                color: !pullMa.enabled ? pullSection.root.fillIdle
                    : pullMa.containsMouse ? pullSection.root.fillPrimaryHover
                    : pullSection.root.seal
                border.color: !pullMa.enabled ? pullSection.root.sep : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }

                UiText {
                    anchors.centerIn: parent
                    text: "Pull"
                    color: !pullMa.enabled ? pullSection.root.sumi : pullSection.root.paper
                    font.family: pullSection.root.mono
                    font.pixelSize: 10
                }

                MouseArea {
                    id: pullMa
                    anchors.fill: parent
                    enabled: !pullSection.data.controlsLocked
                        && String(pullInput.text).trim() !== ""
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        pullSection.pullRequested(pullInput.text)
                        pullInput.text = ""
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 4
            visible: pullSection.data.pullBusy

            UiText {
                width: parent.width
                text: pullSection.data.pullStatus || "Starting..."
                color: pullSection.root.seal
                font.family: pullSection.root.mono
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            UiText {
                width: parent.width
                text: pullSection.data.pullProgressText
                    || "Current layer \u00B7 Calculating..."
                color: pullSection.root.sumiHi
                font.family: pullSection.root.mono
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: pullSection.root.fillIdle
                border.color: pullSection.root.sep
                border.width: 1

                Rectangle {
                    width: Math.min(parent.width - 2,
                        Math.max(6, (parent.width - 2) * pullSection.data.pullProgress))
                    height: parent.height - 2
                    anchors.left: parent.left
                    anchors.leftMargin: 1
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 2
                    color: pullSection.root.seal
                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }
            }

            Rectangle {
                id: cancelPullButton
                width: parent.width
                height: 24
                visible: pullSection.data.pullCanCancel
                radius: pullSection.root.tileRadius
                color: cancelPullMa.containsMouse
                    ? pullSection.root.fillPrimaryHover : pullSection.root.fillIdle
                border.color: pullSection.root.sep
                border.width: 1

                UiText {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: pullSection.root.seal
                    font.family: pullSection.root.mono
                    font.pixelSize: 10
                }
                MouseArea {
                    id: cancelPullMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pullSection.cancelRequested()
                }
            }
        }

        UiText {
            width: parent.width
            visible: !pullSection.data.pullBusy
                && pullSection.data.pullResultText !== ""
            text: pullSection.data.pullResultText
            color: pullSection.data.pullState === "success"
                ? pullSection.root.seal : pullSection.root.sealRaw
            font.family: pullSection.root.mono
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }

    Rectangle {
        parent: pullSection
        width: parent.width
        height: 1
        color: pullSection.root.sep
    }
}
