import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// The energy lane against a real `FeatureRegistry`, a fake runtime and a fake permission state: Keep Awake adopted
/// under OUR registry id (one implementation), the three other features bound with their descriptors, start and
/// stop, the kill switch, the quit hook, shortcut ownership. Nothing here touches pmset, sudo, IOPM, Bluetooth or
/// CoreAudio: the runtime is a recorder.
@MainActor
@Suite(.serialized) struct EnergyLaneTests {
    final class Recorder {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    func runtime(_ log: Recorder) -> EnergyLane.Runtime {
        EnergyLane.Runtime(
            keepAwakeStart: { log.events.append("start keepawake") },
            keepAwakeStop: { log.events.append("stop keepawake") },
            keepAwakeQuit: { log.events.append("quit keepawake") },
            bluetoothStart: { log.events.append("start bluetooth") },
            bluetoothStop: { log.events.append("stop bluetooth") },
            bluetoothQuit: { log.events.append("quit bluetooth") },
            micStart: { log.events.append("start mic") },
            micStop: { log.events.append("stop mic") },
            micQuit: { log.events.append("quit mic") },
            musicStart: { log.events.append("start music") },
            musicStop: { log.events.append("stop music") })
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Recorder
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    /// `switchedOn` turns the three ported features on (Keep Awake is on by default, like the other 13 modules).
    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true), switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let log = Recorder()
        EnergyLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, permissions: permissions,
                   cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptors and permissions

    @Test func theThreePortedFeaturesGetADescriptorAndKeepAwakeDoesNot() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        EnergyLane.bind(into: binding, runtime: runtime(Recorder()))
        #expect(binding.descriptors.map(\.id) == ["bluetoothSleep", "micMute", "musicBlock"])
        #expect(!binding.descriptors.map(\.id).contains("keepawake"), "ours owns that descriptor: one switch")
        #expect(binding.starters.keys.contains("keepawake") && binding.stoppers.keys.contains("keepawake"))
    }

