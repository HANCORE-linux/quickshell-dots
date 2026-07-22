//@ pragma UseQApplication

import Quickshell
import QtQuick
import "core"
// Quickshell's virtual filesystem scanner follows declared directory imports,
// not arbitrary Loader URLs. The alias registers the complete V2 bundle while
// keeping every V2 type uninstantiated until VariantHost selects it.
import "variants/V2" as V2Bundle

ShellRoot {
    id: root

    StateService {
        id: variantState
    }

    VariantHost {
        id: variantHost
        stateService: variantState
        v1Source: Qt.resolvedUrl("VariantRoot.qml")
        v2Source: Qt.resolvedUrl("variants/V2/VariantRoot.qml")
    }

    IpcRouter {
        variantHost: variantHost
    }
}
