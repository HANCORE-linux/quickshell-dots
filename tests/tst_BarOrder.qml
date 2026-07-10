import QtQuick 2.15
import QtTest 1.3
import "../versions/V1/BarOrder.js" as BarOrder

TestCase {
    name: "BarOrder"

    readonly property var ids: [
        "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8",
        "G9", "G10", "G11", "G12", "G13", "G14", "G15", "G16"
    ]
    readonly property var sizes: [8, 1, 7]

    function test_validCurrentOrder() {
        var value = "G1,G2,G3,G4,G5,G6,G7,G16|G8|G9,G10,G11,G14,G12,G13,G15"
        var result = BarOrder.decode(value, ids, sizes, "G16")
        verify(result !== null)
        compare(BarOrder.serialize(result), value)
    }

    function test_migratesLegacyOrderWithoutReordering() {
        var value = "G2,G1,G3,G4,G5,G6,G7|G8|G9,G10,G11,G14,G12,G13,G15"
        var result = BarOrder.decode(value, ids, sizes, "G16")
        verify(result !== null)
        compare(result.left.join(","), "G2,G1,G3,G4,G5,G6,G7,G16")
        compare(result.center.join(","), "G8")
        compare(result.right.join(","), "G9,G10,G11,G14,G12,G13,G15")
    }

    function test_rejectsDuplicate() {
        var value = "G1,G1,G3,G4,G5,G6,G7,G16|G8|G9,G10,G11,G14,G12,G13,G15"
        compare(BarOrder.decode(value, ids, sizes, "G16"), null)
    }

    function test_rejectsUnknownGroup() {
        var value = "G1,G2,G3,G4,G5,G6,G7,G99|G8|G9,G10,G11,G14,G12,G13,G15"
        compare(BarOrder.decode(value, ids, sizes, "G16"), null)
    }

    function test_rejectsIncompleteCurrentOrder() {
        var value = "G1,G2,G3,G4,G5,G6,G16|G8|G9,G10,G11,G14,G12,G13,G15"
        compare(BarOrder.decode(value, ids, sizes, "G16"), null)
    }
}
