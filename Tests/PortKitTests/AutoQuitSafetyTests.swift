import Foundation
import Testing
@testable import PortKit

/// Lane W3D, the policy half: every rule that keeps an app from being asked to quit, walked with plain values and
/// fakes (a fake workspace, fake Accessibility windows, a fake audio list). Nothing here reads the real system.
@MainActor
@Suite struct AutoQuitSafetyTests {
    // MARK: Fakes

    final class FakeAX: AutoQuitAXReading {
        var windows: [Int32: [AutoQuitAXWindow]] = [:]
        private(set) var calls = 0
        func windows(of pid: Int32) -> [AutoQuitAXWindow] { calls += 1; return windows[pid] ?? [] }
    }

    final class World {
        var ownPID: Int32 = 1
        var ownBundles: Set<String> = ["be.roldy.macisland"]
        var neverQuit: Set<String> = ["com.apple.finder", "com.apple.mobilephone"]
        var frontmost: Int32?
        var regular: Set<Int32> = [10, 11, 12]
        var playing: Set<Int32> = []
        var audioReads = 0
        let ax = FakeAX()

        var gate: AutoQuitGate {
            AutoQuitGate(environment: AutoQuitEnvironment(
                ownPID: { self.ownPID }, ownBundleIDs: { self.ownBundles }, neverQuit: { self.neverQuit },
                frontmostPID: { self.frontmost }, isRegular: { self.regular.contains($0) },
                isPlayingAudio: { self.audioReads += 1; return self.playing.contains($0) }, ax: ax))
        }
    }

    private func veto(pid: Int32 = 10, bundle: String? = "com.vendor.app", regular: Bool = true,
                      path: AutoQuitSafety.Path = .lastWindow, front: Bool = false, audio: Bool = false,
                      panel: Bool = false, never: Set<String> = []) -> AutoQuitVeto? {
        AutoQuitSafety.veto(pid: pid, bundleID: bundle, isRegular: regular, path: path, ownPID: 1,
                            ownBundleIDs: ["be.roldy.macisland"], neverQuit: never,
                            isFrontmost: front, isPlayingAudio: audio, hasOpenPanel: panel)
    }

    // MARK: Identity rules

    @Test func anOrdinaryAppMayBeAskedToQuit() {
        #expect(veto() == nil)
        #expect(veto(path: .inactivity) == nil)
    }

    @Test func macIslandIsNeverQuitByPidOrByBundleId() {
        #expect(veto(pid: 1) == .ownApp)
        #expect(veto(pid: 99, bundle: "be.roldy.macisland") == .ownApp)
        #expect(veto(pid: 99, bundle: "be.roldy.macisland.debug") == nil, "only the exact ids, no prefix guess")
        // A `swift run` build has another bundle id: the running bundle's own id counts too.
        let w = World()
        w.ownBundles = ["test.runner"]
        #expect(w.gate.veto(pid: 10, bundleID: "test.runner", path: .lastWindow) == .ownApp)
    }

