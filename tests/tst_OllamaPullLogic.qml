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

    function test_digestChangeResetsEveryLayerFieldBeforeApplyingEvent() {
        var first = Logic.nextLayerProgress({}, {
            digest: "sha256:aaaaaaaa", completed: 100, total: 1000
        }, 1000)
        var second = Logic.nextLayerProgress(first, {
            digest: "sha256:aaaaaaaa", completed: 300, total: 1000
        }, 2000)
        var stable = Logic.nextLayerProgress(second, {
            digest: "sha256:aaaaaaaa", completed: 500, total: 1000
        }, 3000)

        compare(stable.stableSamples, 2)
        verify(stable.rateBytesPerSecond > 0)
        verify(stable.etaSeconds > 0)

        var next = Logic.nextLayerProgress(stable, {
            digest: "sha256:bbbbbbbb", completed: 25, total: 200
        }, 4000)
        compare(next.digest, "sha256:bbbbbbbb")
        compare(next.completed, 25)
        compare(next.total, 200)
        compare(next.sampledAtMs, 4000)
        compare(next.stableSamples, 0)
        compare(next.rateBytesPerSecond, 0)
        compare(next.etaSeconds, 0)
    }

    function test_reducesRawJsonWithoutThrowingOnMalformedInput() {
        var prior = {
            digest: "sha256:aaaaaaaa", completed: 500, total: 1000,
            sampledAtMs: 3000, rateBytesPerSecond: 200, etaSeconds: 2.5,
            stableSamples: 2
        }

        var changed = Logic.nextLayerProgress(prior,
                '{"digest":"sha256:bbbbbbbb"}', 4000)
        compare(changed.digest, "sha256:bbbbbbbb")
        compare(changed.completed, 0)
        compare(changed.total, 0)

        var malformed = Logic.nextLayerProgress(prior, "not-json", 4000)
        compare(malformed.digest, prior.digest)
        compare(malformed.completed, prior.completed)
        compare(malformed.total, prior.total)
    }

    function test_newDigestWithoutTotalsDoesNotRetainPriorLayerBytes() {
        var prior = {
            digest: "sha256:aaaaaaaa", completed: 500, total: 1000,
            sampledAtMs: 3000, rateBytesPerSecond: 200, etaSeconds: 2.5,
            stableSamples: 2
        }

        var next = Logic.nextLayerProgress(prior, {
            digest: "sha256:bbbbbbbb"
        }, 4000)
        compare(next.digest, "sha256:bbbbbbbb")
        compare(next.completed, 0)
        compare(next.total, 0)
        compare(next.stableSamples, 0)
        compare(next.rateBytesPerSecond, 0)
        compare(next.etaSeconds, 0)
        compare(Logic.currentLayerText(next), "Current layer · Calculating...")

        var firstSample = Logic.nextLayerProgress(next, {
            digest: "sha256:bbbbbbbb", completed: 25, total: 200
        }, 5000)
        compare(firstSample.sampledAtMs, 5000)
        compare(firstSample.stableSamples, 0)
        compare(firstSample.rateBytesPerSecond, 0)
        compare(firstSample.etaSeconds, 0)
    }

    function test_formatsStableProgressAsCurrentLayerWithoutDigest() {
        var display = Logic.currentLayerText({
            digest: "sha256:aaaaaaaa",
            completed: 1.8 * 1024 * 1024 * 1024,
            total: 4.7 * 1024 * 1024 * 1024,
            rateBytesPerSecond: 42 * 1024 * 1024,
            etaSeconds: 70,
            stableSamples: 2
        })

        compare(display,
                "Current layer · 1.8 / 4.7 GiB · 42 MiB/s · about 1m 10s remaining")
        verify(display.indexOf("Current layer") === 0)
        verify(display.indexOf("sha256:") < 0)
    }

    function test_formatsUnstableProgressAsCalculating() {
        var display = Logic.currentLayerText({
            digest: "sha256:aaaaaaaa", completed: 512, total: 1024,
            rateBytesPerSecond: 128, etaSeconds: 6, stableSamples: 1
        })

        compare(display, "Current layer · 0.5 / 1.0 KiB · 128 B/s · Calculating...")
        verify(display.indexOf("sha256:") < 0)
    }
}
