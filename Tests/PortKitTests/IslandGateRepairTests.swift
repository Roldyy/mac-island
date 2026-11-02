import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// The second switch of a ported island feature: the seed rule, the one-shot repair of a profile that upstream's first-launch
/// migration forced off, the launch ordering that stops it happening, the live host tick and the clipboard dock commands.
@MainActor
@Suite(.serialized) struct IslandGateRepairTests {
    static let sevenKeys = IslandFeatureSeed.forcedOff.map(\.key)

    // MARK: The seed rule (switch on + key absent => on; a stored choice is never touched)

    @Test func anAbsentGateKeyIsWrittenOnAndASecondStartChangesNothing() {
        PortHostFixture.isolated { defaults in
            #expect(IslandFeatureSeed.seed(feature: "notchLyrics", in: defaults) == [DefaultsKey.notchLyricsEnabled])
            #expect(defaults.bool(forKey: DefaultsKey.notchLyricsEnabled))
            #expect(IslandFeatureSeed.seed(feature: "notchLyrics", in: defaults).isEmpty, "idempotent")
        }
    }

    @Test func anExplicitFalseIsAChoiceAndStays() {
        PortHostFixture.isolated { defaults in
            defaults.set(false, forKey: DefaultsKey.notchMascotEnabled)
            #expect(IslandFeatureSeed.seed(feature: "notchMascot", in: defaults).isEmpty)
            #expect(defaults.bool(forKey: DefaultsKey.notchMascotEnabled) == false)
        }
    }

