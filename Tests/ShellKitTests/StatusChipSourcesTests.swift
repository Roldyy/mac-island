import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// A lock-protected counter the pollers' injected readers and sleepers share across threads.
private final class TickCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    @discardableResult func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

/// The built-in sources, driven by fake counters and a sleeper that lets a fixed number of ticks through and then
/// waits (cancellably) for `stop()`.
@MainActor
@Suite struct StatusChipSourcesTests {
    /// Lets `ticks - 1` sleeps return at once (so `ticks` ticks run), then suspends until cancelled.
    private func sleeper(ticks: Int) -> @Sendable (Duration) async throws -> Void {
        let calls = TickCounter()
        return { _ in
            if calls.next() >= ticks { try await Task.sleep(for: .seconds(3600)) }
        }
    }

    private func wait(_ source: StatusChipPolledSource, until condition: (StatusChipReading?) -> Bool) async throws {
        for _ in 0..<400 where !condition(source.reading) { try await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Load

    @Test func theLoadSourceMeasuresAtOnceFromItsFirstTick() async throws {
        let reads = TickCounter()
        let source = LoadChipSource(
            sleep: sleeper(ticks: 1),
            readTicks: {
                // Every read adds 50 busy of 100 total: 50 % between any two reads.
                let n = UInt64(reads.next())
                return CPUTicks(busy: 50 * n, total: 100 * n)
            },
            readMemory: { 8_000_000_000 }, readPressure: { .normal },
            totalMemory: 16_000_000_000, primeDelay: 0, temperatureProvider: { 62.4 })
        var changes = 0
        source.onChange = { changes += 1 }
        source.start()
        try await wait(source) { $0 != nil }
        #expect(source.reading?.primary == "CPU 50 %")
        #expect(source.reading?.secondary == "RAM 50 % · 62 °C")
        #expect(changes == 1)
        source.stop()
        #expect(source.reading == nil && !source.isRunning)
    }

    @Test func stoppingThePollerEndsTheSampling() async throws {
        let reads = TickCounter()
        let source = LoadChipSource(
            sleep: sleeper(ticks: 1),
            readTicks: { let n = UInt64(reads.next()); return CPUTicks(busy: n, total: 2 * n) },
            readMemory: { 1 }, readPressure: { .normal }, totalMemory: 2, primeDelay: 0)
        source.start()
        try await wait(source) { $0 != nil }
        source.stop()
        let after = reads.value
        try await Task.sleep(for: .milliseconds(100))
        #expect(reads.value == after, "no sample after stop()")
        // A start after a stop begins from a fresh baseline and publishes again.
        source.start()
        try await wait(source) { $0 != nil }
        #expect(source.reading != nil)
        source.stop()
    }

    @Test func startAndStopAreIdempotent() async throws {
        let source = LoadChipSource(sleep: sleeper(ticks: 1), readTicks: { nil }, readMemory: { 1 },
                                    readPressure: { .normal }, totalMemory: 2, primeDelay: 0)
        source.stop()  // never started: nothing to do
        source.start()
        source.start()
        #expect(source.isRunning)
        try await wait(source) { $0 != nil }
        source.stop()
        source.stop()
        #expect(!source.isRunning && source.reading == nil)
    }

    // MARK: Network

    @Test func theNetworkSourceShowsRatesFromTheSecondTick() async throws {
        let reads = TickCounter()
        let source = NetworkChipSource(
            sleep: sleeper(ticks: 2), watchPath: false,
            read: {
                let n = UInt64(reads.next())
                return [InterfaceReading(name: "en0", isUp: true, hasIPv4: true,
                                         counters: InterfaceCounters(bytesIn: 1_000_000 * n, bytesOut: 10_000 * n))]
            })
        source.start()
        try await wait(source) { $0?.secondary != nil }
        // No path monitor in this test: the link reads "other".
        #expect(source.reading?.primary == "Réseau")
        #expect(source.reading?.secondary?.hasPrefix("↓ ") == true)
        source.stop()
        #expect(source.reading == nil)
    }

    // MARK: Disk

    @Test func theDiskSourceReadsOnceAndTagsTheLevel() async throws {
        let reads = TickCounter()
        let source = DiskChipSource(sleep: sleeper(ticks: 1),
                                    read: { reads.next(); return .init(free: 40_000_000_000, total: 1_000_000_000_000) })
        source.start()
        try await wait(source) { $0 != nil }
        #expect(source.reading?.primary == "40 Go" && source.reading?.level == .alert)
        #expect(reads.value == 1)
        source.stop()
    }

    @Test func aFailedReadLeavesNoChip() async throws {
        let source = DiskChipSource(sleep: sleeper(ticks: 1), read: { nil })
        source.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.reading == nil)
        source.stop()
    }

    @Test func theCadenceIsTwoSecondsExceptTheDiskAtOneMinute() {
        #expect(NetworkChipSource.interval == .seconds(2))
        #expect(LoadChipSource.interval == .seconds(2))
        #expect(DiskChipSource.interval == .seconds(60))
    }
}
