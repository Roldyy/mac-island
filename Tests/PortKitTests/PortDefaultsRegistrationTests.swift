import Foundation
import Testing
@testable import PortKit

/// `Defaults.register` after the split (patch 0012): registered values only after the migration and the registry
/// seed, no availability switch registered or written by the ported code, the four upstream seeds through the host.
/// Temporary suites only; every hook is faked.
@Suite struct PortDefaultsRegistrationTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var list: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func shellEnabledKeys(_ defaults: UserDefaults) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("shell.enabled.") }.sorted()
    }

    @Test func registeringValuesNeverRegistersOrWritesAnAvailabilitySwitch() {
        PortHostFixture.isolated { defaults in
            Defaults.register(in: defaults)
            #expect(shellEnabledKeys(defaults).isEmpty,
                    "registered availability would read as a chosen value: \(shellEnabledKeys(defaults))")
            #expect(defaults.object(forKey: DefaultsKey.clipboardHistoryEnabled) != nil, "the upstream values are registered")
            for feature in AppFeature.allCases {
                #expect(defaults.object(forKey: feature.availabilityKey) == nil, "\(feature.rawValue)")
            }
        }
    }

    /// The registration domain is process-wide, so a behavioural test of "this seed saw an unset key" would depend on
    /// which test registered first. The order is pinned in the source instead: `migrateScrollInverterAxes` copies the
    /// vertical switch only while the horizontal one was never set, so it must run BEFORE the registered default
    /// makes `object(forKey:)` non-nil.
    @Test func theUpstreamSeedsKeepTheirOrderAroundTheRegistration() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Core/Defaults.swift"),
                              encoding: .utf8)
        func offset(_ needle: String) throws -> Int {
            try #require(text.range(of: needle)).lowerBound.utf16Offset(in: text)
        }
        let body = try offset("static func register(in defaults: UserDefaults) {")
        let before = try offset("        migrateBeforeRegistration(in: defaults)")
        let values = try offset("        registerDefaultValues(in: defaults)")
        let after = try offset("        migrateAfterRegistration(in: defaults)")
        #expect(body < before && before < values && values < after)
        // Upstream's own order inside the first group: the axes copy and the linear-scroll seed run before the register.
        let preGroup = try offset("static func migrateBeforeRegistration")
        let postGroup = try offset("static func migrateAfterRegistration")
        let registration = try offset("static func registerDefaultValues")
        #expect(preGroup < registration && registration < postGroup)
        let axes = try offset("        migrateScrollInverterAxes(in: defaults)")
        let linear = try offset("        migrateLinearScrollAvailability(in: defaults)")
        #expect(preGroup < axes && axes < linear && linear < registration)
    }

    @Test func theFourAvailabilitySeedsGoThroughTheHostAndWriteNothing() {
        PortHostFixture.isolated { defaults in
            let calls = Recorder()
            PortHost.setEnabled = { id, enabled in calls.add("\(id)=\(enabled)") }
            let stored = Box<[String: Bool]>(["notch": false])
            PortHost.storedSwitch = { stored.value[$0] }

            // fanControl (upstream `migrateFanControlVisibility`) and linearScroll.
            defaults.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            defaults.set(true, forKey: DefaultsKey.linearScrollEnabled)
            // notchMascot (`installCompanionForBetaCommandBar`): a beta, onboarded, command bar and island available.
            defaults.set(true, forKey: DefaultsKey.hasOnboarded)
            PortHost.availability = { ["commandbar", "notch"].contains($0) ? true : nil }
            Defaults.installCompanionForBetaCommandBar(in: defaults, isBeta: true)
            // Register runs the other three seeds.
            Defaults.register(in: defaults)

            let list = calls.list
            #expect(list.contains("fans=true"), "fanControl is the registry's `fans`: \(list)")
            #expect(list.contains("linearScroll=true"), "\(list)")
            #expect(list.contains("notchMascot=true"), "\(list)")
            #expect(list.contains("notchWatch=false"), "the island is left out, so Watch is: \(list)")
            #expect(shellEnabledKeys(defaults).isEmpty, "the registry is the only writer: \(shellEnabledKeys(defaults))")
        }
    }

    @Test func aSeedThatReadsAnAvailabilityReadsTheRegistryNotTheKey() {
        PortHostFixture.isolated { defaults in
            let calls = Recorder()
            PortHost.setEnabled = { id, enabled in calls.add("\(id)=\(enabled)") }
            PortHost.storedSwitch = { $0 == "linearScroll" ? false : nil }  // the registry holds a stored off
            defaults.set(true, forKey: DefaultsKey.linearScrollEnabled)
            Defaults.migrateLinearScrollAvailability(in: defaults)
            #expect(calls.list.isEmpty, "a stored choice is never overwritten")

            // A key planted under the old name is not what the seed reads.
            PortHost.storedSwitch = { _ in nil }
            defaults.set(false, forKey: AppFeature.linearScroll.availabilityKey)
            Defaults.migrateLinearScrollAvailability(in: defaults)
            #expect(calls.list == ["linearScroll=true"])
        }
    }

    @Test func withoutAHostTheSeedsAreSilent() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.linearScrollEnabled)
            defaults.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.register(in: defaults)
            #expect(shellEnabledKeys(defaults).isEmpty)
        }
    }

    @Test func nothingCallsRegisterExceptTheBridge() throws {
        // `register` stays out of main.swift: the cleanup flags run first and nothing else.
        let main = try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/MacIsland/main.swift"),
                              encoding: .utf8)
        #expect(!main.contains("registerDefaults") && !main.contains("Defaults.register"))
        var callers: [String] = []
        for file in PortSourceScrubTests.files {
            for line in file.lines where line.contains("Defaults.register(") || line.contains("registerDefaults()") {
                if !line.drop(while: { $0 == " " }).hasPrefix("//") { callers.append(file.path) }
            }
        }
        #expect(Set(callers) == ["Bridge/PortBridge.swift"], "\(callers)")
    }
}
