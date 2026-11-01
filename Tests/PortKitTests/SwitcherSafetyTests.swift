import CoreGraphics
import Foundation
import Testing
@testable import PortKit

/// The WindowServer's symbolic hotkey table as a dictionary (⌘Tab is ids 1 and 2 on a real Mac): what
/// `SystemShortcutTakeover` would flip for real. Nothing here touches SkyLight.
private final class FakeSwitcherHotKeyTable: @unchecked Sendable {
    private let lock = NSLock()
    private var enabledIDs: [Int32: Bool]
    private(set) var writes: [(Int32, Bool)] = []
    private(set) var markerAtWrite: [Set<Int>] = []
    let defaults: UserDefaults

    init(ids: [Int32], defaults: UserDefaults) {
        enabledIDs = Dictionary(uniqueKeysWithValues: ids.map { ($0, true) })
        self.defaults = defaults
    }

    func isEnabled(_ id: Int32) -> Bool { lock.withLock { enabledIDs[id] ?? false } }

    var store: SystemShortcutTakeover.Store {
        SystemShortcutTakeover.Store(
            setEnabled: { [self] id, on in
                lock.withLock {
                    writes.append((id, on))
                    markerAtWrite.append(Set((defaults.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int]) ?? []))
                    enabledIDs[id] = on
                    return .success
                }
            },
            isEnabled: { [self] id in isEnabled(id) },
            liveEntries: { [self] in
                lock.withLock {
                    enabledIDs.map { LiveSystemShortcut(id: $0.key, shortcut: GlobalShortcut(keyCode: 48, modifiers: [.command]),
                                                        enabled: $0.value) }
                }
            })
    }
}

/// Lane W3-A (switcher), safety: the native ⌘Tab takeover is given back on stop, on quit and after a crash; the
/// overlay closes by itself; the probe maps symbols to French reasons; nothing prompts. Fakes only.
@MainActor
@Suite(.serialized) struct SwitcherSafetyTests {
    private static let nativeIDs: Set<Int32> = [1, 2]

    // MARK: Takeover restore (fake store)

    @Test func stopGivesTheNativeShortcutBackAndTheMarkerGoesFirst() {
        PortHostFixture.isolated { defaults in
            let table = FakeSwitcherHotKeyTable(ids: [1, 2], defaults: defaults)
            SystemShortcutTakeover.resetForTests(store: table.store)
            // What `AppSwitcher.applyNativeHotkeySuppression` asks while its tap is live.
            SystemShortcutTakeover.setWanted(Self.nativeIDs, for: SystemShortcutTakeover.switcherSource)
            #expect(!table.isEnabled(1) && !table.isEnabled(2), "macOS's ⌘Tab is off while the switcher runs")
            #expect(table.markerAtWrite.allSatisfy { !$0.isEmpty }, "the crash marker is on disk before each flip")
            #expect(SystemShortcutTakeover.heldIDs == Self.nativeIDs)

            // What `AppSwitcher.restoreNativeHotkeys` (called by suspend, the lane's stop) does.
            SystemShortcutTakeover.setWanted([], for: SystemShortcutTakeover.switcherSource)
            #expect(table.isEnabled(1) && table.isEnabled(2))
            #expect(SystemShortcutTakeover.heldIDs.isEmpty)
            #expect(defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) == nil, "marker cleared once restored")
        }
    }

    @Test func quitGivesItBackThroughRestoreAll() {
        PortHostFixture.isolated { defaults in
            let table = FakeSwitcherHotKeyTable(ids: [1, 2], defaults: defaults)
            SystemShortcutTakeover.resetForTests(store: table.store)
            SystemShortcutTakeover.setWanted(Self.nativeIDs, for: SystemShortcutTakeover.switcherSource)
            SystemShortcutTakeover.restoreAll()   // what SwitcherLane.Runtime.live.quit ends with
            #expect(table.isEnabled(1) && table.isEnabled(2) && SystemShortcutTakeover.heldIDs.isEmpty)
        }
    }

