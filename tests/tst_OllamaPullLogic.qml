import QtQuick 2.15
import QtTest 1.3
import "../versions/V1/modules/OllamaPullLogic.js" as Logic

TestCase {
    name: "OllamaPullLogic"

    function test_reconcileBackoffIsCapped() {
        compare(Logic.reconcileBackoffMs(0), 1000)
        compare(Logic.reconcileBackoffMs(1), 2000)
        compare(Logic.reconcileBackoffMs(2), 4000)
        compare(Logic.reconcileBackoffMs(3), 8000)
        compare(Logic.reconcileBackoffMs(4), 10000)
        compare(Logic.reconcileBackoffMs(8), 10000)
    }

    function test_delayDoesNotCrossDeadline() {
        compare(Logic.nextReconcileDelayMs(8, 175000, 180000), 5000)
        compare(Logic.nextReconcileDelayMs(8, 180000, 180000), 0)
    }
}
