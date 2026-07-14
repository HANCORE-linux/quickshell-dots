import QtQuick
import "../../modules"

Column {
    id: configSection

    required property var root
    required property var data
    required property bool controlsLocked
    property string customCtxDisplay: ""
    property bool configOpen: false

    signal keepAliveRequested(var value)
    signal contextRequested(var value)
    signal openRuntimeConfigRequested()
    signal applyRequested()
    signal refreshRequested()

    width: parent ? parent.width : 0
    spacing: 8

    OllamaConfigurationToggle {
        parent: configSection
        width: parent.width
        theme: configSection.root
        controlEnabled: !configSection.controlsLocked
        open: configSection.configOpen
        onClicked: configSection.configOpen = !configSection.configOpen
    }

    Column {
        parent: configSection
        width: parent.width
        spacing: 8
        visible: configSection.configOpen

        Row {
            width: parent.width
            height: 28
            spacing: 6

            UiText {
                anchors.verticalCenter: parent.verticalCenter
                width: 70
                text: "Keep Alive"
                color: configSection.root.sumiHi
                font.family: configSection.root.mono
                font.pixelSize: 11
            }

            Repeater {
                model: [
                    { label: "5m", value: "5m" },
                    { label: "30m", value: "30m" },
                    { label: "\u221E", value: -1 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    property bool selected: configSection.data.selectedKeepAlive
                        === modelData.value
                    property bool chipEnabled: !configSection.controlsLocked
                    width: 36
                    height: 28
                    radius: configSection.root.tileRadius
                    color: !chipEnabled ? configSection.root.fillIdle
                        : selected ? configSection.root.seal
                        : keepAliveMa.containsMouse ? configSection.root.fillHover
                        : configSection.root.fillIdle
                    border.color: !chipEnabled ? configSection.root.sep
                        : selected || keepAliveMa.containsMouse
                            ? configSection.root.seal : configSection.root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    UiText {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: selected ? configSection.root.paper
                            : chipEnabled ? configSection.root.ink : configSection.root.sumi
                        font.family: configSection.root.mono
                        font.pixelSize: modelData.value === -1 ? 14 : 10
                    }
                    MouseArea {
                        id: keepAliveMa
                        anchors.fill: parent
                        enabled: chipEnabled
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: keepAliveTip.show()
                        onExited: keepAliveTip.hide()
                        onEnabledChanged: if (!enabled) keepAliveTip.hide()
                        onClicked: configSection.keepAliveRequested(modelData.value)
                    }
                    TooltipMixin {
                        id: keepAliveTip
                        root: configSection.root
                        owner: parent
                        placement: "panel"
                        text: modelData.value === -1
                            ? "Keep model loaded indefinitely" : ""
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: 28
            spacing: 6

            UiText {
                anchors.verticalCenter: parent.verticalCenter
                width: 70
                text: "Context"
                color: configSection.root.sumiHi
                font.family: configSection.root.mono
                font.pixelSize: 11
            }

            Repeater {
                model: [
                    { label: "auto", value: null },
                    { label: "8k", value: 8192 },
                    { label: "16k", value: 16384 },
                    { label: "32k", value: 32768 },
                    { label: "Custom", value: "custom" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    property bool isCustom: modelData.value === "custom"
                    property bool selected: isCustom
                        ? configSection.data.selectedNumCtx !== null
                            && ![8192, 16384, 32768].includes(
                                configSection.data.selectedNumCtx)
                        : configSection.data.selectedNumCtx === modelData.value
                    property bool chipEnabled: !configSection.controlsLocked
                    width: isCustom ? 52 : 40
                    height: 28
                    radius: configSection.root.tileRadius
                    color: !chipEnabled ? configSection.root.fillIdle
                        : selected ? configSection.root.seal
                        : contextChipMa.containsMouse ? configSection.root.fillHover
                        : configSection.root.fillIdle
                    border.color: !chipEnabled ? configSection.root.sep
                        : selected || contextChipMa.containsMouse
                            ? configSection.root.seal : configSection.root.sep
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }

                    UiText {
                        visible: !isCustom
                        anchors.centerIn: parent
                        text: modelData.label
                        color: selected ? configSection.root.paper
                            : chipEnabled ? configSection.root.ink : configSection.root.sumi
                        font.family: configSection.root.mono
                        font.pixelSize: 10
                    }

                    TextInput {
                        id: customInput
                        visible: isCustom
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.family: configSection.root.mono
                        font.pixelSize: 10
                        enabled: chipEnabled && isCustom
                        color: enabled ? configSection.root.ink : configSection.root.sumi
                        clip: true
                        selectByMouse: true
                        text: isCustom && selected
                            ? (configSection.customCtxDisplay !== ""
                                ? configSection.customCtxDisplay
                                : String(configSection.data.selectedNumCtx))
                            : ""
                        onEditingFinished: {
                            var raw = String(text).trim()
                            if (!raw) return
                            var n = configSection.data.parseContextInput(raw)
                            if (n !== null) {
                                configSection.customCtxDisplay = raw
                                configSection.contextRequested(n)
                            }
                        }
                    }

                    UiText {
                        visible: isCustom && (!selected || customInput.text === "")
                            && !customInput.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Custom"
                        color: selected ? configSection.root.paper
                            : chipEnabled ? configSection.root.ink : configSection.root.sumi
                        font.family: configSection.root.mono
                        font.pixelSize: 10
                    }

                    MouseArea {
                        id: contextChipMa
                        anchors.fill: parent
                        enabled: chipEnabled && !isCustom
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: configSection.contextRequested(modelData.value)
                    }
                }
            }
        }

        UiText {
            width: parent.width
            visible: configSection.data.dirty
            text: "Configuration pending \u2014 press Apply to reload model"
            color: configSection.root.seal
            font.family: configSection.root.mono
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Rectangle {
        parent: configSection
        width: parent.width
        height: 1
        color: configSection.root.sep
    }

    Row {
        parent: configSection
        width: parent.width
        height: 28
        spacing: 8

        Rectangle {
            id: configTile
            width: 28
            height: 28
            radius: configSection.root.tileRadius
            color: configBottomMa.containsMouse
                ? configSection.root.fillHover : configSection.root.fillIdle
            border.color: configBottomMa.containsMouse
                ? configSection.root.seal : configSection.root.sep
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            IconText {
                anchors.centerIn: parent
                text: "\uE8B8"
                color: configBottomMa.containsMouse
                    ? configSection.root.seal : configSection.root.ink
                font.pixelSize: 14
            }
            TooltipMixin {
                id: configBottomTip
                root: configSection.root
                owner: configTile
                placement: "panel"
                text: "Open Ollama config file"
            }
            MouseArea {
                id: configBottomMa
                anchors.fill: parent
                enabled: !configSection.controlsLocked
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: configBottomTip.show()
                onExited: configBottomTip.hide()
                onEnabledChanged: if (!enabled) configBottomTip.hide()
                onClicked: {
                    configBottomTip.hide()
                    configSection.openRuntimeConfigRequested()
                }
            }
        }

        Rectangle {
            width: parent.width - refreshTile.width - configTile.width
                - 2 * parent.spacing
            height: parent.height
            radius: configSection.root.tileRadius
            color: applyMa.enabled
                ? (applyMa.containsMouse
                    ? configSection.root.fillPrimaryHover : configSection.root.seal)
                : configSection.root.fillIdle
            Behavior on color { ColorAnimation { duration: 120 } }

            UiText {
                anchors.centerIn: parent
                text: "Apply configuration"
                color: applyMa.enabled ? configSection.root.paper : configSection.root.sumi
                font.family: configSection.root.mono
                font.pixelSize: 11
            }
            MouseArea {
                id: applyMa
                anchors.fill: parent
                enabled: !configSection.controlsLocked
                    && configSection.data.dirty
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: configSection.applyRequested()
            }
        }

        Rectangle {
            id: refreshTile
            width: 28
            height: 28
            radius: configSection.root.tileRadius
            color: refreshBottomMa.containsMouse
                ? configSection.root.fillHover : configSection.root.fillIdle
            border.color: refreshBottomMa.containsMouse
                ? configSection.root.seal : configSection.root.sep
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }

            IconText {
                anchors.centerIn: parent
                text: "\uE5D5"
                color: refreshBottomMa.containsMouse
                    ? configSection.root.seal : configSection.root.ink
                font.pixelSize: 14
            }
            TooltipMixin {
                id: refreshBottomTip
                root: configSection.root
                owner: refreshTile
                placement: "panel"
                text: "Refresh Ollama state"
            }
            MouseArea {
                id: refreshBottomMa
                anchors.fill: parent
                enabled: !configSection.controlsLocked
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: refreshBottomTip.show()
                onExited: refreshBottomTip.hide()
                onEnabledChanged: if (!enabled) refreshBottomTip.hide()
                onClicked: {
                    refreshBottomTip.hide()
                    configSection.refreshRequested()
                }
            }
        }
    }
}