    @Test func aCrashIsRepairedAtTheNextLaunchAndTheLaunchStepIsEntered() {
        PortHostFixture.isolated { defaults in
            let table = FakeSwitcherHotKeyTable(ids: [1, 2], defaults: defaults)
            SystemShortcutTakeover.resetForTests(store: table.store)
            SystemShortcutTakeover.setWanted(Self.nativeIDs, for: SystemShortcutTakeover.switcherSource)
            #expect(!table.isEnabled(1))
            // The process dies here: the table stays as it is, the marker survives in the defaults. The next launch
            // starts with no state in memory and reads the marker.
            #expect(PortBridge.RecoveryPlan(defaults: defaults).systemShortcuts, "PortBridge.recoverAtLaunch enters recovery")
            SystemShortcutTakeover.resetForTests(store: table.store)
            SystemShortcutTakeover.recoverIfNeeded(keeping: [])   // the call in PortBridge.recoverAtLaunch
            #expect(table.isEnabled(1) && table.isEnabled(2), "native ⌘Tab is back before the registry starts anything")
            #expect(defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) == nil)
        }
    }

    @Test func theOldSwitcherMarkerOfVorssaintIsAlsoRepaired() {
        PortHostFixture.isolated { defaults in
            let table = FakeSwitcherHotKeyTable(ids: [1, 2], defaults: defaults)
            _ = table.store.setEnabled?(1, false)
            defaults.set([1], forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
            #expect(PortBridge.RecoveryPlan(defaults: defaults).systemShortcuts)
            SystemShortcutTakeover.resetForTests(store: table.store)
            SystemShortcutTakeover.recoverIfNeeded(keeping: [])
            #expect(table.isEnabled(1))
            #expect(defaults.object(forKey: DefaultsKey.switcherNativeHotkeysSuppressed) == nil)
        }
    }

    @Test func aMissingSystemCallTouchesNothing() {
        PortHostFixture.isolated { defaults in
            SystemShortcutTakeover.resetForTests(store: SystemShortcutTakeover.Store(
                setEnabled: nil, isEnabled: nil, liveEntries: { nil }))
            SystemShortcutTakeover.setWanted(Self.nativeIDs, for: SystemShortcutTakeover.switcherSource)
            #expect(SystemShortcutTakeover.heldIDs.isEmpty, "no private call, nothing taken, nothing to give back")
            #expect(defaults.object(forKey: DefaultsKey.systemShortcutsSuppressed) == nil)
        }
    }

    // MARK: Consent given in this app

    @Test func aMigratedToggleTakesNothingOverUntilItIsTurnedOnHere() {
        PortHostFixture.isolated { defaults in
            #expect(!SwitcherTakeoverConsent.isEffective(toggle: true, defaults: defaults),
                    "Vorssaint's toggle, migrated, is not consent in Mac Island")
            #expect(!SwitcherTakeoverConsent.isEffective(toggle: false, defaults: defaults))
            SwitcherTakeoverConsent.set(true, defaults: defaults)
            #expect(SwitcherTakeoverConsent.isEffective(toggle: true, defaults: defaults))
            #expect(!SwitcherTakeoverConsent.isEffective(toggle: false, defaults: defaults), "toggle off wins")
            SwitcherTakeoverConsent.set(false, defaults: defaults)
            #expect(!SwitcherTakeoverConsent.isEffective(toggle: true, defaults: defaults))
            #expect(defaults.object(forKey: SwitcherTakeoverConsent.key) == nil)
        }
    }

    // MARK: Stuck overlay

    private final class FakeClock {
        private(set) var now: TimeInterval = 0
        private var scheduled: [(id: Int, due: TimeInterval, work: () -> Void)] = []
        private var nextID = 0
        private(set) var delays: [TimeInterval] = []

