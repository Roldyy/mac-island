import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W7D: the uninstaller bound through a fake runtime and a real `FeatureRegistry`; the path policy, the review
/// gate and the source gates that keep it Trash-only. Nothing here moves a real file to the Trash.
@MainActor
@Suite(.serialized) struct UninstallerLaneTests {
    final class Log {
        var events: [String] = []
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func rig(on: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        UninstallerLane.bind(into: binding, runtime: .init(start: { log.events.append("start") },
                                                           stop: { log.events.append("stop") }))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        if on { registry.switches["uninstaller"] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    @Test func theUninstallerIsANewFeatureOffByDefaultWithItsPage() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["uninstaller"])
        let d = r.registry.descriptor("uninstaller")
        #expect(d?.title.isEmpty == false && d?.summary.isEmpty == false)
        #expect(d?.enabledByDefault == false && d?.risk == .touchesSystem)
        #expect(d?.permissions == [.fullDiskAccess], "no Automation row: the Finder script is gone")
        #expect(r.registry.state(for: "uninstaller") == .off)
        #expect(r.binding.pages.map(\.pageID) == ["uninstaller"] && r.binding.pages.first?.featureID == "uninstaller")
        #expect(SettingsPageCatalog.page("uninstaller") != nil)
        #expect(r.log.events.isEmpty)
    }

    @Test func startAndStopFollowTheSwitchAndTheKillSwitch() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["uninstaller"] = true
        r.registry.switches["uninstaller"] = true
        #expect(r.log.events == ["start"])
        r.registry.killSwitch = true
        #expect(r.log.events == ["start", "stop"])
        #expect(r.binding.availability("uninstaller") == false)
        r.registry.killSwitch = false
        #expect(r.log.events == ["start", "stop", "start"])
    }

    @Test func theLaneIsListedInTheLaunchOrder() throws {
        let lanes = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/PortLanes.swift"),
                               encoding: .utf8)
        #expect(lanes.contains("UninstallerLane.bind(into:)"))
    }
}

// MARK: - Which paths may be removed

@Suite struct UninstallPathPolicyTests {
    static let home = "/Users/me"
    static let roots = UninstallPathPolicy.userRoots(
        home: home, darwinCache: "/private/var/folders/ab/cdef/C", darwinTemp: "/private/var/folders/ab/cdef/T/")

    func removable(_ path: String, app: Bool = false) -> Bool {
        UninstallPathPolicy.isRemovable(path, isAppBundle: app, userRoots: Self.roots)
    }

    @Test func theLeftoversOfAnAppInThePersonsLibraryAreRemovable() {
        for path in ["/Users/me/Library/Application Support/Acme", "/Users/me/Library/Caches/com.acme.app",
                     "/Users/me/Library/Preferences/com.acme.app.plist", "/Users/me/Library/Containers/com.acme.app",
                     "/Users/me/Library/Group Containers/ABCD.acme", "/Users/me/Library/Logs/Acme",
                     "/Users/me/Library/Saved Application State/com.acme.app.savedState",
                     "/Users/me/.config/acme", "/Users/me/.cache/acme", "/Users/me/.local/share/acme",
                     "/private/var/folders/ab/cdef/C/com.acme.app", "/private/var/folders/ab/cdef/T/com.acme.app"] {
            #expect(removable(path), "\(path)")
        }
    }

    @Test func systemFoldersAreNeverRemovableWhateverTheItem() {
        for path in ["/Library/Application Support/Acme", "/Library/LaunchDaemons/com.acme.plist",
                     "/Library/PrivilegedHelperTools/com.acme.helper", "/System/Library/Foo", "/usr/local/bin/acme",
                     "/private/var/db/receipts/com.acme.pkg.plist", "/private/etc/hosts", "/etc/hosts",
                     "/var/db/foo", "/bin/ls", "/sbin/foo", "/opt/homebrew/bin/brew", "/Users/Shared/Library/Acme",
                     "/Users/Shared/Acme", "/Volumes/Backup/Library/Acme", "/", "/Users", "/Applications"] {
            #expect(removable(path) == false, "\(path)")
            #expect(removable(path, app: true) == false || path.hasSuffix(".app"), "\(path)")
        }
    }

