import Foundation
import Testing
@testable import PortKit

/// A Mac shut down while asleep (Bluetooth switched off for the sleep) or killed with the microphone muted must get
/// both back at the next launch, even when the registry will not start the feature (kill switch, quarantine, safe
/// mode): the launch recovery owes them, not the lane. Fakes only: no Bluetooth, no audio device is touched.
@MainActor
@Suite struct RecoveryOwedRestoreTests {
    private func recover(_ defaults: UserDefaults) -> (bluetooth: Int, mic: Int) {
        var bluetooth = 0
        var mic = 0
        PortBridge.resetRecoveryForTesting()
        PortBridge.recoverAtLaunch(defaults: defaults, restoreBluetooth: { bluetooth += 1 }, unmuteMic: { mic += 1 })
        return (bluetooth, mic)
    }

    @Test func noMarkerEntersNeitherStep() {
        PortHostFixture.isolated { defaults in
            let plan = PortBridge.RecoveryPlan(defaults: defaults)
            #expect(!plan.bluetoothRestore && !plan.micUnmute)
            let ran = recover(defaults)
            #expect(ran.bluetooth == 0 && ran.mic == 0, "a Mac where nothing was owed gets no service built")
        }
    }

    @Test func aBluetoothRestoreStillOwedIsPaidAtLaunch() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.bluetoothSleepRestorePending)
            #expect(PortBridge.RecoveryPlan(defaults: defaults).bluetoothRestore)
            let ran = recover(defaults)
            #expect(ran.bluetooth == 1 && ran.mic == 0)
        }
    }

    @Test func aMicrophoneMuteStillOwedIsGivenBackAtLaunch() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.micMuteActive)
            #expect(PortBridge.RecoveryPlan(defaults: defaults).micUnmute)
            let ran = recover(defaults)
            #expect(ran.mic == 1 && ran.bluetooth == 0)
        }
    }

    @Test func aDeviceStillClaimedIsGivenBackEvenWithTheFlagClear() {
        PortHostFixture.isolated { defaults in
            defaults.set(false, forKey: DefaultsKey.micMuteActive)
            defaults.set(["BuiltInMicrophoneDevice"], forKey: DefaultsKey.micMuteMutedDevices)
            #expect(recover(defaults).mic == 1)
        }
    }

    @Test func bothAreOwedWhateverTheFeatureAvailability() {
        PortHostFixture.isolated { defaults in
            // Kill switch / quarantine / safe mode: the registry answers "not available" for every feature, so
            // neither lane's start nor stop will ever run.
            PortHost.availability = { _ in false }
            PortHost.storedSwitch = { _ in false }
            defaults.set(true, forKey: DefaultsKey.bluetoothSleepRestorePending)
            defaults.set(true, forKey: DefaultsKey.micMuteActive)
            let ran = recover(defaults)
            #expect(ran.bluetooth == 1 && ran.mic == 1)
        }
    }

    @Test func theRestoresRunBeforeTheRegistryStartsAnything() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.bluetoothSleepRestorePending)
            defaults.set(true, forKey: DefaultsKey.micMuteActive)
            var events: [String] = []
            PortBridge.resetRecoveryForTesting()
            PortBridge.launchAfterRecovery(
                recover: {
                    PortBridge.recoverAtLaunch(defaults: defaults,
                                               restoreBluetooth: { events.append("bluetooth") },
                                               unmuteMic: { events.append("mic") })
                },
                start: { events.append("registry.launch") })
            #expect(events == ["bluetooth", "mic", "registry.launch"])
        }
    }

    @Test func theRecoveryIsOnceAndTheSecondCallPaysNothing() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.bluetoothSleepRestorePending)
            var bluetooth = 0
            PortBridge.resetRecoveryForTesting()
            PortBridge.recoverAtLaunch(defaults: defaults, restoreBluetooth: { bluetooth += 1 })
            PortBridge.recoverAtLaunch(defaults: defaults, restoreBluetooth: { bluetooth += 1 })
            #expect(bluetooth == 1)
        }
    }

    @Test func theLiveSeamsAreTheServicesOwnRestorePaths() throws {
        let source = try String(
            contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/PortKit/Bridge/PortBridge.swift"),
            encoding: .utf8)
        #expect(source.contains("BluetoothSleepService.shared.restoreNow()"))
        #expect(source.contains("MicMuteService.shared.unmuteForTeardown()"))
    }
}
