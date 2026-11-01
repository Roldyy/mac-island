import Foundation
import Testing
@testable import PortKit

/// The emergency stop of the super key (kill switch, safe mode, permission revoked) must never freeze the UI behind a
/// hung `hidutil`: the mapping is taken out off the main thread within ONE budget, only the quit waits (2 s at most),
/// and what the budget does not finish the guard child finishes when its pipe closes. A fake `hidutil` that hangs and
/// a fake clock stand in for the system; the guard child is a harmless `/bin/sh` that waits on the pipe like the real
/// one, never the test binary.
@MainActor
@Suite(.serialized) struct SuperKeyStopBudgetTests {
    private static let ours = SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                              destination: SuperKeySupport.triggerUsage)

    /// A `hidutil` whose first call blocks until the test lets it go.
    private final class HangingHID: @unchecked Sendable {
        private let lock = NSLock()
        private var table: [SuperKeyMapping]
        private var hasHung = false
        private var recorded: [[String]] = []
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        init(table: [SuperKeyMapping]) { self.table = table }

        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
        var sets: [[String]] { calls.filter { $0.contains("--set") } }
        var current: [SuperKeyMapping] { lock.lock(); defer { lock.unlock() }; return table }

        func run(_ arguments: [String]) -> (status: Int32, output: String) {
            lock.lock()
            recorded.append(arguments)
            let hangNow = !hasHung
            hasHung = true
            lock.unlock()
            if hangNow {
                entered.signal()
                release.wait()
            }
            lock.lock()
            defer { lock.unlock() }
            if let index = arguments.firstIndex(of: "--set"), arguments.indices.contains(index + 1) {
                table = Self.parse(arguments[index + 1])
                return (0, "")
            }
            return (0, Self.report(table))
        }

        static func parse(_ argument: String) -> [SuperKeyMapping] {
            guard let data = argument.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = root["UserKeyMapping"] as? [[String: Any]] else { return [] }
            return entries.compactMap {
                guard let src = ($0["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
                      let dst = ($0["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value else { return nil }
                return SuperKeyMapping(source: src, destination: dst)
            }
        }

        static func report(_ table: [SuperKeyMapping]) -> String {
            var text = "Matching Service Property:\n0x100000bb1 UserKeyMapping (\n"
            for mapping in table {
                text += "    {\n        HIDKeyboardModifierMappingDst = \(mapping.destination);\n"
                text += "        HIDKeyboardModifierMappingSrc = \(mapping.source);\n    }\n"
            }
            return text + ")\n"
        }
    }

    /// Runs `body` with the fake `hidutil` and a clock `clock` drives; both are put back before it returns, after
    /// the mapping queue has drained (a stray task must never reach the real `hidutil` once the fake is gone).
    private func withHang(_ hid: HangingHID, clock: Box<TimeInterval>, _ body: () -> Void) {
        let savedClock = SuperKeyMappingGuard.StopBudget.uptime
        SuperKeyMappingGuard.runHIDOverride = { hid.run($0) }
        SuperKeyMappingGuard.StopBudget.uptime = { clock.value }
        defer {
            hid.release.signal()  // a hang the body left in place never outlives the test
            #expect(SuperKeyService.shared.waitForMappingQueueForTesting(timeout: 120), "the mapping queue never drained")
            SuperKeyMappingGuard.runHIDOverride = nil
            SuperKeyMappingGuard.StopBudget.uptime = savedClock
        }
        body()
    }

    private func armedDefaults(_ defaults: UserDefaults) {
        defaults.set(true, forKey: DefaultsKey.superKeyMappingApplied)
        defaults.set(SuperKeySource.capsLock.rawValue, forKey: DefaultsKey.superKeyMappedSource)
    }

    private func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = Date()
        body()
        return Date().timeIntervalSince(start)
    }

    // MARK: The registry stop never waits

    @Test func theRegistryStopReturnsAtOnceWhileHidutilHangsAndTheClearFinishesWhenItAnswers() {
        PortHostFixture.isolated { defaults in
            armedDefaults(defaults)
            let hid = HangingHID(table: [Self.ours])
            withHang(hid, clock: Box(0)) {
                let took = elapsed { SuperKeyService.shared.suspend() }
                #expect(took < 1, "the main thread waited \(took) s on a hung hidutil")
                #expect(hid.entered.wait(timeout: .now() + 120) == .success, "the clear never reached hidutil")
                #expect(defaults.bool(forKey: DefaultsKey.superKeyMappingApplied), "nothing is cleared while hidutil hangs")
                hid.release.signal()
                #expect(SuperKeyService.shared.waitForMappingQueueForTesting(timeout: 120))
                #expect(hid.current.isEmpty, "the key is given back once hidutil answers")
                #expect(!defaults.bool(forKey: DefaultsKey.superKeyMappingApplied))
            }
        }
    }

    // MARK: The quit waits, but only a little

    @Test func theQuitWaitsAtMostItsOwnBudgetOnAHungHidutil() {
        PortHostFixture.isolated { defaults in
            armedDefaults(defaults)
            let hid = HangingHID(table: [Self.ours])
            withHang(hid, clock: Box(0)) {
                let took = elapsed { SuperKeyService.shared.suspendForTermination() }
                let cap = SuperKeyMappingGuard.StopBudget.terminationTotal
                #expect(took >= cap - 0.5, "it did not wait for the clear (\(took) s)")
                #expect(took < cap + 8, "the quit waited \(took) s: a hung hidutil must not hold it")
                #expect(defaults.bool(forKey: DefaultsKey.superKeyMappingApplied), "marker kept: the guard child or the next launch retries")
            }
        }
    }

    // MARK: One total budget

    @Test func aBudgetRunOutStartsNoFurtherHidutilKeepsTheMarkerAndLeavesTheRestToTheGuard() {
        PortHostFixture.isolated { defaults in
            armedDefaults(defaults)
            let hid = HangingHID(table: [Self.ours])
            let clock = Box<TimeInterval>(0)
            withHang(hid, clock: clock) {
                SuperKeyService.shared.suspend()
                #expect(hid.entered.wait(timeout: .now() + 120) == .success)
                clock.value = SuperKeyMappingGuard.StopBudget.asyncTotal + 1  // the hang ate the whole budget
                hid.release.signal()
                #expect(SuperKeyService.shared.waitForMappingQueueForTesting(timeout: 120))
                #expect(hid.sets.isEmpty, "a clear past its budget writes nothing more")
                #expect(hid.calls.count == 1)
                #expect(defaults.bool(forKey: DefaultsKey.superKeyMappingApplied), "marker kept so the next launch retries")
                #expect(hid.current == [Self.ours])
            }
        }
    }

    @Test func theBudgetCountsDownFromTheMomentTheStopWasAskedFor() {
        let clock = Box<TimeInterval>(100)
        let saved = SuperKeyMappingGuard.StopBudget.uptime
        SuperKeyMappingGuard.StopBudget.uptime = { clock.value }
        defer { SuperKeyMappingGuard.StopBudget.uptime = saved }
        let budget = SuperKeyMappingGuard.StopBudget(seconds: 3)
        #expect(budget.remaining == 3 && !budget.isExhausted)
        clock.value = 102
        #expect(budget.remaining == 1)
        clock.value = 103
        #expect(budget.isExhausted && budget.remaining == 0)
        clock.value = 500
        #expect(budget.remaining == 0, "never negative")
        #expect(SuperKeyMappingGuard.StopBudget.asyncTotal <= 3)
        #expect(SuperKeyMappingGuard.StopBudget.terminationTotal <= 2)
    }

    // MARK: The guard child gives the key back when the pipe closes

    private func markerURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mis-guard-\(UUID().uuidString)")
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    private func withFakeChild(marker: URL, _ body: () -> Void) {
        // Same shape as the real child: wait for the pipe to close, then do the cleanup (here: write a file).
        SuperKeyMappingGuard.launchOverride = { _ in
            ("/bin/sh", ["-c", "IFS= read -r _; /usr/bin/touch \"$1\"", "sh", marker.path])
        }
        defer {
            SuperKeyMappingGuard.launchOverride = nil
            try? FileManager.default.removeItem(at: marker)
        }
        body()
    }

    @Test func aStopThatDoesNotWaitStillLetsTheGuardChildClean() throws {
        let marker = markerURL()
        withFakeChild(marker: marker) {
            guard let handle = SuperKeyMappingGuard.start(source: .capsLock) else {
                Issue.record("the fake guard child did not start"); return
            }
            #expect(!FileManager.default.fileExists(atPath: marker.path), "the child waits on the pipe")
            let took = elapsed { _ = handle.stop(within: 0) }
            #expect(took < 1, "a zero budget must not wait")
            #expect(waitUntil(120) { FileManager.default.fileExists(atPath: marker.path) },
                    "the pipe was closed, so the child cleans on its own")
        }
    }

    @Test func aStopWithBudgetLeftConfirmsTheChildsCleanup() throws {
        let marker = markerURL()
        withFakeChild(marker: marker) {
            guard let handle = SuperKeyMappingGuard.start(source: .capsLock) else {
                Issue.record("the fake guard child did not start"); return
            }
            #expect(handle.stop(within: 120), "the child finished within the budget")
            #expect(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    // MARK: Contracts

    private func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func onlyTheQuitPathWaitsAndNeverOnASynchronousQueueHop() throws {
        let lane = try source("Sources/PortKit/Bridge/InputKeyboard.swift")
        #expect(lane.contains("stop: { SuperKeyService.shared.suspend() }"), "the registry stop does not wait")
        #expect(lane.contains("observeTermination(of: binding) { SuperKeyService.shared.suspendForTermination() }"))
        let service = try source("Sources/PortKit/Services/SuperKey/SuperKeyService.swift")
        let code = service.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        #expect(!code.contains { $0.contains("mappingQueue.sync") }, "an unbounded wait behind queued work is back")
    }
}