    @Test func finderAndTheSystemsOwnUIAreNeverQuitWhateverTheList() {
        #expect(veto(bundle: "com.apple.finder") == .finder)
        for id in AutoQuitSafety.systemBundleIDs { #expect(veto(bundle: id) == .system, "\(id)") }
        for id in ["com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver", "com.apple.Spotlight"] {
            #expect(AutoQuitSafety.systemBundleIDs.contains(id), "\(id)")
        }
    }

    @Test func anAppWithoutABundleIdentifierIsNeverQuit() {
        #expect(veto(bundle: nil) == .noIdentity)
        #expect(veto(bundle: "") == .noIdentity)
    }

    @Test func theNeverQuitListHolds() {
        #expect(veto(bundle: "com.vendor.keep", never: ["com.vendor.keep"]) == .neverQuitList)
        #expect(veto(bundle: "com.vendor.keep.helper", never: ["com.vendor.keep"]) == nil, "exact ids")
    }

    @Test func menuBarAndBackgroundAppsAreNotRegularAndAreKept() {
        #expect(veto(regular: false) == .notRegular)
    }

    // MARK: State rules

    @Test func anAppThatPlaysSoundIsKeptOnBothPaths() {
        #expect(veto(path: .lastWindow, audio: true) == .playingAudio)
        #expect(veto(path: .inactivity, audio: true) == .playingAudio)
    }

    @Test func anAppWithASavePanelOrAnAlertUpIsKeptOnBothPaths() {
        #expect(veto(path: .lastWindow, panel: true) == .openPanel)
        #expect(veto(path: .inactivity, panel: true) == .openPanel)
    }

    @Test func theAppInFrontIsKeptForInactivityButNotAfterItsLastWindowClosed() {
        #expect(veto(path: .inactivity, front: true) == .frontmost)
        // After the red button the app is still the one in front: if that vetoed, the feature would never fire.
        #expect(veto(path: .lastWindow, front: true) == nil)
    }

    @Test func identityRulesWinOverStateRulesAndTheLiveReadsAreLazy() {
        var reads = 0
        let result = AutoQuitSafety.veto(
            pid: 10, bundleID: "com.apple.finder", isRegular: true, path: .lastWindow, ownPID: 1,
            ownBundleIDs: [], neverQuit: [], isFrontmost: { reads += 1; return true }(),
            isPlayingAudio: { reads += 1; return true }(), hasOpenPanel: { reads += 1; return true }())
        #expect(result == .finder)
        #expect(reads == 0, "no audio or Accessibility read when an identity rule already settled it")
    }

    // MARK: Open panels

    @Test func theAccessibilityTreeSaysWhenAPanelIsUp() {
        #expect(!AutoQuitPanelCheck.hasBlockingPanel([]))
        #expect(!AutoQuitPanelCheck.hasBlockingPanel([AutoQuitAXWindow(role: "AXWindow", subrole: "AXStandardWindow")]))
        #expect(AutoQuitPanelCheck.hasBlockingPanel([AutoQuitAXWindow(role: "AXWindow", subrole: "AXDialog")]))
        #expect(AutoQuitPanelCheck.hasBlockingPanel([AutoQuitAXWindow(subrole: "AXSystemDialog")]))
        #expect(AutoQuitPanelCheck.hasBlockingPanel([AutoQuitAXWindow(role: "AXSheet")]))
        #expect(AutoQuitPanelCheck.hasBlockingPanel([AutoQuitAXWindow(role: "AXWindow", hasSheet: true)]))
        #expect(AutoQuitPanelCheck.hasBlockingPanel([AutoQuitAXWindow(role: "AXWindow", isModal: true)]))
        #expect(AutoQuitPanelCheck.hasBlockingPanel([
            AutoQuitAXWindow(role: "AXWindow", subrole: "AXStandardWindow"), AutoQuitAXWindow(role: "AXSheet"),
        ]), "one panel among ordinary windows is enough")
    }

    // MARK: The live gate, against a fake world

    @Test func theGateLetsAnOrdinaryClosedAppQuitAndNothingElse() {
        let w = World()
        w.frontmost = 10
        #expect(w.gate.allowsLastWindowQuit(pid: 10, bundleID: "com.vendor.app"), "in front is fine here")
        #expect(!w.gate.allowsLastWindowQuit(pid: 1, bundleID: "com.vendor.app"), "own pid")
        #expect(!w.gate.allowsLastWindowQuit(pid: 11, bundleID: "com.apple.finder"))
        #expect(!w.gate.allowsLastWindowQuit(pid: 11, bundleID: nil))
        w.neverQuit.insert("com.vendor.keep")
        #expect(!w.gate.allowsLastWindowQuit(pid: 12, bundleID: "com.vendor.keep"))
        w.regular.remove(12)
        #expect(!w.gate.allowsLastWindowQuit(pid: 12, bundleID: "com.vendor.agent"), "menu bar app")
    }

    @Test func theGateKeepsAnAppThatPlaysSound() {
        let w = World()
        w.playing = [10]
        #expect(w.gate.veto(pid: 10, bundleID: "com.vendor.player", path: .lastWindow) == .playingAudio)
        #expect(w.gate.veto(pid: 11, bundleID: "com.vendor.other", path: .lastWindow) == nil)
    }

    @Test func theGateKeepsAnAppWhoseSavePanelIsOpen() {
        let w = World()
        w.ax.windows[10] = [AutoQuitAXWindow(role: "AXWindow", subrole: "AXStandardWindow", hasSheet: true)]
        w.ax.windows[11] = [AutoQuitAXWindow(role: "AXWindow", subrole: "AXDialog")]
        #expect(w.gate.veto(pid: 10, bundleID: "com.vendor.a", path: .lastWindow) == .openPanel)
        #expect(w.gate.veto(pid: 11, bundleID: "com.vendor.b", path: .lastWindow) == .openPanel)
        #expect(w.gate.veto(pid: 12, bundleID: "com.vendor.c", path: .lastWindow) == nil)
    }

    @Test func theGateReadsAudioAndAccessibilityOnlyForAnAppThatPassedTheIdentityRules() {
        let w = World()
        _ = w.gate.veto(pid: 11, bundleID: "com.apple.finder", path: .lastWindow)
        _ = w.gate.veto(pid: 1, bundleID: "be.roldy.macisland", path: .lastWindow)
        #expect(w.audioReads == 0 && w.ax.calls == 0)
        _ = w.gate.veto(pid: 10, bundleID: "com.vendor.app", path: .lastWindow)
        #expect(w.audioReads == 1)
    }

    @Test func theInactivityPathAlsoKeepsTheFrontmostApp() {
        let w = World()
        w.frontmost = 10
        #expect(w.gate.veto(pid: 10, bundleID: "com.vendor.app", path: .inactivity) == .frontmost)
        #expect(w.gate.veto(pid: 11, bundleID: "com.vendor.app", path: .inactivity) == nil)
    }

    // MARK: Source contract (read from the files, nothing runs)

    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/PortKit")

    private func codeLines(_ relative: String) throws -> [String] {
        let text = try String(contentsOf: Self.sources.appendingPathComponent(relative), encoding: .utf8)
        return text.split(separator: "\n").map(String.init).filter {
            !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
        }
    }

    private static let autoQuitFiles = [
        "Bridge/AutoQuit.swift", "Bridge/AutoQuitSafety.swift", "Bridge/AutoQuitIdle.swift",
        "Bridge/AutoQuitPages.swift", "Bridge/AutoQuitSpacesGuard.swift",
        "Services/AutoQuit/AutoQuitService.swift", "Services/AutoQuit/AutoQuitSupport.swift",
        "Services/SpacesOrder/SpacesOrderHold.swift",
    ]

    @Test func nothingInTheAutoQuitCodeCanForceQuitOrKill() throws {
        let banned = ["forceTerminate", "kill(", "SIGKILL", "SIGTERM", "SIGHUP", "killpg", "pkill", "\"/bin/kill\"",
                      "\"/usr/bin/kill\"", "terminateProcess", "NSRunningApplication.forceTerminate"]
        for file in Self.autoQuitFiles {
            for line in try codeLines(file) {
                for token in banned { #expect(!line.contains(token), "\(file): \(token)") }
            }
        }
    }

    @Test func theOnlyThingThatEndsAnAppIsThePoliteTerminate() throws {
        var sites: [String] = []
        for file in Self.autoQuitFiles {
            for line in try codeLines(file) where line.contains("terminate(") && !line.contains("func terminate") {
                sites.append("\(file): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        // The upstream service (behind the gate), the inactivity terminator and its protocol call.
        #expect(sites.count == 3, "\(sites)")
        #expect(sites.contains { $0.hasPrefix("Services/AutoQuit/AutoQuitService.swift") && $0.hasSuffix("app.terminate()") })
        #expect(sites.contains { $0.contains("NSRunningApplication(processIdentifier: pid)?.terminate()") })
    }

    @Test func theUpstreamServiceAsksTheGateRightBeforeItTerminates() throws {
        let lines = try codeLines("Services/AutoQuit/AutoQuitService.swift")
        let gate = try #require(lines.firstIndex { $0.contains("AutoQuitGate.live.allowsLastWindowQuit(app)") })
        let terminate = try #require(lines.firstIndex { $0.contains("app.terminate()") })
        #expect(gate < terminate, "the gate (patch 0850) comes before the only terminate")
        #expect(lines[gate].contains("guard") && lines[gate].contains("else { return }"))
    }

    @Test func noAutoQuitFileCanPromptForAPermission() throws {
        for file in Self.autoQuitFiles {
            for line in try codeLines(file) {
                for banned in PortPromptScrubTests.banned { #expect(!line.contains(banned), "\(file): \(banned)") }
            }
        }
    }

    @Test func noAutoQuitFileAddsAPrivateSymbolSite() throws {
        for file in Self.autoQuitFiles where file.hasPrefix("Bridge/") {
            for line in try codeLines(file) {
                #expect(!line.contains("dlopen(") && !line.contains("dlsym(") && !line.contains("@_silgen_name"),
                        "\(file): a new private-symbol site must be reviewed and listed")
            }
        }
    }
}
