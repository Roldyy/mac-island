import Foundation
import Testing
@testable import PortKit

/// The pure parts of the mixer lane: volume math, device priority and auto-switch decisions, the output switch
/// guard, the stale aggregate sweep with a fake HAL, and the legacy settings. No Core Audio object is touched.
@MainActor
@Suite struct MixerLogicTests {
    // MARK: Volume math (0 to 200 %)

    @Test func theSliderRunsFromZeroToTwoHundredPercentAndClamps() {
        #expect(MixerVolumeMath.range == 0...2)
        #expect(AppVolumeMixer.maxVolume == 2)
        let percents = [-1.0, 0, 0.25, 0.5, 1, 1.5, 2, 3, .infinity].map(MixerVolumeMath.percent(forVolume:))
        #expect(percents == [0, 0, 25, 50, 100, 150, 200, 200, 100], "a level that is not finite plays untouched")
        #expect(MixerVolumeMath.percent(forVolume: .nan) == 100)
        #expect(MixerVolumeMath.clamped(7) == 2 && MixerVolumeMath.clamped(-7) == 0)
    }

    @Test func gainSquaresBelowUnityIsLinearAboveAndNeverLeavesTheRange() {
        #expect(MixerVolumeMath.gain(forVolume: 0) == 0)
        #expect(MixerVolumeMath.gain(forVolume: 0.5) == 0.25, "50 % is -12 dB")
        #expect(MixerVolumeMath.gain(forVolume: 1) == 1, "100 % is an untouched passthrough")
        #expect(MixerVolumeMath.gain(forVolume: 1.5) == 1.5)
        #expect(MixerVolumeMath.gain(forVolume: 2) == 2, "200 % is +6 dB")
        #expect(MixerVolumeMath.gain(forVolume: 9) == 2, "a stored value past 200 % is clamped before the audio thread")
        #expect(MixerVolumeMath.gain(forVolume: -3) == 0)
        var previous: Float = -1
        for step in 0...40 {
            let gain = MixerVolumeMath.gain(forVolume: Double(step) / 20)
            #expect(gain >= previous, "monotonic at \(step)")
            previous = gain
        }
    }

    @Test func aStoredVolumeFromTheRetiredModuleKeepsItsMeaning() {
        // The retired module stored slider positions 0...1 with a square law; the port stores the same positions.
        for position in stride(from: 0.0, through: 1.0, by: 0.125) {
            #expect(abs(Double(MixerRoutingSupport.gain(forVolume: position)) - position * position) < 1e-6)
            #expect(abs(MixerRoutingSupport.volume(forGain: position * position) - position) < 1e-6)
        }
    }

    // MARK: Priority ordering and auto-switch

