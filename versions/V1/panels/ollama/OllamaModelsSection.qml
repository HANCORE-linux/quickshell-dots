import QtQuick

Column {
    id: modelsSection

    required property var root
    required property var data
    property string confirmDeleteModel: ""

    signal loadRequested(string name)
    signal ejectRequested(string name)
    signal deleteRequested(string name)

    width: parent ? parent.width : 0
    spacing: 8

    function clearDeleteConfirmation() {
        confirmDeleteModel = ""
        deleteConfirmationTimer.stop()
    }

    function confirmDelete(name) {
        confirmDeleteModel = name
        deleteConfirmationTimer.restart()
    }

    Timer {
        id: deleteConfirmationTimer
        interval: 8000
        onTriggered: modelsSection.clearDeleteConfirmation()
    }

    Repeater {
        model: modelsSection.data.models

        delegate: OllamaModelRow {
            width: modelsSection.width
            root: modelsSection.root
            data: modelsSection.data
            confirmationVisible: modelsSection.confirmDeleteModel === modelData.name
            onConfirmDeleteRequested: function(name) {
                modelsSection.confirmDelete(name)
            }
            onClearDeleteRequested: modelsSection.clearDeleteConfirmation()
            onLoadRequested: function(name) {
                modelsSection.clearDeleteConfirmation()
                modelsSection.loadRequested(name)
            }
            onEjectRequested: function(name) {
                modelsSection.clearDeleteConfirmation()
                modelsSection.ejectRequested(name)
            }
            onDeleteRequested: function(name) {
                modelsSection.deleteRequested(name)
                modelsSection.clearDeleteConfirmation()
            }
        }
    }

    Rectangle { width: parent.width; height: 1; color: modelsSection.root.sep }
}
