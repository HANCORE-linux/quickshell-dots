import QtQuick

Item {
    id: rootMod
    required property var root

    visible: implicitWidth > 0.5
    implicitWidth: root.modOllama ? row.implicitWidth + 18 : 0
    implicitHeight: 28
    opacity: root.modOllama ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    readonly property string tooltipText: root.ollama.connected
        ? "Ollama " + root.ollama.version + " · " + root.ollama.loadedModels.length
            + " loaded · " + formatVram(root.ollama.loadedVramBytes)
        : "Ollama offline"

    function formatVram(bytes) {
        if (!(bytes > 0)) return "0 MiB"
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GiB"
        return Math.round(bytes / 1048576) + " MiB"
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(row.width) + 18
        height: root.pillH
        radius: root.pillRadius
        color: root.pill
        border.color: root.pillBorder
        border.width: root.pillBorderW
        PillShadow { theme: root }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.compactOllama ? 4 : 5

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 18
            source: Qt.resolvedUrl("../assets/ollama.svg")
            sourceSize: Qt.size(16, 18)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            layer.enabled: true
            layer.smooth: true
            layer.effect: ShaderEffect {
                property color tintColor: root.ollama.connected ? root.seal : root.sumi
                fragmentShader: Qt.resolvedUrl("../shaders/logo-tint.frag.qsb")
            }
        }

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compactOllama
            text: "GPU"
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.6)
            font.family: root.mono
            font.pixelSize: 12
        }

        UiText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.ollama.gpuPercent >= 0
                ? String(Math.min(100, root.ollama.gpuPercent)).padStart(2, "0") + "%"
                : "N/A"
            color: root.ollama.connected ? root.seal : root.sumi
            font.family: root.mono
            font.pixelSize: 12
        }
    }

    TooltipMixin { id: tip; root: rootMod.root; owner: rootMod; text: rootMod.tooltipText }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tip.show()
        onExited: tip.hide()
        onClicked: { tip.hide(); root.ollamaVisible = !root.ollamaVisible }
    }
}