    @Test func theHighestPriorityConnectedDeviceWinsAndAGoneOneIsSkipped() {
        let order = ["dock", "usb", "built-in"]
        func first(_ available: Set<String>) -> String? {
            MixerRoutingSupport.firstAvailablePriorityDeviceUID(orderedUIDs: order, availableUIDs: available)
        }
        #expect(first(["dock", "usb", "built-in"]) == "dock")
        #expect(first(["usb", "built-in"]) == "usb", "the dock left: the next one takes over")
        #expect(first(["built-in"]) == "built-in")
        #expect(first([]) == nil, "nothing ranked is connected: macOS keeps its own choice")
        #expect(first(["airpods"]) == nil, "an unranked device is never picked by the policy")
        #expect(MixerRoutingSupport.firstAvailablePriorityDeviceUID(
            orderedUIDs: ["", "dup", "dup", "usb"], availableUIDs: ["usb"]) == "usb", "blank and duplicate entries are skipped")
    }

    @Test func aSwitchIsRequestedOnlyForAnExistingDifferentTarget() {
        #expect(MixerRoutingSupport.shouldSwitchToDevice(targetUID: "dock", currentUID: "built-in"))
        #expect(!MixerRoutingSupport.shouldSwitchToDevice(targetUID: "dock", currentUID: "dock"), "already active")
        #expect(!MixerRoutingSupport.shouldSwitchToDevice(targetUID: nil, currentUID: "dock"), "no target, no write")
        #expect(MixerRoutingSupport.shouldSwitchToDevice(targetUID: "dock", currentUID: nil))
    }

    @Test func onlyAnEligibleUIDEnteringOrLeavingIsAPriorityEvent() {
        typealias R = MixerRoutingSupport
        #expect(!R.deviceAvailabilityChanged(previousUIDs: nil, currentUIDs: ["a"]), "the first reading is a baseline")
        #expect(!R.deviceAvailabilityChanged(previousUIDs: ["a", "b"], currentUIDs: ["a", "b"]))
        #expect(R.deviceAvailabilityChanged(previousUIDs: ["a"], currentUIDs: ["a", "b"]))
        #expect(R.deviceAvailabilityChanged(previousUIDs: ["a", "b"], currentUIDs: ["b"]))
    }

    @Test func aFirstTimeListLeadsWithTheDeviceInUseThenBuiltInThenHardwareThenVirtual() {
        let tiers: [String: MixerRoutingSupport.PriorityTier] = ["mac": .builtIn, "usb": .hardware, "bh": .virtual]
        func tier(_ uid: String) -> MixerRoutingSupport.PriorityTier { tiers[uid] ?? .hardware }
        let list = MixerRoutingSupport.initialPriorityList(
            availableUIDs: ["bh", "usb", "mac", "usb"], currentUID: "usb", tier: tier)
        #expect(list == ["usb", "mac", "bh"])
        #expect(MixerRoutingSupport.initialPriorityList(
            availableUIDs: ["bh", "usb", "mac"], currentUID: nil, tier: tier) == ["mac", "usb", "bh"])
        // A new device goes first when it is the one macOS just chose, above virtual devices otherwise.
        #expect(MixerRoutingSupport.placingNewPriorityDevice("pods", in: ["mac", "bh"], isCurrent: true, tier: tier)
                == ["pods", "mac", "bh"])
        #expect(MixerRoutingSupport.placingNewPriorityDevice("pods", in: ["mac", "bh"], isCurrent: false, tier: tier)
                == ["mac", "pods", "bh"])
        #expect(MixerRoutingSupport.placingNewPriorityDevice("mac", in: ["mac"], isCurrent: true, tier: tier) == ["mac"],
                "a ranked device keeps its place")
    }

    @Test func theOutputSwitcherCyclesTheSelectionAndNeverTargetsAMissingDevice() {
        func next(_ current: String?, _ selected: [String], _ available: Set<String>) -> String? {
            MixerRoutingSupport.nextSelectedOutputDeviceUID(currentUID: current, selectedUIDs: selected,
                                                            availableUIDs: available)
        }
        let all: Set<String> = ["mac", "dock", "tv"]
        #expect(next("mac", ["mac", "dock", "tv"], all) == "dock")
        #expect(next("tv", ["mac", "dock", "tv"], all) == "mac", "wraps around")
        #expect(next("mac", ["mac", "dock", "tv"], ["mac", "tv"]) == "tv", "the unplugged dock is skipped")
        #expect(next("mac", ["mac", "dock"], ["mac"]) == nil, "only one output left: nowhere to go")
        #expect(next("mac", ["dock"], ["mac"]) == nil, "the whole selection is gone")
        #expect(next("other", ["mac", "dock"], all) == "mac", "a current device outside the selection joins at the start")
        #expect(next(nil, [], all) == nil)
    }

    @Test func theFeaturesThatShareTheDeviceWatchAreTheThree() {
        func needs(_ on: Set<AppFeature>) -> (devices: Bool, processes: Bool) {
            MixerRoutingSupport.observationNeeds(isAvailable: { on.contains($0) })
        }
        #expect(needs([]) == (false, false))
        #expect(needs([.mixer]) == (true, true))
        #expect(needs([.soundOutputSwitcher]) == (true, false), "no process watching, so no per-app tap")
        #expect(needs([.audioPriority]) == (true, false))
        #expect(needs([.audioPriority, .soundOutputSwitcher]) == (true, false))
    }

    // MARK: Output volume restore

    @Test func aVolumeTheMixerLoweredIsHandedBackOnlyWhileItIsStillTheValueItSet() {
        typealias R = MixerRoutingSupport
        #expect(R.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.25))
        #expect(!R.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.6), "the user moved it since: that wins")
        #expect(!R.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: nil), "an unreadable output is left alone")
        // A mute is only set by the lowering when the output was audible, so only that mute is ever undone.
        #expect(R.shouldMuteOutputLoweredForDisconnect(lowerToPercent: 0, currentlyMuted: false))
        #expect(!R.shouldMuteOutputLoweredForDisconnect(lowerToPercent: 0, currentlyMuted: true))
        #expect(!R.shouldMuteOutputLoweredForDisconnect(lowerToPercent: 0, currentlyMuted: nil))
        #expect(!R.shouldMuteOutputLoweredForDisconnect(lowerToPercent: 25, currentlyMuted: false))
    }

    @Test func theStopPathRestoresALoweredOutputBeforeAnythingElse() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Services/Audio/AppVolumeMixer.swift"),
                              encoding: .utf8)
        let stopAll = try #require(text.range(of: "func stopAll() {"))
        let body = text[stopAll.upperBound...].prefix(600)
        #expect(body.contains("engine.stop()") && body.contains("restoreLoweredOutputVolume()"),
                "taps stop and the lowered system volume comes back in the same teardown")
    }

    // MARK: Output switch guard

    @Test func theSystemIsNeverPointedAtADeviceThatIsGoneNotAnOutputOrCannotBeDefault() {
        typealias G = MixerOutputSwitchGuard
        #expect(G.allows(.init(isAlive: true, hasOutputStreams: true, canBeDefault: true)))
        #expect(G.allows(.init(isAlive: nil, hasOutputStreams: true, canBeDefault: true)), "a virtual device with no alive flag")
        #expect(!G.allows(.init(isAlive: false, hasOutputStreams: true, canBeDefault: true)), "unplugged")
        #expect(!G.allows(.init(isAlive: nil, hasOutputStreams: false, canBeDefault: false)), "unreadable: gone")
        #expect(!G.allows(.init(isAlive: true, hasOutputStreams: false, canBeDefault: true)), "an input-only device")
        #expect(!G.allows(.init(isAlive: true, hasOutputStreams: true, canBeDefault: false)))
    }

    // MARK: Stale aggregates (fake HAL)

    final class FakeHAL: MixerHAL {
        var devices: [(id: UInt32, name: String)]
        var destroyed: [UInt32] = []
        var failing: Set<UInt32> = []
        init(_ devices: [(id: UInt32, name: String)]) { self.devices = devices }
        func aggregateDevices() -> [(id: UInt32, name: String)] { devices }
        func destroyAggregate(_ id: UInt32) -> Bool {
            destroyed.append(id)
            return !failing.contains(id)
        }
    }

    @Test func theLaunchSweepDestroysOurStaleAggregatesAndNothingElse() {
        let hal = FakeHAL([(10, "Mac Island Mixer"), (11, "Mac Island AirPlay"), (12, "Mac Island Mixer 2"),
                           (13, "Mac Island Recorder"), (14, "Mac Island Island Levels"), (15, "BlackHole 2ch"),
                           (16, "Multi-Output Device"), (17, "mac island mixer")])
        let removed = MixerStaleAggregateSweeper.sweep(hal: hal)
        #expect(hal.destroyed == [10, 11, 12])
        #expect(removed == ["Mac Island Mixer", "Mac Island AirPlay", "Mac Island Mixer 2"])
    }

    @Test func aDeviceThatWillNotGoIsNotReportedAndTheSweepContinues() {
        let hal = FakeHAL([(1, "Mac Island Mixer"), (2, "Mac Island Mixer")])
        hal.failing = [1]
        #expect(MixerStaleAggregateSweeper.sweep(hal: hal) == ["Mac Island Mixer"])
        #expect(hal.destroyed == [1, 2])
        #expect(MixerStaleAggregateSweeper.sweep(hal: FakeHAL([])).isEmpty)
    }

    @Test func theSweepNamesAreTheOnesTheMixerGivesItsAggregates() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Services/Audio/AppVolumeMixer.swift"),
                              encoding: .utf8)
        for prefix in MixerStaleAggregateSweeper.namePrefixes {
            #expect(text.contains("kAudioAggregateDeviceNameKey: \"\(prefix)\""), "\(prefix)")
        }
        #expect(text.components(separatedBy: "kAudioAggregateDeviceNameKey").count - 1 == 2,
                "a third aggregate name would escape the sweep")
    }

    // MARK: AirPlay probe

    @Test func airPlayFailsClosedWithAFrenchReason() {
        #expect(MixerAirPlayProbe.unavailableReason(osMajor: 15, managerAvailable: nil)?.hasPrefix("AirPlay par app") == true)
        #expect(MixerAirPlayProbe.unavailableReason(osMajor: 26, managerAvailable: true)?.contains("27") == true)
        #expect(MixerAirPlayProbe.unavailableReason(osMajor: 27, managerAvailable: false)?.contains("reste éteinte") == true)
        #expect(MixerAirPlayProbe.unavailableReason(osMajor: 27, managerAvailable: true) == nil)
        #expect(MixerAirPlayProbe.unavailableReason(osMajor: 27, managerAvailable: nil) == nil)
    }

    // MARK: Legacy settings

    @Test func aMutedAppOfTheRetiredModuleBecomesVolumeZeroOnceAndTheOldKeyGoes() {
        PortHostFixture.isolated { defaults in
            defaults.set(["com.a", "com.b", ""], forKey: MixerLegacySettings.mutedAppsKey)
            defaults.set(["com.b": 0.7, "com.c": 0.4], forKey: DefaultsKey.appVolumes)
            let changed = MixerLegacySettings.migrateMutedApps(in: defaults)
            #expect(changed == ["com.a"], "an app whose slider the user already moved keeps it")
            let volumes = defaults.dictionary(forKey: DefaultsKey.appVolumes) as? [String: Double]
            #expect(volumes == ["com.a": 0, "com.b": 0.7, "com.c": 0.4])
            #expect(defaults.object(forKey: MixerLegacySettings.mutedAppsKey) == nil)
            #expect(MixerLegacySettings.migrateMutedApps(in: defaults).isEmpty, "idempotent")
            #expect(defaults.dictionary(forKey: DefaultsKey.appVolumes)?.count == 3)
        }
    }

    @Test func noMutedAppsLeavesTheStoredVolumesUntouched() {
        PortHostFixture.isolated { defaults in
            defaults.set(["com.c": 0.4], forKey: DefaultsKey.appVolumes)
            #expect(MixerLegacySettings.migrateMutedApps(in: defaults).isEmpty)
            #expect(defaults.dictionary(forKey: DefaultsKey.appVolumes) as? [String: Double] == ["com.c": 0.4])
        }
    }
}
