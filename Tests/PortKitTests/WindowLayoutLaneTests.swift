import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W3B (window layout and maximize): `windowLayout` and `windowMaximizer` bound through `PortFeatureBinding`
/// with a FAKE runtime, so no event tap, hot key, Accessibility call or window is ever touched here. Covers the
/// descriptors and permission table, off by default, the permission gate, start and stop, the kill switch and safe
/// mode, the display watch, shortcut ownership, the two Settings pages, the visibility clamp and the source contract
/// of the taps (read from the files, nothing runs).
@MainActor
@Suite(.serialized) struct WindowLayoutLaneTests {
    static let ids = ["windowLayout", "windowMaximizer"]

    final class FakeRuntime {
        var events: [String] = []
        var handler: (@MainActor () -> Void)?
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: WindowLayoutLane.Runtime {
            WindowLayoutLane.Runtime(
                syncLayout: { [self] in events.append("syncLayout") },
                suspendLayout: { [self] in events.append("suspendLayout") },
                suspendPointerKey: { [self] in events.append("suspendPointer") },
                displaysChanged: { [self] in events.append("displaysChanged") },
                installDisplayWatch: { [self] handler in
                    events.append("watchOn")
                    self.handler = handler
                    return { [self] in
                        events.append("watchOff")
                        self.handler = nil
                    }
                },
                syncMaximizer: { [self] in events.append("syncMaximizer") },
                stopMaximizer: { [self] in events.append("stopMaximizer") })
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
             runtime: WindowLayoutLane.Runtime? = nil) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let fake = FakeRuntime()
        WindowLayoutLane.bind(into: binding, runtime: runtime ?? fake.runtime)
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

    // MARK: Descriptors and permission table