        var schedule: SwitcherSessionWatchdog.Schedule {
            { [self] delay, work in
                delays.append(delay)
                nextID += 1
                let id = nextID
                scheduled.append((id, now + delay, work))
                return { [self] in scheduled.removeAll { $0.id == id } }
            }
        }

        func advance(by seconds: TimeInterval) {
            now += seconds
            while let next = scheduled.filter({ $0.due <= now }).min(by: { $0.due < $1.due }) {
                scheduled.removeAll { $0.id == next.id }
                next.work()
            }
        }
    }

    @Test func theOverlayClosesAfterThirtySecondsWithoutInput() {
        #expect(SwitcherSessionSafety.idleTimeout == 30)
        let clock = FakeClock()
        let watchdog = SwitcherSessionWatchdog(schedule: clock.schedule)
        var closed = 0
        watchdog.arm { closed += 1 }
        #expect(clock.delays == [30] && watchdog.isArmed)
        clock.advance(by: 29)
        #expect(closed == 0)
        clock.advance(by: 1)
        #expect(closed == 1 && !watchdog.isArmed)
        clock.advance(by: 120)
        #expect(closed == 1, "fires once")
    }

    @Test func inputKeepsTheOverlayOpenAndEndingTheSessionDisarmsIt() {
        let clock = FakeClock()
        let watchdog = SwitcherSessionWatchdog(schedule: clock.schedule)
        var closed = 0
        watchdog.arm { closed += 1 }
        clock.advance(by: 20)
        watchdog.arm { closed += 1 }          // a key arrived: the countdown restarts
        clock.advance(by: 20)
        #expect(closed == 0, "40 s in total but only 20 s idle")
        clock.advance(by: 10)
        #expect(closed == 1)

        watchdog.arm { closed += 1 }
        watchdog.disarm()                      // the session ended normally
        clock.advance(by: 300)
        #expect(closed == 1 && !watchdog.isArmed)
    }

    @Test func anotherAppComingToTheFrontClosesTheSessionButTheSourceAppDoesNot() {
        #expect(SwitcherSessionSafety.shouldCancelOnActivation(activatedPID: 200, sessionFrontPID: 100))
        #expect(!SwitcherSessionSafety.shouldCancelOnActivation(activatedPID: 100, sessionFrontPID: 100))
        #expect(!SwitcherSessionSafety.shouldCancelOnActivation(activatedPID: nil, sessionFrontPID: 100))
    }

    // MARK: Probe

    @Test func everySymbolPresentMeansNothingToReport() {
        let report = SwitcherProbe.evaluate { _ in true }
        #expect(report.findings.isEmpty && !report.blocksStart && report.blockingReason == nil)
    }

    @Test func aMissingWindowMappingBlocksTheStartWithAFrenchReason() {
        let report = SwitcherProbe.evaluate { $0 != "_AXUIElementGetWindow" }
        #expect(report.blocksStart)
        #expect(report.blockingReason?.contains("⌘Tab reste celui de macOS") == true)
        #expect(report.degraded.isEmpty)
    }

    @Test func everyOtherMissingCapabilityOnlyDegradesAndEachHasItsOwnReason() {
        let table: [(symbol: String, capability: SwitcherProbe.Capability)] = [
            ("CGSCopySpacesForWindows", .otherSpaces), ("SLSWindowQueryWindows", .otherSpaces),
            ("CGSHWCaptureWindowList", .thumbnails), ("_SLPSSetFrontProcessWithOptions", .activation),
            ("SLPSPostEventRecordTo", .activation), ("CGSSetSymbolicHotKeyEnabled", .nativeShortcutTakeover),
            ("CGSGetSymbolicHotKeyValue", .nativeShortcutTakeover),
        ]
        for row in table {
            let report = SwitcherProbe.evaluate { $0 != row.symbol }
            #expect(!report.blocksStart, "\(row.symbol)")
            #expect(report.findings.map(\.capability) == [row.capability], "\(row.symbol)")
        }
        let everything = SwitcherProbe.evaluate { _ in false }
        #expect(everything.blocksStart)
        #expect(Set(everything.findings.map(\.reason)).count == SwitcherProbe.Capability.allCases.count)
        for finding in everything.findings {
            #expect(!finding.reason.contains("Window") && !finding.reason.contains("missing"), "French: \(finding.reason)")
        }
    }

