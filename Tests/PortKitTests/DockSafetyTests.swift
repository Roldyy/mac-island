import Foundation
import Testing
@testable import PortKit

/// Lane W3C safety and logic, fakes only: the Dock auto-hide journal and its launch recovery, Dock Preview's
/// permission table, tile resolution on fake Dock trees (the pure pairing the AX reads feed), the click decision
/// table, the exclusions list, and source gates (no prompt API, no blocking call, taps removed and re-armed, panels
/// never activate Mac Island).
@MainActor
@Suite(.serialized) struct DockSafetyTests {
    // MARK: Auto-hide journal

    /// A Dock whose auto-hide preference is a variable, with the hold's two seams on it.
    final class FakeDock {
        var autohide: Bool
        var writes: [Bool] = []
        var failWrites = false
        init(autohide: Bool) { self.autohide = autohide }

        func hold(_ defaults: UserDefaults) -> DockAutohideHold {
            DockAutohideHold(defaults: defaults, readAutohide: { self.autohide }, writeAutohide: { value in
                self.writes.append(value)
                if self.failWrites { return false }
                self.autohide = value
                return true
            })
        }
    }

    @Test func theJournalIsWrittenBeforeTheDockPreferenceChangesAndGoneOnceItIsBack() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(autohide: true)
            var journalAtFirstWrite: Bool?
            let hold = DockAutohideHold(defaults: defaults, readAutohide: { dock.autohide }, writeAutohide: { value in
                journalAtFirstWrite = journalAtFirstWrite ?? defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide)
                dock.autohide = value
                return true
            })
            #expect(hold.begin())
            #expect(journalAtFirstWrite == true, "persisted BEFORE the system preference is touched")
            #expect(dock.autohide == false && hold.isHolding)
            hold.end()
            #expect(dock.autohide == true && !hold.isHolding)
            #expect(defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide) == false)
        }
    }

    @Test func aCrashWhileTheDockIsHeldIsGivenBackAtTheNextLaunch() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(autohide: true)
            let first = dock.hold(defaults)
            #expect(first.begin() && dock.autohide == false)
            // The process dies here: `first` never runs `end()`. The journal is all that is left.
            #expect(defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide))
            dock.writes.removeAll()
            let clean = DockLane.recoverAtLaunch(defaults: defaults, makeHold: { dock.hold($0) })
            #expect(clean && dock.autohide == true, "the Dock hides itself again")
            #expect(dock.writes == [true], "one write, nothing else")
            #expect(defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide) == false)
            // And a second launch has nothing left to do.
            dock.writes.removeAll()
            #expect(DockLane.recoverAtLaunch(defaults: defaults, makeHold: { dock.hold($0) }))
            #expect(dock.writes.isEmpty)
        }
    }

    @Test func withoutAJournalTheLaunchStepNeverBuildsAHoldNorTouchesTheDock() {
        PortHostFixture.isolated { defaults in
            var built = 0
            let clean = DockLane.recoverAtLaunch(defaults: defaults, makeHold: { _ in built += 1; return FakeDock(autohide: false).hold(defaults) })
            #expect(clean && built == 0)
        }
    }

    @Test func aFailedRestoreKeepsTheJournalSoTheNextLaunchTriesAgain() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.dockPreviewRestoreAutohide)
            let dock = FakeDock(autohide: false)
            dock.failWrites = true
            #expect(DockLane.recoverAtLaunch(defaults: defaults, makeHold: { dock.hold($0) }) == false)
            #expect(defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide), "still owed")
            dock.failWrites = false
            #expect(DockLane.recoverAtLaunch(defaults: defaults, makeHold: { dock.hold($0) }))
            #expect(dock.autohide == true && defaults.bool(forKey: DefaultsKey.dockPreviewRestoreAutohide) == false)
        }
    }

    @Test func theHoldNeverStartsWhenADockAlreadyHidesNothingOrAHoldIsOwed() {
        PortHostFixture.isolated { defaults in
            let visible = FakeDock(autohide: false)
            #expect(visible.hold(defaults).begin() == false, "auto-hide is off: nothing to hold")
            #expect(visible.writes.isEmpty)
            defaults.set(true, forKey: DefaultsKey.dockPreviewRestoreAutohide)
            let owed = FakeDock(autohide: true)
            owed.failWrites = true  // the recovery in the initializer fails and keeps the journal
            let hold = owed.hold(defaults)
            #expect(hold.begin() == false, "a hold still owed is never stacked on a second one")
        }
    }

    // MARK: Permission table

    @Test func dockPreviewNeedsAccessibilityAndTheDockButThumbnailsAreOptional() {
        let standard = DockPreviewPreferences.sanitized(orientation: "bottom", autohide: false, tileSize: 64,
                                                     magnification: false, magnifiedTileSize: nil)
        func result(enabled: Bool = true, ax: Bool, sr: Bool, prefs: DockPreviewPreferences? = standard) -> DockPreviewAvailability {
            DockPreviewSupport.availability(enabled: enabled, hasAccessibility: ax, hasScreenRecording: sr, preferences: prefs)
        }
        #expect(result(enabled: false, ax: true, sr: true) == DockPreviewAvailability(canRun: false, blockedReason: nil))
        #expect(result(ax: false, sr: true) == DockPreviewAvailability(canRun: false, blockedReason: .missingAccessibility))
        #expect(result(ax: false, sr: false) == DockPreviewAvailability(canRun: false, blockedReason: .missingAccessibility))
        #expect(result(ax: true, sr: false) == DockPreviewAvailability(canRun: true, blockedReason: nil),
                "no Screen Recording: the cards show the app icon, the panel still opens")
        #expect(result(ax: true, sr: true) == DockPreviewAvailability(canRun: true, blockedReason: nil))
        #expect(result(ax: true, sr: true, prefs: nil) == DockPreviewAvailability(canRun: false, blockedReason: .dockUnavailable))
    }

    @Test func noCaptureWithoutScreenRecordingSoTheIconFallbackNeverAsksTheSystem() throws {
        let provider = try #require(PortSourceScrubTests.files.first { $0.path == "Services/Switcher/WindowPreviewProvider.swift" })
        let gates = provider.lines.filter { $0.contains("guard Permissions.shared.screenRecording") }
        #expect(gates.count >= 2, "both preview entry points check the grant before any capture")
        let panel = try #require(PortSourceScrubTests.files.first { $0.path == "UI/Switcher/DockPreviewPanelView.swift" })
        #expect(panel.lines.contains { $0.contains("} else if let icon = window.appIcon {") }, "a card without a thumbnail draws the icon")
    }

    @Test func theClickDecisionTable() {
        func decide(front: Bool = true, unmin: Bool = true, min: Bool = false, full: Bool = false, mods: Bool = false,
                    minimize: Bool = false, hide: Bool = false, cycle: Bool = false, candidates: Int = 0,
                    owns: Bool = false) -> DockClickAction {
            DockClickSupport.action(appIsFrontmost: front, hasUnminimizedWindows: unmin, hasMinimizedWindows: min,
                                    hasFullscreenWindows: full, hasModifiers: mods, minimizeEnabled: minimize,
                                    hideEnabled: hide, cycleWindowsEnabled: cycle, cycleCandidateCount: candidates,
                                    ownsMinimize: owns)
        }
        #expect(decide() == .passThrough, "every option off: the Dock keeps the click")
        #expect(decide(minimize: true) == .minimize)
        #expect(decide(mods: true, minimize: true) == .passThrough, "a modifier click stays the Dock's")
        #expect(decide(front: false, minimize: true) == .passThrough, "only the active app")
        #expect(decide(hide: true) == .hide)
        #expect(decide(unmin: false, hide: true) == .passThrough, "an app with no window has nothing to hide")
        #expect(decide(full: true, minimize: true) == .passThrough, "never over a full screen window")
        #expect(decide(cycle: true, candidates: 2) == .cycleWindows)
        #expect(decide(cycle: true, candidates: 1) == .passThrough)
        #expect(decide(unmin: false, min: true, minimize: true, owns: true) == .restore)
        #expect(decide(unmin: false, min: true, minimize: true, owns: false) == .passThrough, "never restores what it did not minimize")
    }

    @Test func ourOwnBundleIsNeverTheTargetOfADockClick() {
        for id in ["be.roldy.macisland", "com.vorssaint.utils"] { #expect(DockClickSupport.isOwnBundleIdentifier(id), "\(id)") }
        #expect(!DockClickSupport.isOwnBundleIdentifier("com.apple.finder"))
    }

    // MARK: Tile resolution on fake Dock trees

    private let older = DockAppInstance(pid: 10, launchTime: 100)
    private let newer = DockAppInstance(pid: 11, launchTime: 200)

    private func pid(of tile: String, in pairings: [DockTilePairing<String>]) -> pid_t? {
        pairings.first { $0.tile == tile }?.pid
    }

    @Test func twoTilesOfOneBundlePairWithTheirInstancesInLaunchOrder() {
        let pairs = DockClickSupport.pairTiles(["tileA", "tileB"], instances: [newer, older], previous: [])
        #expect(pid(of: "tileA", in: pairs) == 10 && pid(of: "tileB", in: pairs) == 11)
    }

    @Test func aDraggedTileKeepsItsProcess() {
        let first = DockClickSupport.pairTiles(["tileA", "tileB"], instances: [older, newer], previous: [])
        // The user drags the second tile in front: the Dock list now reads in the other order.
        let after = DockClickSupport.pairTiles(["tileB", "tileA"], instances: [older, newer], previous: first)
        #expect(pid(of: "tileA", in: after) == 10 && pid(of: "tileB", in: after) == 11)
    }

    @Test func aPidTheSystemHandsToAnotherInstanceDoesNotInheritTheTile() {
        let first = DockClickSupport.pairTiles(["tileA"], instances: [older], previous: [])
        let reused = DockAppInstance(pid: 10, launchTime: 999)
        #expect(pid(of: "tileA", in: DockClickSupport.pairTiles(["tileA"], instances: [reused], previous: first)) == 10,
                "paired afresh by order, not carried over")
        let other = DockAppInstance(pid: 12, launchTime: 300)
        let none = DockClickSupport.pairTiles(["tileA", "tileB"], instances: [reused, other], previous: first, complete: false)
        #expect(none.isEmpty, "the old pairing is dropped and an incomplete list pairs nothing new")
    }

    @Test func anIncompleteOrUnevenTileListPairsNothingNew() {
        #expect(DockClickSupport.pairTiles(["tileA", "tileB"], instances: [older, newer], previous: [], complete: false).isEmpty)
        #expect(DockClickSupport.pairTiles(["tileA"], instances: [older, newer], previous: []).isEmpty,
                "a tile still launching: the click is left to the Dock")
        #expect(!DockClickSupport.canPairByOrder(tileCount: 2, instanceCount: 1, complete: true))
        #expect(DockClickSupport.canPairByOrder(tileCount: 2, instanceCount: 2, complete: true))
    }

    @Test func aKeptTileOfAQuitInstanceIsPassedOverOnlyWhenAnotherTileRuns() {
        var asked = 0
        #expect(DockClickSupport.soleInstanceIsBehindTile(tileReadsRunning: true, anotherTileReadsRunning: { asked += 1; return true }))
        #expect(asked == 0, "the ordinary click pays no second read")
        #expect(DockClickSupport.soleInstanceIsBehindTile(tileReadsRunning: false, anotherTileReadsRunning: { false }),
                "nothing places the instance elsewhere: the tile keeps it")
        #expect(!DockClickSupport.soleInstanceIsBehindTile(tileReadsRunning: false, anotherTileReadsRunning: { true }))
    }

    @Test func theKernelStartTimeComesBeforeTheLaunchDate() {
        let date = Date(timeIntervalSinceReferenceDate: 500)
        #expect(DockClickSupport.launchTime(processStartMicroseconds: nil, launchDate: date) == 500)
        #expect(DockClickSupport.launchTime(processStartMicroseconds: nil, launchDate: nil) == nil)
        let kernel = DockClickSupport.launchTime(processStartMicroseconds: 1_000_000, launchDate: date)
        #expect(kernel == Date(timeIntervalSince1970: 1).timeIntervalSinceReferenceDate)
    }

    // MARK: Exclusions

    @Test func theExclusionListIsOneKeyOfBundleIdsWithoutBlanksOrDuplicates() {
        #expect(DefaultsKey.windowPreviewExcludedApps == "windowPreviewExcludedApps")
        #expect(Defaults.sanitizedBundleIdentifierList([" com.apple.finder ", "com.apple.finder", "", "  ", "com.apple.Safari"])
                == ["com.apple.finder", "com.apple.Safari"])
        PortHostFixture.isolated { defaults in
            #expect((defaults.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? []).isEmpty,
                    "nothing is excluded until the user adds an app")
        }
    }

    // MARK: Source gates

    private static let dockFiles = [
        "Services/DockClick/DockClickService.swift", "Services/DockClick/DockClickSupport.swift",
        "Services/DockPreview/DockPreviewService.swift", "Services/DockPreview/DockPreviewSupport.swift",
        "Services/DockPreview/DockAutohideHold.swift", "Services/DockPreview/DockPreviewDragGhost.swift",
        "Services/DockPreview/DockPreviewFrameRestoration.swift", "Services/DockTileResolver.swift",
        "UI/Settings/DockSettings.swift", "UI/Settings/WindowPreviewExclusionsList.swift",
        "UI/Switcher/DockPreviewPanelView.swift", "Bridge/Dock.swift",
    ]

    private static func code(_ path: String) -> [Substring] {
        (PortSourceScrubTests.files.first { $0.path == path }?.lines ?? []).filter {
            !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
        }
    }

    /// The body of `func <name>`: from its line to the next member at the same indent.
    private static func body(of name: String, in path: String) -> String {
        let lines = PortSourceScrubTests.files.first { $0.path == path }?.lines ?? []
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else { return "" }
        let indent = lines[start].prefix { $0 == " " }.count
        var end = start + 1
        while end < lines.count {
            let line = lines[end]
            let lead = line.prefix { $0 == " " }.count
            if !line.isEmpty, lead <= indent, !line.drop(while: { $0 == " " }).hasPrefix("}") { break }
            end += 1
        }
        return lines[start..<end].joined(separator: "\n")
    }

    @Test func theDockFilesAreAllThere() {
        for path in Self.dockFiles { #expect(!Self.code(path).isEmpty, "\(path)") }
    }

    @Test func noDockFileCanRaiseASystemPermissionPrompt() {
        let banned = ["AXIsProcessTrustedWithOptions", "AXTrustedCheckOptionPrompt", "CGRequestScreenCaptureAccess",
                      "CGRequestListenEventAccess", "SCShareableContent", "requestAccess(", "requestFullAccess"]
        for path in Self.dockFiles {
            for line in Self.code(path) {
                for api in banned where line.contains(api) { Issue.record("\(path) calls \(api)") }
            }
        }
    }

    @Test func noDockFileBlocksTheMainThreadAndEveryAXReadHasATimeout() {
        let blocking = ["sleep(", "usleep(", ".wait(", "DispatchSemaphore", "waitUntilExit", "Thread.sleep"]
        for path in Self.dockFiles {
            for line in Self.code(path) {
                for call in blocking where line.contains(call) { Issue.record("\(path) blocks with \(call)") }
            }
        }
        #expect(DockPreviewSupport.dockHitTimeout <= 0.5, "the hover hit test on the Dock gives up quickly")
        let preview = Self.code("Services/DockPreview/DockPreviewService.swift").joined(separator: "\n")
        #expect(preview.contains("AXUIElementSetMessagingTimeout(dock, DockPreviewSupport.dockHitTimeout)"))
        let click = Self.code("Services/DockClick/DockClickService.swift").joined(separator: "\n")
        #expect(click.contains("AXUIElementSetMessagingTimeout(app, 0.35)") && click.contains("AXUIElementSetMessagingTimeout(dockElement, 0.35)"))
        for path in Self.dockFiles {
            #expect(!Self.code(path).joined(separator: "\n").contains("SetMessagingTimeout(AXUIElementCreateSystemWide()"),
                    "\(path): a timeout on the system-wide element would cut every other AX read of the app")
        }
    }

    @Test func bothTapsAreRemovedOnStopAndRearmedWhenTheSystemDisablesThem() {
        for (path, stop) in [("Services/DockPreview/DockPreviewService.swift", "stopTap"),
                             ("Services/DockClick/DockClickService.swift", "stop")] {
            let body = Self.body(of: stop, in: path)
            #expect(body.contains("CGEvent.tapEnable(tap: tap, enable: false)"), "\(path) disables the tap")
            #expect(body.contains("CFRunLoopRemoveSource"), "\(path) removes the run loop source")
            #expect(body.contains("CFMachPortInvalidate(tap)"), "\(path) invalidates the port")
            #expect(body.contains("tap = nil"), "\(path) forgets the tap")
            let handle = Self.body(of: "handle", in: path)
            #expect(handle.contains("tapDisabledByTimeout") && handle.contains("tapDisabledByUserInput"), "\(path)")
            #expect(handle.contains("CGEvent.tapEnable(tap: tap, enable: true)") || handle.contains("syncWithPreferences"),
                    "\(path) re-arms or re-syncs when the system disables the tap")
        }
        // The preview's listen-only mouse tap passes every event through; the click tap is the only active one.
        let preview = Self.code("Services/DockPreview/DockPreviewService.swift").joined(separator: "\n")
        #expect(preview.contains("options: .listenOnly"))
    }

    @Test func stoppingThePreviewEndsTheSessionWhichHandsAHeldDockBack() {
        let stop = Self.body(of: "stop", in: "Services/DockPreview/DockPreviewService.swift")
        #expect(stop.contains("stopTap()") && stop.contains("endSession()") && stop.contains("closeAllPinnedPanels()"))
        let end = Self.body(of: "endSession", in: "Services/DockPreview/DockPreviewService.swift")
        #expect(end.contains("releaseDockAutohideHold()"))
        let release = Self.body(of: "releaseDockAutohideHold", in: "Services/DockPreview/DockPreviewService.swift")
        #expect(release.contains("dockAutohideHold.end()"))
        // The hold is opt-in: only the "keep the Dock visible" option starts it.
        let begin = Self.body(of: "beginSession", in: "Services/DockPreview/DockPreviewService.swift")
        #expect(begin.contains("DefaultsKey.dockPreviewKeepDockVisible") && begin.contains("beginDockAutohideHold()"))
    }

    @Test func thePreviewPanelsNeverActivateMacIsland() {
        let service = Self.code("Services/DockPreview/DockPreviewService.swift").joined(separator: "\n")
        #expect(service.components(separatedBy: ".nonactivatingPanel").count - 1 >= 2, "session panel and pinned panels")
        for path in Self.dockFiles {
            let text = Self.code(path).joined(separator: "\n")
            for call in ["NSApp.activate", "NSApplication.shared.activate", "activate(ignoringOtherApps"] {
                #expect(!text.contains(call), "\(path) activates the app with \(call)")
            }
        }
        // Panels are ordered front without becoming key.
        #expect(service.contains("orderFrontRegardless()"))
    }

    @Test func dockSettingsOnlyChangesPreferencesAndSyncsTheServices() {
        // The page toggles reach the services through syncWithPreferences, which re-reads the registry verdict:
        // with the dock off no page toggle can arm a tap.
        let page = Self.code("UI/Settings/DockSettings.swift").joined(separator: "\n")
        #expect(page.contains("DockPreviewService.shared.syncWithPreferences()"))
        #expect(page.contains("DockClickService.shared.syncWithPreferences()"))
        let preview = Self.body(of: "syncWithPreferences", in: "Services/DockPreview/DockPreviewService.swift")
        #expect(preview.contains("AppFeature.dockPreview.isAvailable"))
        let click = Self.body(of: "syncWithPreferences", in: "Services/DockClick/DockClickService.swift")
        #expect(click.contains("AppFeature.dockClick.isAvailable") && click.contains("AXIsProcessTrusted()"))
    }
}