    @Test func theLaneBindsTheTwoFeaturesWithFrenchTextAndAccessibility() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            WindowLayoutLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            for d in binding.descriptors {
                #expect(d.category == .windows, "\(d.id)")
                #expect(d.permissions == [.accessibility], "\(d.id)")
                #expect(d.risk == .touchesInput, "\(d.id)")
                #expect(!d.enabledByDefault, "\(d.id): off unless the migrated switch says on")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id)")
                #expect(!d.title.contains("Window") && !d.title.contains("maximiz"), "French, not English: \(d.title)")
                #expect(MonitoredPermission.used(by: d) == [.accessibility], "\(d.id): a grant restarts it")
            }
        }
    }

    @Test func theLiveLaneBindsTheSameTwoAndIsListedByPortLanes() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            WindowLayoutLane.bind(into: binding)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            #expect(WindowLayoutLane.featureIDs == Self.ids)
            // The foundation lane, four input lanes, shortcuts, mixer, display, energy and this lane; later lanes add theirs.
            #expect(PortLanes.all.count >= 9, "this lane is one line of PortLanes")
        }
    }

    @Test func aSecondBindingOfTheSameFeaturesAddsNothing() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            WindowLayoutLane.bind(into: binding, runtime: FakeRuntime().runtime)
            WindowLayoutLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.ids)
        }
    }

    // MARK: Off by default, permission gate, start

    @Test func everythingIsOffAndNothingRunsUntilTheSwitchesAreOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty)
            for id in Self.ids { #expect(r.registry.state(for: id) == .off, "\(id)") }
        }
    }

    @Test func nothingStartsWithoutAccessibilityAndAGrantStartsBoth() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "switched on, Accessibility missing: no service and no observer touched")
            for id in Self.ids { #expect(r.registry.state(for: id) == .needsPermission(.accessibility), "\(id)") }
            change(r, to: PortPermissionState(accessibility: true))
            #expect(Self.ids.allSatisfy { r.binding.isStarted($0) })
            #expect(r.fake.events.last(where: { $0.hasSuffix("Layout") }) == "syncLayout")
            #expect(r.fake.events.last(where: { $0.hasSuffix("Maximizer") }) == "syncMaximizer")
            #expect(r.fake.handler != nil, "the display watch is up while the layout runs")
        }
    }

    @Test func startIsIdempotentAndNeverAddsASecondDisplayWatch() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let before = r.fake.events
            for id in Self.ids { r.binding.starters[id]!() }
            #expect(r.fake.events == before, "a second start of a running feature reaches nothing")
            #expect(r.fake.count("watchOn") == 1)
        }
    }

    @Test func aStartOrdersTheWatchBeforeTheServiceAndNeverTouchesTheMaximizerForTheLayout() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let layout = r.fake.events.filter { $0 == "watchOn" || $0 == "syncLayout" }
            #expect(layout == ["watchOn", "syncLayout"])
            #expect(r.fake.count("syncMaximizer") == 1 && r.fake.count("syncLayout") == 1)
        }
    }

    // MARK: Stops

    @Test func theKillSwitchStopsEverythingAndLiftingItStartsItAgain() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.count("suspendLayout") == 1, "every hot key, tap and observer of the layout goes down")
            #expect(r.fake.count("suspendPointer") == 1, "so does the pointer key")
            #expect(r.fake.count("stopMaximizer") == 1, "and the green button tap")
            #expect(r.fake.count("watchOff") == 1 && r.fake.handler == nil, "and the display watch")
            for id in Self.ids { #expect(r.registry.state(for: id) == .killed, "\(id)") }
            #expect(!PortShortcutOwnership.isRunning(.windowLayout), "its shortcuts stop being anyone's")
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.count("syncLayout") == 1 && r.fake.count("syncMaximizer") == 1)
            #expect(r.fake.handler != nil)
        }
    }

    @Test func safeModeStopsBoth() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.count("suspendLayout") == 1 && r.fake.count("stopMaximizer") == 1)
            #expect(Self.ids.allSatisfy { !r.binding.isStarted($0) })
        }
    }

    @Test func switchingOneOffLeavesTheOtherRunning() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.switches["windowMaximizer"] = false
            #expect(r.fake.events == ["stopMaximizer"])
            r.registry.switches["windowLayout"] = false
            #expect(r.fake.events == ["stopMaximizer", "watchOff", "suspendLayout", "suspendPointer"])
        }
    }

    @Test func aPermissionRevokeStopsThemAndTheGrantRestartsThem() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            change(r, to: PortPermissionState())
            #expect(r.fake.count("suspendLayout") == 1 && r.fake.count("stopMaximizer") == 1)
            #expect(r.fake.handler == nil)
            r.fake.events.removeAll()
            change(r, to: PortPermissionState(accessibility: true))
            #expect(r.fake.count("syncLayout") == 1 && r.fake.count("syncMaximizer") == 1)
        }
    }

    @Test func aDisplayChangeReachesTheServiceOnlyWhileTheLayoutRuns() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.handler?()
            #expect(r.fake.count("displaysChanged") == 1)
            r.registry.killSwitch = true
            #expect(r.fake.handler == nil, "no observer survives the stop")
        }
    }

    // MARK: Real services, inert

    @Test func theRealServicesStayDownWhilePageTogglesAreOffAndAfterTheKillSwitch() {
        PortHostFixture.isolated { _ in
            // Empty defaults: every page toggle is off, so even with the registry on and Accessibility "granted" the
            // real `syncWithPreferences` arms nothing. No tap, no hot key.
            let r = rig(runtime: .live)
            defer { r.cleanup() }
            #expect(!WindowMaximizer.shared.isRunning)
            #expect(!WindowLayoutService.shared.isGestureRunning)
            r.registry.killSwitch = true
            #expect(!WindowMaximizer.shared.isRunning && !WindowLayoutService.shared.isGestureRunning)
        }
    }

    // MARK: Shortcut ownership

    @Test func theLayoutOwnsItsShortcutsOnlyWhileTheRegistryLetsItRun() {
        PortHostFixture.isolated { _ in
            #expect(!PortShortcutOwnership.isBound(.windowLayout), "nobody bound: nobody owns")
            let r = rig()
            defer { r.cleanup() }
            #expect(PortShortcutOwnership.isBound(.windowLayout) && PortShortcutOwnership.isRunning(.windowLayout))
            #expect(PortShortcutOwnership.isBound(.windowMaximizer))
            r.registry.switches["windowLayout"] = false
            #expect(PortShortcutOwnership.isBound(.windowLayout) && !PortShortcutOwnership.isRunning(.windowLayout))
        }
    }

    @Test func noDefaultShortcutOfTheLayoutCollidesWithAnotherOneOrWithMacIslandsOwn() {
        var seen: [GlobalShortcut: String] = [:]
        for action in WindowLayoutAction.shortcutActions {
            guard let shortcut = action.defaultShortcut else { continue }
            #expect(seen[shortcut] == nil, "\(action.rawValue) shares \(shortcut.displayString) with \(seen[shortcut] ?? "")")
            seen[shortcut] = action.rawValue
        }
        for (name, shortcut) in [("pointer", GlobalShortcut.pointerNextDisplayDefault),
                                 ("directional", GlobalShortcut.windowDirectionalDefault)] {
            #expect(seen[shortcut] == nil, "\(name) key is free among the actions")
        }
        // Mac Island's own global keys: Keep Awake (⌃⌥⌘K), clipboard (⌥⌘V), command bar (⌥Space).
        let ours: [GlobalShortcut] = [.keepAwakeDefault,
                                      GlobalShortcut(keyCode: 9, modifiers: [.option, .command]),
                                      GlobalShortcut(keyCode: 49, modifiers: [.option])]
        for key in ours { #expect(seen[key] == nil, "\(key.displayString) belongs to Mac Island's own module") }
        #expect(!ours.contains(.pointerNextDisplayDefault) && !ours.contains(.windowDirectionalDefault))
    }

    @Test func theActionsThatRegisterAShortcutAreExactlyTheOnesTheCentralPageCanEdit() {
        for action in WindowLayoutAction.allCases where action.supportsShortcut {
            #expect(!action.shortcutKey.isEmpty, "\(action.rawValue)")
        }
        #expect(Set(WindowLayoutAction.shortcutActions.map(\.shortcutKey)).count == WindowLayoutAction.shortcutActions.count,
                "one stored key per action")
        #expect(Set(WindowLayoutAction.shortcutActions.map(\.shortcutID)).count == WindowLayoutAction.shortcutActions.count,
                "one Carbon id per action")
    }

    // MARK: Settings pages

    @Test func twoPagesAreRegisteredAndReplaceTheComingSoonRows() {
        PortHostFixture.isolated { _ in
            SettingsPageBodies.removeAll()
            defer { SettingsPageBodies.removeAll() }
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            let pages = r.binding.pages
            #expect(pages.map(\.pageID) == ["windowlayout", "maximize"])
            #expect(pages.map(\.featureID) == Self.ids)
            for ported in pages {
                let page = SettingsPageCatalog.page(ported.pageID)!
                #expect(page.isComingSoon, "\(ported.pageID): a stub until the body is registered")
                SettingsPageBodies.register(pageID: ported.pageID, featureID: ported.featureID, registry: r.registry,
                                            openPermission: { _ in }, ported.body)
                #expect(!page.isComingSoon, "\(ported.pageID)")
                #expect(SettingsPageModel.blocks(for: page).isEmpty, "\(ported.pageID): no greyed 'Bientôt' row stays")
            }
        }
    }

    @Test func eachPageBodyRendersEvenWhileTheFeatureIsOff() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            for ported in r.binding.pages {
                let host = NSHostingView(rootView: ported.body())
                host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 40, "\(ported.pageID) rendered \(host.fittingSize)")
            }
        }
    }

    // MARK: Visibility clamp

    private let screens = [CGRect(x: 0, y: 70, width: 1440, height: 805),
                           CGRect(x: 1440, y: 0, width: 1920, height: 1055)]

    @Test func aReachableWindowIsLeftWhereItIs() {
        for rect in [CGRect(x: 100, y: 100, width: 800, height: 500),
                     CGRect(x: -300, y: 300, width: 800, height: 500),   // hangs off the left, title bar reachable
                     CGRect(x: 1300, y: 300, width: 800, height: 500)] {  // straddles two displays
            #expect(WindowLayoutVisibility.clamped(rect, toVisibleFrames: screens) == rect, "\(rect)")
        }
    }

    @Test func aWindowOnAnUnpluggedDisplayComesBackOntoAVisibleFrame() {
        let gone = CGRect(x: 4000, y: 200, width: 900, height: 600)
        let back = WindowLayoutVisibility.clamped(gone, toVisibleFrames: screens)
        #expect(back == CGRect(x: 2460, y: 200, width: 900, height: 600), "nearest display, fully inside: \(back)")
        #expect(WindowLayoutVisibility.isReachable(back, in: screens))
        let below = WindowLayoutVisibility.clamped(CGRect(x: 100, y: -2000, width: 800, height: 500), toVisibleFrames: screens)
        #expect(screens[0].contains(below), "\(below)")
    }

    @Test func aTitleBarAboveTheMenuBarIsPulledDown() {
        let tooHigh = CGRect(x: 100, y: 700, width: 800, height: 600)  // top edge 1300 above the 875 visible top
        let fixed = WindowLayoutVisibility.clamped(tooHigh, toVisibleFrames: screens)
        #expect(fixed.maxY <= screens[0].maxY && screens[0].contains(fixed), "\(fixed)")
    }

    @Test func aWindowLargerThanTheDisplayShrinksToFitIt() {
        let huge = CGRect(x: 5000, y: 5000, width: 6000, height: 4000)
        let fixed = WindowLayoutVisibility.clamped(huge, toVisibleFrames: screens)
        #expect(fixed.size.width <= 1920 && fixed.size.height <= 1055)
        #expect(screens.contains { $0.contains(fixed) })
    }

    @Test func aSliverOnAScreenDoesNotCountAsReachable() {
        let sliver = CGRect(x: -790, y: 300, width: 800, height: 500)  // 10 pt visible
        #expect(!WindowLayoutVisibility.isReachable(sliver, in: screens))
        let fixed = WindowLayoutVisibility.clamped(sliver, toVisibleFrames: screens)
        #expect(fixed.minX >= 0 && screens[0].contains(fixed), "\(fixed)")
    }

    @Test func degenerateInputsNeverCrashOrInvent() {
        let rect = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(WindowLayoutVisibility.clamped(rect, toVisibleFrames: []) == rect, "no screen during a display change")
        #expect(WindowLayoutVisibility.clamped(rect, toVisibleFrames: [.zero, .null]) == rect)
        #expect(WindowLayoutVisibility.clamped(.zero, toVisibleFrames: screens) == .zero)
        #expect(!WindowLayoutVisibility.isReachable(rect, in: []))
    }

    // MARK: Source contract (read from the files, nothing runs)

    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/PortKit")

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.sources.appendingPathComponent(path), encoding: .utf8)
    }

    private static let laneFiles = [
        "Services/WindowLayout/WindowLayoutService.swift", "Services/WindowLayout/WindowGestureSupport.swift",
        "Services/WindowLayout/WindowLayoutSupport.swift", "Services/WindowLayout/PointerDisplayService.swift",
        "Services/WindowLayout/WindowLayoutIgnoredApps.swift", "Services/WindowMaximizer.swift",
        "Services/WindowMaximizerSupport.swift", "UI/WindowGestureControls.swift", "UI/WindowVisibilityReader.swift",
        "UI/Settings/WindowLayoutSettings.swift", "UI/Settings/WindowMaximizerExclusionsList.swift",
        "UI/Settings/WindowLayoutIgnoredAppsList.swift", "Bridge/WindowLayout.swift",
    ]

    @Test func everyTapOfTheLaneIsRemovedOnStopAndRearmedWhenTheSystemDisablesIt() throws {
        let layout = try source("Services/WindowLayout/WindowLayoutService.swift")
        #expect(layout.components(separatedBy: "CGEvent.tapCreate(").count - 1 == 4, "directional x2, edge snap, gesture")
        #expect(layout.components(separatedBy: "CFMachPortInvalidate(").count - 1 >= 4, "each tap's port is handed back")
        #expect(layout.components(separatedBy: "tapDisabledByTimeout").count - 1 >= 4, "each tap re-arms on a system disable")
        let maximizer = try source("Services/WindowMaximizer.swift")
        #expect(maximizer.contains("tapDisabledByTimeout") && maximizer.contains("tapDisabledByUserInput"))
        #expect(maximizer.contains("CGEvent.tapEnable(tap: tap, enable: true)"))
        #expect(maximizer.contains("CFMachPortInvalidate(tap)") && maximizer.contains("CFRunLoopRemoveSource("))
        #expect(layout.contains("func suspend()") && layout.contains("stopGestureTap()") && layout.contains("stopEdgeSnapTap()"))
    }

    @Test func everyTapIsGatedOnAccessibilityAndTheRegistryAndNeverBlocksOnAHungApp() throws {
        for name in ["Services/WindowLayout/WindowLayoutService.swift", "Services/WindowMaximizer.swift"] {
            let text = try source(name)
            #expect(text.contains("tapShouldRun(") && text.contains("accessibilityGranted"), "\(name) gates the tap on Accessibility")
            #expect(text.contains("AXIsProcessTrusted()"), "\(name)")
        }
        #expect(try source("Services/WindowLayout/WindowLayoutService.swift").contains("AppFeature.windowLayout.isAvailable"))
        #expect(try source("Services/WindowMaximizer.swift").contains("AppFeature.windowMaximizer.isAvailable"))
        // Every element the lane talks to answers within a bounded time: a hung app cannot freeze the main thread.
        #expect(try source("Services/WindowMaximizer.swift").contains("AXUIElementSetMessagingTimeout(element, 0.35)"))
        #expect(try source("Services/EnhancedUserInterfaceSuspension.swift").contains("AXUIElementSetMessagingTimeout(application, 0.35)"))
    }

    @Test func noFileOfTheLanePromptsForAPermissionOrAlerts() throws {
        let forbidden = ["AXIsProcessTrustedWithOptions", "kAXTrustedCheckOptionPrompt", "CGRequestScreenCaptureAccess",
                         "CGRequestPostEventAccess", "CGRequestListenEventAccess", "NSAlert", "UserDefaults.standard"]
        for name in Self.laneFiles {
            let text = try source(name)
            // The source of this very file names them; the contract is about the lane's own code.
            for token in forbidden where name != "Bridge/WindowLayout.swift" { #expect(!text.contains(token), "\(name): \(token)") }
        }
        let bridge = try source("Bridge/WindowLayout.swift")
        #expect(!bridge.contains("AXIsProcessTrustedWithOptions") && !bridge.contains("Permissions.shared.request"))
    }

    @Test func theLaneOnlyReadsTheSystemsDockAndSpacesPreferences() throws {
        let text = try source("Services/WindowLayout/WindowGestureSupport.swift")
        for suite in ["com.apple.dock", "com.apple.spaces", "com.apple.WindowManager"] {
            #expect(text.contains("UserDefaults(suiteName: \"\(suite)\")"), "\(suite)")
        }
        // Nothing in the lane writes, deletes or syncs a preference of the system or runs a tool to do it.
        for name in Self.laneFiles {
            let body = try source(name)
            for token in ["setPersistentDomain", "removePersistentDomain", "CFPreferencesSetValue", "CFPreferencesSetAppValue",
                          "defaults write", "/usr/bin/defaults", "killall", "Process()"] {
                #expect(!body.contains(token), "\(name): \(token)")
            }
        }
        let suiteLines = text.split(separator: "\n").filter { $0.contains("UserDefaults(suiteName:") }
        #expect(suiteLines.count == 3 && suiteLines.allSatisfy { !$0.contains(".set(") })
    }

    @Test func restoreClampsTheRememberedFrameOntoTheScreensThatExist() throws {
        let text = try source("Services/WindowLayout/WindowLayoutService.swift")
        #expect(text.contains("WindowLayoutVisibility.clamped("), "patch 0751")
        #expect(text.contains("func displaysChanged()"), "patch 0751")
        #expect(text.contains("setFrame(safe, on: target.window, windowKey: target.key)"))
    }
}
