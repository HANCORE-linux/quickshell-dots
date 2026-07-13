// BluetoothPanel.qml — compatibility wrapper.
//
// This file deliberately does NOT `import Quickshell.Bluetooth`. shell.qml instantiates the
// Bluetooth panel eagerly, so importing the native module here would make the WHOLE shell fail
// to load on installations whose Quickshell predates the native Bluetooth API (< 0.3) — e.g. a
// Self-Update that upgraded the config but not Quickshell yet. Instead the native implementation
// is loaded lazily at runtime: if its `Quickshell.Bluetooth` import is unavailable the component
// fails to compile and we transparently fall back to the bluetoothctl implementation, so the
// panel keeps working (and the rest of the shell always loads) regardless of Quickshell version.
import QtQuick

Item {
    id: wrapper
    required property var root

    // The actual panel (native or legacy), created lazily below.
    property QtObject impl: null

    Component.onCompleted: loadImpl("BluetoothPanelNative.qml", true)

    function loadImpl(file, allowFallback) {
        // Local files load synchronously, so status is Ready/Error immediately.
        var comp = Qt.createComponent(Qt.resolvedUrl(file))
        if (comp.status === Component.Error) {
            console.warn("BluetoothPanel: '" + file + "' unavailable"
                + (allowFallback ? " — falling back to bluetoothctl" : "")
                + ": " + comp.errorString().trim())
            comp.destroy()
            if (allowFallback)
                loadImpl("BluetoothPanelLegacy.qml", false)
            return
        }
        // createObject() sets the required `root` at construction time (a Loader cannot).
        wrapper.impl = comp.createObject(wrapper, { root: wrapper.root })
        comp.destroy()
    }
}