    @Test func theLiveProbeDoesALookupOnlyAndNeverThrows() {
        // Whatever this macOS exports, the report is well formed (the lookup is `dlsym`, no private call is made).
        let live = SwitcherProbe.live
        #expect(live.findings.count <= SwitcherProbe.Capability.allCases.count)
        #expect(SpaceWindowBridge.isSymbolAvailable("CGSMainConnectionID") || !live.findings.isEmpty)
        #expect(!SpaceWindowBridge.isSymbolAvailable("MacIslandNoSuchSymbol"))
    }

    // MARK: Source contracts (read from the files, nothing runs)

    private static let switcherFiles: [(path: String, lines: [Substring])] = PortSourceScrubTests.files.filter {
        $0.path.hasPrefix("Services/Switcher/") || $0.path.hasPrefix("UI/Switcher/")
            || ["Services/WindowServerSupport.swift", "Services/WindowServerTrafficLightHitTest.swift",
                "Services/EnhancedUserInterfaceSuspension.swift", "Services/ActivationHandoff.swift",
                "UI/Settings/SwitcherSettings.swift", "UI/Settings/SwitcherAppRulesList.swift",
                "Bridge/Switcher.swift"].contains($0.path)
    }

    private static func isCode(_ line: Substring) -> Bool {
        !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
    }

    @Test func noSwitcherFileCanRaiseAPermissionPrompt() {
        #expect(Self.switcherFiles.count >= 20, "the lane's files are found")
        let forbidden = ["AXIsProcessTrustedWithOptions", "kAXTrustedCheckOptionPrompt", "CGRequestScreenCaptureAccess",
                         "CGRequestListenEventAccess", "CGRequestPostEventAccess", "requestAccessibility(",
                         "requestScreenRecording(", "SCShareableContent.get"]
        var offenders: [String] = []
        for file in Self.switcherFiles {
            for (index, line) in file.lines.enumerated() where Self.isCode(line) {
                if let hit = forbidden.first(where: { line.contains($0) }) { offenders.append("\(file.path):\(index + 1) \(hit)") }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func screenCaptureOnlyRunsBehindTheGrantTheMonitorReports() {
        // ScreenCaptureKit is asked for the window list in ONE file, and both entry points that reach it
        // (a session's refresh and the warm-up) start with the cached Screen Recording flag: without the grant
        // nothing is captured, so nothing can raise the consent prompt.
        var users: [String] = []
        for file in Self.switcherFiles where file.lines.contains(where: { Self.isCode($0) && $0.contains("SCShareableContent") }) {
            users.append(file.path)
        }
        #expect(users == ["Services/Switcher/WindowPreviewProvider.swift"])
        let text = PortSourceScrubTests.files.first { $0.path == users.first }?.lines.joined(separator: "\n") ?? ""
        #expect(text.components(separatedBy: "guard Permissions.shared.screenRecording, Self.screenIsInView()").count - 1 == 2)
        let refresh = text.range(of: "func refreshPreviews(")
        let capture = text.range(of: "SCShareableContent.excludingDesktopWindows")
        let guardRange = text.range(of: "guard Permissions.shared.screenRecording, Self.screenIsInView()")
        #expect(refresh != nil && capture != nil && guardRange != nil
                && guardRange!.lowerBound < capture!.lowerBound, "the guard comes before the first capture")
    }

    private static var appSwitcher: String {
        PortSourceScrubTests.files.first { $0.path == "Services/Switcher/AppSwitcher.swift" }?
            .lines.joined(separator: "\n") ?? ""
    }

    /// The text of one `func` of AppSwitcher, from its signature to the next `func` at the same indent.
    private static func body(of signature: String) -> String {
        let text = appSwitcher
        guard let start = text.range(of: signature) else { return "" }
        let rest = text[start.lowerBound...]
        let end = rest.dropFirst(signature.count).range(of: "\n    func ")
            ?? rest.dropFirst(signature.count).range(of: "\n    private func ")
        return end.map { String(rest[..<$0.lowerBound]) } ?? String(rest.prefix(2000))
    }

    @Test func suspendRestoresTheNativeShortcutAndRemovesTheTap() {
        let suspend = Self.body(of: "func suspend() {")
        #expect(suspend.contains("restoreNativeHotkeys()") && suspend.contains("removeTap()"))
        #expect(suspend.contains("stopObservingKeyboardLayout()") && suspend.contains("stopWarming()"))
        let restore = Self.body(of: "private func restoreNativeHotkeys() {")
        #expect(restore.contains("SystemShortcutTakeover.setWanted([], for: SystemShortcutTakeover.switcherSource)"))
    }

    @Test func theTapPassesEventsThroughWhenTheSystemDisablesItAndReEnablesIt() {
        let route = Self.body(of: "private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {")
        #expect(route.contains("tapDisabledByTimeout") && route.contains("tapDisabledByUserInput"))
        #expect(route.contains("CGEvent.tapEnable(tap: currentTap, enable: true)"), "re-enabled")
        #expect(route.contains("return Unmanaged.passUnretained(event)"), "and the event itself goes through")
        #expect(route.contains("guard canStartSession else { return Unmanaged.passUnretained(event) }"),
                "a stopped switcher answers every key with a pass-through")
        #expect(Self.appSwitcher.contains("DispatchQueue.main.async { [weak self] in self?.restoreNativeHotkeys() }"),
                "no tap, native ⌘Tab back")
    }

