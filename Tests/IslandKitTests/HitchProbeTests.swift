import Foundation
import Testing
@testable import IslandKit

/// The probe itself: its numbers, its ring, its switch, and one real stall on the main thread.
@MainActor
@Suite(.serialized) struct HitchProbeTests {
    private func pump(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(5))
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
    }

    @Test func statsAreNearestRankPercentiles() {
        let stats = HitchStats(milliseconds: (1...100).map(Double.init), threshold: 8)
        #expect(stats.iterations == 100)
        #expect(stats.overThreshold == 92)  // strictly above 8: 9...100
        #expect(stats.median == 50)
        #expect(stats.p95 == 95)
        #expect(stats.worst == 100)
        #expect(stats.line == "n=100 over8=92 p50=50.0 p95=95.0 max=100.0")
    }

    @Test func emptyAndGarbageInputIsHarmless() {
        #expect(HitchStats(milliseconds: []).iterations == 0)
        let stats = HitchStats(milliseconds: [.nan, -3, .infinity, 4])
        #expect(stats.iterations == 1)
        #expect(stats.worst == 4)
        #expect(HitchStats.percentile(sorted: [], 0.95) == 0)
        #expect(HitchStats.percentile(sorted: [7], 2) == 7, "p is clamped")
    }

    @Test func aProbeThatWasNeverStartedRecordsNothing() {
        let probe = HitchProbe()
        #expect(!probe.isRunning)
        probe.record(elapsedNanos: 50_000_000)
        #expect(probe.totalHitches == 0)
        #expect(probe.hitches.isEmpty)
        #expect(probe.stats().iterations == 0)
    }

    @Test func onlyPassesOverTheThresholdAreHitchesButEveryPassIsCounted() {
        let probe = HitchProbe()
        probe.start(captureAll: true)
        defer { probe.stop() }
        probe.record(elapsedNanos: 3_000_000, cpuNanos: 2_000_000)
        probe.record(elapsedNanos: 8_000_000)  // exactly the threshold: not over
        probe.record(elapsedNanos: 12_000_000, cpuNanos: 11_000_000)
        #expect(probe.totalHitches == 1)
        #expect(probe.hitches.map(\.milliseconds) == [12])
        #expect(probe.hitches.first?.cpuMilliseconds == 11)
        #expect(probe.capturedMilliseconds == [3, 8, 12])
        #expect(probe.capturedCPUMilliseconds == [2, 0, 11])
        let stats = probe.stats()
        #expect(stats.iterations == 3 && stats.overThreshold == 1)
    }

    @Test func theRingKeepsTheNewestHitchesAndTheTotalKeepsCounting() {
        let probe = HitchProbe()
        probe.start()
        defer { probe.stop() }
        let extra = 40
        for i in 1...(HitchProbe.ringCapacity + extra) {
            probe.record(elapsedNanos: 9_000_000 + UInt64(i) * 1_000)  // 9.001 ms, 9.002 ms, ...
        }
        let kept = probe.hitches
        #expect(kept.count == HitchProbe.ringCapacity)
        #expect(probe.totalHitches == HitchProbe.ringCapacity + extra)
        let steps = kept.map { Int(($0.milliseconds * 1_000 - 9_000).rounded()) }
        #expect(steps.first == extra + 1, "oldest kept is the 41st")
        #expect(steps.last == HitchProbe.ringCapacity + extra)
        #expect(steps == Array(steps.first!...steps.last!), "oldest first, no gap")
    }

    @Test func resetForgetsEverythingAndKeepsRunning() {
        let probe = HitchProbe()
        probe.start(captureAll: true)
        defer { probe.stop() }
        probe.record(elapsedNanos: 20_000_000)
        probe.reset()
        #expect(probe.isRunning)
        #expect(probe.totalHitches == 0 && probe.hitches.isEmpty && probe.capturedMilliseconds.isEmpty)
    }

    @Test func aRealStallOnTheMainThreadIsSeen() async {
        let probe = HitchProbe()
        probe.start()
        defer { probe.stop() }
        await pump(0.05)
        probe.reset()
        DispatchQueue.main.async { usleep(35_000) }  // a main-queue block that blocks the thread for 35 ms
        await pump(0.25)
        #expect(probe.hitches.contains { $0.milliseconds >= 30 }, "got \(probe.hitches.map(\.milliseconds))")
    }

    @Test func theEnvironmentVariableIsTheOnlySwitch() async throws {
        let off = HitchProbe()
        #expect(off.startIfRequested(environment: [:]) == false)
        #expect(off.startIfRequested(environment: [HitchProbe.environmentKey: ""]) == false)
        #expect(off.startIfRequested(environment: [HitchProbe.environmentKey: "0"]) == false)
        #expect(!off.isRunning)

        let path = NSTemporaryDirectory() + "mis-hitch-test-\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let on = HitchProbe()
        #expect(on.startIfRequested(environment: [HitchProbe.environmentKey: path]))
        #expect(on.isRunning)
        on.record(elapsedNanos: 21_000_000, cpuNanos: 4_000_000)
        on.stop()
        #expect(!on.isRunning)
        // The writer is asynchronous: wait for the summary line it adds on stop.
        var text = ""
        for _ in 0..<100 {
            text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if text.contains("# summary") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.contains { $0.hasSuffix(" 21.0 4.0") }, "one line per hitch: <t> <wall ms> <cpu ms>, got \(lines)")
        #expect(lines.last?.hasPrefix("# summary") == true)
        #expect(!text.contains("/"), "counts and durations only: no path, no name")
    }
}
