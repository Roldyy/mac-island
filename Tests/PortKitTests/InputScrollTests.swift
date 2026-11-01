import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W1A (scroll): the four scroll features bound through `PortFeatureBinding` with a FAKE runtime, so no event
/// tap is ever created here. Covers the descriptors, off by default, the permission gate, the kill switch, safe
/// mode, the shared wheel tap, the Settings pages and the source contract of the three taps.
@MainActor
@Suite(.serialized) struct InputScrollTests {
    static let ids = ["scrollInverter", "scrollHorizontal", "smoothScroll", "linearScroll"]

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: InputScrollLane.Runtime {
            InputScrollLane.Runtime(
                syncWheelTap: { [self] in events.append("syncWheel") },
                suspendWheelTap: { [self] in events.append("suspendWheel") },
                syncSmoothScroll: { [self] in events.append("syncSmooth") },
                suspendSmoothScroll: { [self] in events.append("suspendSmooth") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true), switchedOn: Bool = true,
             runtime: InputScrollLane.Runtime? = nil) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let fake = FakeRuntime()
        InputScrollLane.bind(into: binding, runtime: runtime ?? fake.runtime)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        binding.connectAvailability()
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, fake: fake, permissions: permissions,
                   cleanup: { bench.cleanup(); marker.clear() })
    }

    func change(_ rig: Rig, to new: PortPermissionState) {
        let old = rig.permissions.value
        rig.permissions.value = new
        rig.registry.permissionsChanged(PermissionChange(
            old: PermissionSnapshot(accessibility: old.accessibility, inputMonitoring: old.inputMonitoring,
                                    screenRecording: old.screenRecording),
            new: PermissionSnapshot(accessibility: new.accessibility, inputMonitoring: new.inputMonitoring,
                                    screenRecording: new.screenRecording)))
    }

    // MARK: Descriptors

    @Test func theLaneBindsTheFourScrollFeaturesWithFrenchTextAndAccessibility() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            InputScrollLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            for d in binding.descriptors {
                #expect(d.category == .input, "\(d.id)")
                #expect(d.permissions == [.accessibility], "\(d.id)")
                #expect(d.risk == .touchesInput, "\(d.id)")
                #expect(!d.enabledByDefault, "\(d.id)")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id)")
                #expect(!d.title.contains("scroll") && !d.title.lowercased().contains("smooth"), "French, not English: \(d.title)")
            }
            #expect(binding.descriptors.map(\.title).contains("Défilement fluide"))
            #expect(binding.descriptors.map(\.title).contains("Défilement linéaire"))
        }
    }

    @Test func theLiveLaneBindsTheSameFour() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            InputScrollLane.bind(into: binding)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            #expect(PortLanes.all.count == 5, "PortLanes lists the foundation lane and the four input lanes")
        }
    }

    // MARK: Off by default, permission gate

    @Test func everythingIsOffAndNothingRunsUntilTheSwitchesAreOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty)
            for id in Self.ids { #expect(r.registry.state(for: id) == .off, "\(id)") }
        }
    }

    @Test func nothingStartsWithoutAccessibilityAndAGrantStartsThem() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "switched on, Accessibility missing: no service was touched")
            for id in Self.ids { #expect(r.registry.state(for: id) == .needsPermission(.accessibility), "\(id)") }
            change(r, to: PortPermissionState(accessibility: true))
            // The registry restarts a feature whose start ran while the permission was missing: a stop (harmless, it
            // armed nothing) then a start. What matters is where each tap ends up.
            #expect(Self.ids.allSatisfy { r.binding.isStarted($0) })
            #expect(r.fake.events.filter { $0.hasSuffix("Wheel") }.last == "syncWheel")
            #expect(r.fake.events.filter { $0.hasSuffix("Smooth") }.last == "syncSmooth")
        }
    }

    @Test func startIsIdempotent() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let before = r.fake.events
            for id in Self.ids { r.binding.starters[id]!() }
            #expect(r.fake.events == before, "a second start of a running feature reaches nothing")
        }
    }

    // MARK: Stops

    @Test func theKillSwitchStopsAllFourAndTheSharedTapGoesDownWithTheLastOne() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.count("suspendWheel") == 1, "the shared wheel tap is force-stopped exactly once")
            #expect(r.fake.count("suspendSmooth") == 1)
            #expect(r.fake.events.filter { $0.hasSuffix("Wheel") }.last == "suspendWheel", "...by the last of its three")
            #expect(r.fake.count("syncWheel") == 2, "the first two only re-sync: another feature still needs the tap")
            for id in Self.ids { #expect(r.registry.state(for: id) == .killed, "\(id)") }
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.count("syncWheel") == 3 && r.fake.count("syncSmooth") == 1, "lifting it starts them again")
        }
    }

    @Test func safeModeStopsAllFour() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.count("suspendWheel") == 1 && r.fake.count("suspendSmooth") == 1)
            #expect(r.binding.isStarted("smoothScroll") == false && r.binding.isStarted("scrollInverter") == false)
        }
    }

    @Test func aPermissionRevokeStopsThemAndTheGrantRestartsThem() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            change(r, to: PortPermissionState())
            #expect(r.fake.count("suspendWheel") == 1 && r.fake.count("suspendSmooth") == 1)
            r.fake.events.removeAll()
            change(r, to: PortPermissionState(accessibility: true))
            #expect(r.fake.count("syncWheel") == 3 && r.fake.count("syncSmooth") == 1)
        }
    }

    @Test func switchingOneWheelFeatureOffKeepsTheTapForTheOthersUntilTheLastIsOff() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.switches["linearScroll"] = false
            #expect(r.fake.events == ["syncWheel"], "scrollInverter and scrollHorizontal still run: re-sync, no force-stop")
            r.registry.switches["scrollHorizontal"] = false
            #expect(r.fake.events == ["syncWheel", "syncWheel"])
            r.registry.switches["scrollInverter"] = false
            #expect(r.fake.events == ["syncWheel", "syncWheel", "suspendWheel"], "the last one removes the tap")
            #expect(r.fake.count("suspendSmooth") == 0, "smooth scrolling has its own tap and is untouched")
            r.registry.switches["smoothScroll"] = false
            #expect(r.fake.count("suspendSmooth") == 1)
        }
    }

    // MARK: Real services, inert

    @Test func theRealServicesStayDownWhileTheirPageTogglesAreOff() {
        PortHostFixture.isolated { _ in
            // Empty defaults: every page toggle is off, so even with the registry on and Accessibility "granted" the
            // real `syncWithPreferences` arms nothing. No tap is created.
            let r = rig(runtime: .live)
            defer { r.cleanup() }
            #expect(!ScrollInverter.shared.isRunning)
            #expect(!SmoothScrollService.shared.isRunning)
            r.registry.killSwitch = true
            #expect(!ScrollInverter.shared.isRunning && !SmoothScrollService.shared.isRunning)
        }
    }

    // MARK: Settings pages

    @Test func fourPagesAreRegisteredAndReplaceTheComingSoonRows() {
        PortHostFixture.isolated { _ in
            SettingsPageBodies.removeAll()
            defer { SettingsPageBodies.removeAll() }
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            let pages = r.binding.pages
            #expect(pages.map(\.pageID) == ["scrollreverse", "hscroll", "smoothscroll", "linearscroll"])
            #expect(pages.map(\.featureID) == Self.ids)
            for ported in pages {
                let page = SettingsPageCatalog.page(ported.pageID)!
                #expect(page.isComingSoon, "\(ported.pageID): a stub until the body is registered")
                #expect(!SettingsPageModel.blocks(for: page).isEmpty, "\(ported.pageID): placeholder rows noted from the reference")
                SettingsPageBodies.register(pageID: ported.pageID, featureID: ported.featureID, registry: r.registry,
                                            openPermission: { _ in }, ported.body)
                #expect(!page.isComingSoon, "\(ported.pageID)")
                #expect(SettingsPageModel.blocks(for: page).isEmpty, "\(ported.pageID): no greyed 'Bientôt' row stays under the body")
            }
        }
    }

    @Test func eachPageBodyRendersItsOwnCardEvenWhileTheFeatureIsOff() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            for ported in r.binding.pages {
                let host = NSHostingView(rootView: ported.body())
                host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 40, "\(ported.pageID) rendered \(host.fittingSize): empty while the feature is off")
            }
        }
    }

    // MARK: Source contract of the three taps (read from the files, nothing runs)

    private static let services = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/PortKit/Services")

    private func source(_ name: String) throws -> String {
        try String(contentsOf: Self.services.appendingPathComponent(name), encoding: .utf8)
    }

    @Test func everyScrollTapIsRemovedOnStopAndRearmedWhenTheSystemDisablesIt() throws {
        for name in ["ScrollInverter.swift", "SmoothScrollService.swift", "ScrollWheelHIDStage.swift"] {
            let text = try source(name)
            #expect(text.contains("tapDisabledByTimeout") && text.contains("tapDisabledByUserInput"), "\(name) re-arms on both")
            #expect(text.contains("CGEvent.tapEnable(tap: port, enable: true)")
                    || text.contains("CGEvent.tapEnable(tap: tap, enable: true)"), "\(name) re-enables the tap")
            #expect(text.contains("enable: false"), "\(name) switches the tap off on stop")
            #expect(text.contains("CFMachPortInvalidate") || text.contains("invalidating: port"), "\(name) hands the port back")
        }
        // The wheel tap and the HID watcher run on the dedicated pointer thread; the glide engine's tap is the one
        // upstream keeps on the main run loop (its state is main-thread state), and nothing else adds a wheel tap.
        #expect(try source("ScrollInverter.swift").contains("PointerTapRunLoop.add(source)"))
        #expect(try source("ScrollWheelHIDStage.swift").contains("PointerTapRunLoop.add(createdSource)"))
        #expect(try source("SmoothScrollService.swift").contains("CFRunLoopAddSource(CFRunLoopGetMain()"))
    }

    @Test func noScrollTapIsPassiveOrCreatedWithoutAnAccessibilityGate() throws {
        for name in ["ScrollInverter.swift", "SmoothScrollService.swift"] {
            let text = try source(name)
            #expect(text.contains("tapShouldRun(") && text.contains("accessibilityGranted"), "\(name) gates the tap on Accessibility")
            #expect(!text.contains("kAXTrustedCheckOptionPrompt"), "\(name) never prompts")
        }
    }
}