    @Test func theHomeFolderItselfAndTheSharedLibraryFoldersAreNeverRemovable() {
        for path in ["/Users/me", "/Users/me/", "/Users/me/Library", "/Users/me/Library/Caches",
                     "/Users/me/Library/Application Support", "/Users/me/Library/Preferences",
                     "/Users/me/Library/Containers", "/Users/me/Library/Group Containers",
                     "/Users/me/Library/Logs", "/Users/me/Library/LaunchAgents", "/Users/me/Applications",
                     "/Users/me/.config", "/Users/me/.cache", "/Users/me/.local", "/Users/me/.local/share",
                     "/private/var/folders/ab/cdef/C", "/private/var/folders/ab/cdef/T"] {
            #expect(removable(path) == false, "\(path)")
        }
    }

    @Test func thePersonalFoldersAndSecretsAreNeverTouchedEvenWhenAnItemIsNamedLikeTheApp() {
        for path in ["/Users/me/Documents/Acme", "/Users/me/Desktop/Acme.app", "/Users/me/Downloads/Acme",
                     "/Users/me/Pictures/Acme", "/Users/me/Movies/Acme", "/Users/me/Music/Acme",
                     "/Users/me/.ssh/id_ed25519", "/Users/me/.gnupg/pubring.kbx", "/Users/me/.Trash/Acme",
                     "/Users/me/Library/Keychains/login.keychain-db", "/Users/me/Library/Mail/V10",
                     "/Users/me/Library/Messages/chat.db", "/Users/me/Library/Mobile Documents/com~apple~CloudDocs",
                     "/Users/me/Library/CloudStorage/Dropbox", "/Users/me/Library/Photos/Libraries"] {
            #expect(removable(path) == false, "\(path)")
        }
    }

    @Test func tricksAreRefusedBeforeAnyFileIsLookedAt() {
        for path in ["Library/Caches/acme", "~/Library/Caches/acme", "/Users/me/Library/Caches/../../../etc/passwd",
                     "/Users/me/Library/Caches/./acme", "/Users/me/Library/Caches/acme\0/x", "", "relative",
                     "/Users/me/../me2/Library/Caches/acme", "/Users/mee/Library/Caches/acme",
                     "/Users/me-other/Library/Caches/acme"] {
            #expect(removable(path) == false, "\(path.debugDescription)")
        }
        // A sibling whose name only starts like the home folder is not inside it.
        #expect(removable("/Users/me2/Library/Caches/acme") == false)
    }

    @Test func anAppBundleMayGoFromAnywhereButTheSystemRoots() {
        for path in ["/Applications/Acme.app", "/Applications/Utilities/Acme.app", "/Users/me/Applications/Acme.app",
                     "/Users/me/Downloads/Acme.app", "/Users/me/Desktop/Acme.app", "/Volumes/Tools/Acme.app"] {
            #expect(removable(path, app: true), "\(path)")
        }
        for path in ["/System/Applications/Safari.app", "/Library/Acme.app", "/usr/local/Acme.app",
                     "/private/var/Acme.app", "/opt/homebrew/Caskroom/acme/1.0/Acme.app", "/bin/Acme.app",
                     "/Applications/Acme", "/Applications/Acme.app/../Other", "/Acme.app", "/.app"] {
            #expect(removable(path, app: true) == false, "\(path)")
        }
        // The same path is refused when it is not the app bundle itself (no `app: true`).
        #expect(removable("/Applications/Acme.app") == false)
    }

    @Test func aRefusalGivesAPlainReasonAndAnAllowedPathGivesNone() {
        let roots = Self.roots
        #expect(UninstallPathPolicy.refusalReason("/Users/me/Library/Caches/acme", isAppBundle: false, userRoots: roots) == nil)
        #expect(UninstallPathPolicy.refusalReason("/Library/Acme", isAppBundle: false, userRoots: roots) == "Dossier système : jamais touché.")
        #expect(UninstallPathPolicy.refusalReason("/Users/Shared/x", isAppBundle: false, userRoots: roots)
                == "Hors de votre espace personnel : jamais touché.")
        #expect(UninstallPathPolicy.refusalReason("../x", isAppBundle: false, userRoots: roots) == "Chemin invalide.")
    }

    @Test func noRootMeansNothingIsRemovableExceptABundle() {
        #expect(UninstallPathPolicy.isRemovable("/Users/me/Library/Caches/acme", isAppBundle: false, userRoots: []) == false)
        #expect(UninstallPathPolicy.isRemovable("/Applications/Acme.app", isAppBundle: true, userRoots: []))
    }
}