    @Test func everyIslandFeatureWithASecondKeyIsInTheTableAndBound() {
        let lane = PortFeatureBinding(permissions: { PortPermissionState() })
        PortLanes.bindAll(into: lane)
        let known = Set(lane.descriptors.map(\.id)).union(["cameraPreview"])
        for id in IslandFeatureSeed.gateKeys.keys { #expect(known.contains(id), "\(id) is no bound feature") }
    }

    // MARK: One-shot repair

    @Test func aProfileWithAllSevenKeysForcedOffIsRepairedOnceToUpstreamsDefaultProfile() {
        PortHostFixture.isolated { defaults in
            for key in Self.sevenKeys { defaults.set(false, forKey: key) }
            let fixed = IslandFeatureSeed.repairForcedOffGates(in: defaults)
            #expect(Set(fixed).count == 6, "the equalizer's default profile value is off")
            for item in IslandFeatureSeed.forcedOff {
                #expect(defaults.bool(forKey: item.key) == item.defaultProfile, Comment(rawValue: item.key))
            }
            // A choice made after the repair is not read as damage.
            defaults.set(false, forKey: DefaultsKey.notchLyricsEnabled)
            #expect(IslandFeatureSeed.repairForcedOffGates(in: defaults).isEmpty)
            #expect(defaults.bool(forKey: DefaultsKey.notchLyricsEnabled) == false)
        }
    }

    @Test func aProfileWhereThePersonChoseAnythingIsNeverTouched() {
        PortHostFixture.isolated { defaults in
            for key in Self.sevenKeys { defaults.set(false, forKey: key) }
            defaults.set(true, forKey: DefaultsKey.notchDownloadsEnabled)  // Harold's own profile: downloads is on
            #expect(IslandFeatureSeed.repairForcedOffGates(in: defaults).isEmpty)
            #expect(defaults.bool(forKey: DefaultsKey.notchLyricsEnabled) == false)
            #expect(defaults.bool(forKey: IslandFeatureSeed.repairMarker), "marker written either way")
        }
    }

    @Test func keysThatAreAbsentAreNotARepairCaseTheSeedHandlesThem() {
        PortHostFixture.isolated { defaults in
            #expect(IslandFeatureSeed.repairForcedOffGates(in: defaults).isEmpty)
        }
    }

    // MARK: Launch ordering (fresh install)

    func freshBench() -> (defaults: UserDefaults, domain: String, cleanup: () -> Void) {
        let name = UUID().uuidString
        let bench = TestDefaults.make(name, fenced: true)
        return (bench.defaults, NSTemporaryDirectory() + "mis-test-\(name)", bench.cleanup)
    }

    @Test func storingTheIslandOnBeforeTheRegistrationForcesSevenSwitchesOff() {
        let bench = freshBench()
        defer { bench.cleanup() }
        bench.defaults.set(true, forKey: DefaultsKey.notchEnabled)  // the old order of AppDelegate
        Defaults.registerDefaultValues(in: bench.defaults)
        Defaults.migrateExistingNotchDefaults(in: bench.defaults, domainName: bench.domain)
        let forced = Self.sevenKeys.filter { bench.defaults.persistentDomain(forName: bench.domain)?[$0] as? Bool == false }
        #expect(forced.count == 7, "the upstream trap the first-launch ordering must avoid")
    }

    @Test func aFreshInstallStoresTheIslandOnAfterTheRegistrationAndNothingIsForcedOff() {
        let bench = freshBench()
        defer { bench.cleanup() }
        IslandFirstLaunch.storeIslandOn(in: bench.defaults) {
            Defaults.registerDefaultValues(in: bench.defaults)
            Defaults.migrateExistingNotchDefaults(in: bench.defaults, domainName: bench.domain)
        }
        #expect(bench.defaults.bool(forKey: DefaultsKey.notchEnabled), "the island is the app")
        let stored = bench.defaults.persistentDomain(forName: bench.domain) ?? [:]
        for key in Self.sevenKeys { #expect(stored[key] as? Bool != false, Comment(rawValue: key)) }
        #expect(bench.defaults.bool(forKey: DefaultsKey.notchLyricsEnabled), "the registered default applies")
    }

    @Test func aMigratedChoiceOfTheIslandIsKept() {
        let bench = freshBench()
        defer { bench.cleanup() }
        bench.defaults.set(false, forKey: DefaultsKey.notchEnabled)
        IslandFirstLaunch.storeIslandOn(in: bench.defaults) { Defaults.registerDefaultValues(in: bench.defaults) }
        #expect(bench.defaults.bool(forKey: DefaultsKey.notchEnabled) == false)
    }

    // MARK: Live host tick

    @Test func aFeatureHostChangeTicksTheObservableSoPagesRedrawLive() async {
        let before = IslandHostTicker.shared.tick
        IslandActivityHost.shared.acquire("tick-test")
        let deadline = Date().addingTimeInterval(120)
        while IslandHostTicker.shared.tick == before, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(IslandHostTicker.shared.tick > before)
        let held = IslandHostTicker.shared.tick
        IslandActivityHost.shared.release("tick-test")
        let end = Date().addingTimeInterval(120)
        while IslandHostTicker.shared.tick == held, Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(IslandHostTicker.shared.tick > held, "releasing ticks too")
    }

    // MARK: Clipboard dock commands

    @Test func theClipboardDockCommandsFollowOurClipboardFeatureAndCallItsDoors() throws {
        PortHostFixture.isolated { _ in
            let saved = (PortDockCommands.clipboardIsOn, PortDockCommands.clearClipboardUnpinned,
                         PortDockCommands.pastePlainFromClipboard)
            defer {
                (PortDockCommands.clipboardIsOn, PortDockCommands.clearClipboardUnpinned,
                 PortDockCommands.pastePlainFromClipboard) = saved
            }
            var cleared = 0, pasted = 0
            var on = false
            PortDockCommands.clipboardIsOn = { on }
            PortDockCommands.clearClipboardUnpinned = { cleared += 1 }
            PortDockCommands.pastePlainFromClipboard = { pasted += 1 }
            PortHost.permissionState.send(PortPermissionState(accessibility: true))
            let commands = Dictionary(uniqueKeysWithValues: PortDockCommands.all().map { ($0.id, $0) })
            let clear = commands["port.clipboard.clearUnpinned"]!, plain = commands["port.pasteplain"]!

            #expect(clear.unavailableReason() != nil && plain.unavailableReason() != nil, "our clipboard off: both unavailable")
            on = true
            #expect(clear.unavailableReason() == nil, "the ported AppFeature flags no longer gate it")
            #expect(plain.unavailableReason() == nil)
            clear.run()
            plain.run()
            #expect(cleared == 1 && pasted == 1)
            PortHost.permissionState.send(PortPermissionState(accessibility: false))
            #expect(plain.unavailableReason() != nil, "plain paste still needs Accessibility")
        }
    }
}
