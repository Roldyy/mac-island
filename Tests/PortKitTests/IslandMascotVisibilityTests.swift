import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Harold's bug: "Le compagnon n'apparait pas sur l'île lorsque actif". The whole path, switch to closed strip:
/// FeatureRegistry switch -> `IslandLockScreenLane` start -> the ported gate (`NotchMascotSupport.isEnabled`) -> an
/// `AmbientIndicator` on an `AmbientCenter` -> the content the closed strip draws. Fakes only: no panel.
@MainActor
@Suite(.serialized) struct IslandMascotVisibilityTests {
    struct Rig {
        let registry: FeatureRegistry
        let binding: PortFeatureBinding  // the registry's starters hold it unowned
        let ambient: AmbientCenter
        let cleanup: () -> Void
    }

    /// A registry running the real mascot start and stop (host flag, seed, presence) against a local ambient center.
    func rig(defaults: UserDefaults, notched: Bool = true) -> Rig {
        let bench = TestDefaults.make()
        ClosedIslandSettings.standard.write(to: bench.defaults)
        bench.defaults.set(true, forKey: ClosedIslandKeys.migrated)
        let ambient = AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: bench.defaults),
                                    isNotched: notched, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        let presence = IslandMascotPresence(hooks: .init(
            isShown: { NotchMascotSupport.isEnabled(in: defaults) },
            side: { NotchMascotSupport.side(in: defaults) },
            post: { ambient.post($0) }, withdraw: { ambient.withdraw(id: $0) },
            observe: { onChange in
                NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                    .sink { _ in MainActor.assumeIsolated { onChange() } }
            }))
        let runtime = IslandLockScreenLane.Runtime(
            startLock: {}, stopLock: {}, startGestures: {}, stopGestures: {},
            startMascot: { IslandLockScreenLane.Runtime.mascotStart(presence: presence)() },
            stopMascot: { IslandLockScreenLane.Runtime.mascotStop(presence: presence)() })
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        IslandLockScreenLane.bind(into: binding, runtime: runtime)
        binding.connectAvailability()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(registry: registry, binding: binding, ambient: ambient, cleanup: {
            registry.switches["notchMascot"] = false
            bench.cleanup(); marker.clear()
            IslandActivityHost.shared.release("notchMascot")
        })
    }

    func mascotItems(_ ambient: AmbientCenter) -> [AmbientIndicator] {
        ambient.content.all.filter { $0.channel == AmbientChannel.mascot && $0.glyph == .mascot }
    }

    @Test func switchingTheCompanionOnShowsItInTheClosedStripAndSwitchingOffRemovesIt() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            let r = rig(defaults: defaults)
            defer { r.cleanup() }
            #expect(mascotItems(r.ambient).isEmpty, "off by default: the closed island keeps its five indicators")
            #expect(NotchMascotSupport.isEnabled(in: defaults) == false)

            r.registry.switches["notchMascot"] = true

            #expect(NotchMascotSupport.isEnabled(in: defaults), "the registry switch alone must make the ported gate say yes")
            #expect(mascotItems(r.ambient).count == 1)
            #expect(mascotItems(r.ambient).first?.label == "Compagnon", "VoiceOver names it")

            r.registry.switches["notchMascot"] = false
            #expect(mascotItems(r.ambient).isEmpty)
            #expect(IslandActivityHost.shared.holds("notchMascot") == false)
        }
    }

    @Test func itRestsOnTheSideThePersonChoseAndFollowsAChange() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            let r = rig(defaults: defaults)
            defer { r.cleanup() }
            defaults.set(NotchMascotSide.right.rawValue, forKey: DefaultsKey.notchMascotSide)
            r.registry.switches["notchMascot"] = true
            #expect(r.ambient.content.trailing.contains { $0.glyph == .mascot })
            defaults.set(NotchMascotSide.left.rawValue, forKey: DefaultsKey.notchMascotSide)
            #expect(r.ambient.content.leading.contains { $0.glyph == .mascot }, "re-read when the side preference changes")
            #expect(!r.ambient.content.trailing.contains { $0.glyph == .mascot })
        }
    }

    @Test func theCompanionsOwnToggleOnItsPageStillSwitchesItOffAndTheSeedIsNotReappliedAtRestart() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            let r = rig(defaults: defaults)
            defer { r.cleanup() }
            r.registry.switches["notchMascot"] = true
            #expect(mascotItems(r.ambient).count == 1)
            defaults.set(false, forKey: DefaultsKey.notchMascotEnabled)  // the toggle on the Compagnon page
            #expect(mascotItems(r.ambient).isEmpty)
            r.registry.switches["notchMascot"] = false
            r.registry.switches["notchMascot"] = true
            #expect(defaults.bool(forKey: DefaultsKey.notchMascotEnabled) == false, "a person's choice is not undone by a restart")
            #expect(mascotItems(r.ambient).isEmpty)
        }
    }

    @Test func thePageShowsItToo() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            let r = rig(defaults: defaults)
            defer { r.cleanup() }
            r.registry.switches["notchMascot"] = true
            // `IslandMascotView` draws only while the host holds the flag AND the ported gate says yes: both true.
            #expect(IslandActivityHost.shared.holds("notchMascot"))
            #expect(NotchMascotSupport.isEnabled(in: defaults))
        }
    }

    @Test func theClosedIslandRegistersItsDrawingForTheCompanion() {
        PortHostFixture.isolated { defaults in
            Defaults.registerDefaultValues(in: defaults)
            AmbientMascotSlot.make = nil
            let r = rig(defaults: defaults)
            defer { r.cleanup() }
            r.registry.switches["notchMascot"] = true
            #expect(AmbientMascotSlot.make != nil)
        }
    }
}