// MARK: - Review gate

@Suite struct UninstallReviewGateTests {
    static func plan(_ ids: [UUID]) -> UninstallReviewPlan {
        UninstallReviewPlan(appName: "Acme", rows: ids.enumerated().map {
            .init(id: $1, path: "/Users/me/Library/Caches/acme\($0)", size: Int64(($0 + 1) * 1_000), isAppBundle: $0 == 0)
        })
    }

    @Test func nothingMayRunBeforeAPlanWasShown() {
        var gate = UninstallReviewGate()
        let ids = [UUID(), UUID()]
        #expect(gate.pending == nil)
        let answer1 = gate.confirm(Self.plan(ids), currentSelection: Set(ids))
        #expect(answer1 == false)
    }

    @Test func confirmingTheShownPlanWithTheSameSelectionLetsTheRemovalRunOnce() {
        var gate = UninstallReviewGate()
        let ids = [UUID(), UUID()]
        let plan = Self.plan(ids)
        gate.request(plan)
        #expect(gate.pending == plan)
        let answer2 = gate.confirm(plan, currentSelection: Set(ids))
        #expect(answer2)
        #expect(gate.pending == nil)
        let answer3 = gate.confirm(plan, currentSelection: Set(ids))
        #expect(answer3 == false, "a second confirm finds nothing pending")
    }

    @Test func aDifferentPlanOrAChangedSelectionIsRefusedAndClearsTheReview() {
        var gate = UninstallReviewGate()
        let ids = [UUID(), UUID(), UUID()]
        let shown = Self.plan(ids)
        gate.request(shown)
        let answer4 = gate.confirm(Self.plan(ids), currentSelection: Set(ids))
        #expect(answer4 == false, "another plan with the same rows")
        #expect(gate.pending == nil)

        gate.request(shown)
        let answer5 = gate.confirm(shown, currentSelection: Set(ids.dropLast()))
        #expect(answer5 == false, "a row was unticked meanwhile")
        gate.request(shown)
        let answer6 = gate.confirm(shown, currentSelection: Set(ids + [UUID()]))
        #expect(answer6 == false, "a row was ticked meanwhile")
    }

    @Test func cancelDropsThePlan() {
        var gate = UninstallReviewGate()
        let ids = [UUID()]
        let plan = Self.plan(ids)
        gate.request(plan)
        gate.cancel()
        #expect(gate.pending == nil)
        let answer7 = gate.confirm(plan, currentSelection: Set(ids))
        #expect(answer7 == false)
    }

    @Test func thePlanSumsEveryRowAndKeepsTheFullPaths() {
        let ids = [UUID(), UUID(), UUID()]
        let plan = Self.plan(ids)
        #expect(plan.totalSize == 6_000)
        #expect(plan.rows.map(\.path) == ["/Users/me/Library/Caches/acme0", "/Users/me/Library/Caches/acme1",
                                         "/Users/me/Library/Caches/acme2"])
        #expect(plan.rows.first?.isAppBundle == true && plan.rows.last?.isAppBundle == false)
        #expect(plan.matches(selection: Set(ids)) && !plan.matches(selection: []))
    }

    @Test func theReviewTextsAreFrenchAndPlain() {
        #expect(UninstallReviewText.summary(app: "Acme", count: 1, size: "1 Mo") == "« Acme » : 1 élément, 1 Mo.")
        #expect(UninstallReviewText.summary(app: "Acme", count: 3, size: "3 Mo") == "« Acme » : 3 éléments, 3 Mo.")
        for text in [UninstallReviewText.title, UninstallReviewText.trashOnly, UninstallReviewText.systemNote,
                     UninstallReviewText.cancel, UninstallReviewText.confirm] {
            #expect(!text.isEmpty && !text.localizedCaseInsensitiveContains("bientôt")
                    && !text.localizedCaseInsensitiveContains("bientot"))
        }
    }
}