    @Test func descriptorTableIsFrenchOffByDefaultWithTheCatalogPermissionsAndRisk() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        EnergyLane.bind(into: binding, runtime: runtime(Recorder()))
        let byID = Dictionary(uniqueKeysWithValues: binding.descriptors.map { ($0.id, $0) })
        let bluetooth = byID["bluetoothSleep"]!
        let mic = byID["micMute"]!
        let music = byID["musicBlock"]!
        for d in [bluetooth, mic, music] {
            #expect(!d.title.isEmpty && !d.summary.isEmpty)
            #expect(d.enabledByDefault == false, "\(d.id)")
        }
        #expect(bluetooth.permissions.isEmpty && bluetooth.risk == .touchesSystem && bluetooth.category == .display)
        #expect(mic.permissions.isEmpty && mic.risk == .touchesSystem && mic.category == .sound)
        #expect(music.permissions == [.accessibility] && music.category == .sound)
        #expect(bluetooth.title == "Bluetooth en veille" || bluetooth.title.contains("Bluetooth"))
        #expect(mic.title.lowercased().contains("micro"))
    }

    @Test func pagesPointAtOurSettingsPageIds() {
        #expect(EnergyLane.pageIDs[.keepAwake] == "keepawake")
        #expect(EnergyLane.pageIDs[.bluetoothSleep] == "btsleep")
        #expect(EnergyLane.pageIDs[.micMute] == "mutemic")
        #expect(EnergyLane.pageIDs[.musicBlock] == "musicblock")
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        EnergyLane.bind(into: binding, runtime: runtime(Recorder()))
        #expect(binding.pages.map(\.pageID) == ["btsleep", "mutemic", "musicblock"], "keepawake's page is a plain body")
        #expect(Set(binding.pages.map(\.featureID)) == ["bluetoothSleep", "micMute", "musicBlock"])
        for id in ["keepawake", "btsleep", "mutemic", "musicblock"] {
            #expect(SettingsPageCatalog.page(id) != nil, "\(id) is a real page of the catalog")
        }
    }

    // MARK: Start and stop through the registry

    @Test func keepAwakeStartsAtLaunchByDefaultAndTheOthersWaitForTheirSwitch() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        #expect(r.log.events == ["start keepawake"], "default-on, like before the merge")
        r.registry.switches["micMute"] = true
        #expect(r.log.count("start mic") == 1)
        r.registry.switches["bluetoothSleep"] = true
        #expect(r.log.count("start bluetooth") == 1)
    }

    @Test func musicBlockWaitsForAccessibilityAndTheOthersNeverDo() {
        let r = rig(granted: PortPermissionState())
        defer { r.cleanup() }
        #expect(r.log.count("start keepawake") == 1, "Keep Awake needs no permission: the jiggle asks for its own")
        #expect(r.log.count("start bluetooth") == 1 && r.log.count("start mic") == 1)
        #expect(r.log.count("start music") == 0)
        r.permissions.value = PortPermissionState(accessibility: true)
        r.registry.permissionsChanged(PermissionChange(
            old: PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: false),
            new: PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)))
        #expect(r.log.count("start music") == 1)
    }

    @Test func aSwitchOffStopsOnlyThatFeature() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["micMute"] = false
        #expect(r.log.count("stop mic") == 1)
        #expect(r.log.count("stop bluetooth") == 0 && r.log.count("stop keepawake") == 0 && r.log.count("stop music") == 0)
    }

    @Test func theKillSwitchStopsKeepAwakeMicBluetoothAndMusicBlock() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.killSwitch = true
        for name in ["keepawake", "mic", "bluetooth", "music"] {
            #expect(r.log.count("stop \(name)") == 1, "the kill switch must reach \(name)")
        }
        r.registry.killSwitch = false
        for name in ["keepawake", "mic", "bluetooth", "music"] { #expect(r.log.count("start \(name)") == 2) }
    }

    @Test func safeModeHoldsDownTheThreeRiskyFeaturesButKeepsTheDailyKeepAwake() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.safeMode = true
        for name in ["mic", "bluetooth", "music"] { #expect(r.log.count("stop \(name)") == 1, "\(name)") }
        // The registry keeps the `daily` category up in safe mode, as it did for our Keep Awake before the merge.
        #expect(r.log.count("stop keepawake") == 0)
        #expect(r.registry.state(for: "keepawake") != .safeMode)
    }

    @Test func startIsIdempotentButStopAlwaysReachesTheRestore() {
        let r = rig()
        defer { r.cleanup() }
        r.binding.starters["micMute"]!()
        r.binding.starters["micMute"]!()
        #expect(r.log.count("start mic") == 1)
        r.binding.stoppers["micMute"]!()
        r.binding.stoppers["micMute"]!()
        #expect(r.log.count("stop mic") == 2, "a stop never depends on what was remembered")
    }

    // MARK: Availability, ownership

    @Test func keepAwakeAvailabilityFollowsOurRegistryNotAStoredKey() {
        PortHostFixture.isolated { defaults in
            let r = rig()
            defer { r.cleanup() }
            r.binding.connectAvailability()
            #expect(AppFeature.keepAwake.isAvailable, "the ported manager may start a session")
            r.registry.killSwitch = true
            #expect(!AppFeature.keepAwake.isAvailable, "the kill switch holds the ported manager down")
            #expect(defaults.object(forKey: AppFeature.keepAwake.availabilityKey) == nil, "no key was written")
            r.registry.killSwitch = false
            r.registry.switches["keepawake"] = false
            #expect(!AppFeature.keepAwake.isAvailable)
            #expect(AppFeature.keepAwake.availabilityKey == "shell.enabled.keepawake", "one switch, our id")
        }
    }

    @Test func theKeepAwakeShortcutKeepsOneOwner() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.binding.connectAvailability()
            #expect(!PortShortcutOwnership.upstreamKeepAwakeHotkeyAllowed, "only KeepAwakeShortcutService registers it")
            #expect(!PortShortcutOwnership.isRunning(.keepAwake), "the central editor never lists a second key for it")
            #expect(!PortShortcutOwnership.isBound(.keepAwake))
            #expect(PortShortcutOwnership.isRunning(.micMute), "the microphone shortcut is the ported service's")
            #expect(PortShortcutOwnership.isBound(.bluetoothSleep))
        }
    }

    @Test func theMicrophoneShortcutIsNotTheKeepAwakeOne() {
        #expect(GlobalShortcut.micMuteDefault != GlobalShortcut.keepAwakeDefault)
        #expect(GlobalShortcutRole.micMute.storageKey == DefaultsKey.micMuteShortcut)
        #expect(GlobalShortcutRole.keepAwake.storageKey == DefaultsKey.keepAwakeShortcut)
    }

    // MARK: Quit

    @Test func quitGivesBackSleepTheMicrophoneAndBluetooth() {
        let log = Recorder()
        EnergyLane.quit(runtime: runtime(log))
        #expect(log.events == ["quit keepawake", "quit mic", "quit bluetooth"], "sleep first, then the mic and the radio")
    }

    // MARK: Ported manager API is not reachable from a prompt-free path

    @Test func theFacadeHasNoPromptingEntryPoint() {
        let public_ = ["snapshot", "snapshots", "toggle", "start", "stop", "defaultMinutes"]
        // Reading the source keeps the public surface of the facade to what the shell needs.
        let text = (try? String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/Energy.swift"),
                                encoding: .utf8)) ?? ""
        let facade = text.components(separatedBy: "public enum PortKeepAwake")[1].components(separatedBy: "// MARK: - The lane")[0]
        let declared = facade.split(separator: "\n").filter { $0.contains("public static") }
        for line in declared { #expect(public_.contains { line.contains(" \($0)") }, "\(line)") }
        #expect(!facade.contains("setClosedLidMode") && !facade.contains("restoreSleepFromClick"),
                "the shell can never reach the prompting entry points: only the Energy page does")
    }
}