    @Test func theOverlayHasEscapeDeactivationAndTimeoutExits() {
        let text = Self.appSwitcher
        #expect(text.contains("case KeyCode.escape:\n            cancelSession()"))
        #expect(Self.body(of: "private func endSession() {").contains("endSessionSafety()"))
        let begin = Self.body(of: "private func beginSessionSafety(frontPID: pid_t) {")
        #expect(begin.contains("armSessionWatchdog()") && begin.contains("didActivateApplicationNotification"))
        #expect(begin.contains("SwitcherSessionSafety.shouldCancelOnActivation"))
        #expect(Self.body(of: "private func armSessionWatchdog() {").contains("cancelSession()"))
        #expect(text.contains("beginSessionSafety(frontPID: reportedFrontPID)"))
        #expect(text.contains("if sessionActive { armSessionWatchdog() }"), "input keeps the session alive")
    }

    @Test func theTakeoverNeedsTheConsentGivenInThisApp() {
        let text = Self.appSwitcher
        #expect(text.contains("SwitcherTakeoverConsent.isEffective("))
        // No remaining direct read of the page toggle that would arm the takeover without the consent.
        let direct = text.components(separatedBy: "\n").filter {
            Self.isCode(Substring($0)) && $0.contains("DefaultsKey.switcherTakeOverSystemShortcuts")
        }
        #expect(direct.count == 2, "only the two reads wrapped in isEffective: \(direct)")
    }

    @Test func everyPrivateSymbolOfTheLaneIsResolvedAtRuntime() {
        // `_AXUIElementGetWindow` used to be linked with @_silgen_name: a macOS without it would not launch.
        for file in Self.switcherFiles {
            for (index, line) in file.lines.enumerated() where Self.isCode(line) {
                #expect(!line.contains("@_silgen_name"), "\(file.path):\(index + 1)")
            }
        }
        let ax = PortSourceScrubTests.files.first { $0.path == "Services/Switcher/AXWindowResolver.swift" }?
            .lines.joined(separator: "\n") ?? ""
        #expect(ax.contains("dlsym(") && ax.contains("static var isAvailable"))
    }
}
