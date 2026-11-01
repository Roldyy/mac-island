import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// "Effacer toutes les autorisations" and "Désinstaller complètement": the plan, with every system touch faked.
@MainActor
@Suite struct AppResetTests {
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }

    struct FakeLogin: LoginItemService {
        let unregistered: Recorder
        var status: LoginItemStatus { .enabled }
        func register() throws {}
        func unregister() throws { unregistered.add("login-off") }
        func openSystemSettings() {}
    }

    func reset(_ log: Recorder, tccOK: Bool = true, recycled: Bool = true, bundle: String = "/Applications/Mac Island.app",
               defaults: UserDefaults) -> AppReset {
        let env = AppReset.Environment(
            run: { tool, args in log.add("run \(tool) \(args.joined(separator: " "))"); return tccOK },
            removeFolder: { log.add("rm \($0.lastPathComponent)") },
            removePreferences: { log.add("prefs \($0)") },
            recycleApp: { url, done in log.add("trash \(url.lastPathComponent)"); done(recycled) },
            terminate: { log.add("quit") })
        return AppReset(bundleID: "be.roldy.macisland", bundleURL: URL(fileURLWithPath: bundle),
                        library: URL(fileURLWithPath: "/tmp/lib"),
                        login: LoginItemModel(service: FakeLogin(unregistered: log), defaults: defaults), environment: env)
    }

    @Test func clearingPermissionsResetsOnlyThisBundleAndTheLoginItem() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let log = Recorder()
        let outcome = reset(log, defaults: bench.defaults).clearPermissions()
        #expect(outcome == .done("Autorisations effacées. macOS les redemandera au moment du besoin."))
        #expect(log.all == ["run /usr/bin/tccutil reset All be.roldy.macisland", "login-off"])
    }

    @Test func aRefusedResetIsReportedNotHidden() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let outcome = reset(Recorder(), tccOK: false, defaults: bench.defaults).clearPermissions()
        guard case .partial = outcome else { Issue.record("\(outcome)"); return }
    }

    @Test func uninstallingClearsThenRemovesThenTrashesThenQuits() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let log = Recorder()
        var result: AppReset.Outcome?
        reset(log, defaults: bench.defaults).uninstallCompletely { result = $0 }
        #expect(result == .done("Mac Island est dans la corbeille. L’app quitte maintenant."))
        let all = log.all
        #expect(all.first == "run /usr/bin/tccutil reset All be.roldy.macisland")
        #expect(all.contains("rm be.roldy.macisland"), "Application Support and Caches share the name")
        #expect(all.contains("rm be.roldy.macisland.savedState"))
        let trash = try? #require(all.firstIndex(of: "trash Mac Island.app"))
        #expect(trash != nil && all.last == "quit" && all.firstIndex(of: "prefs be.roldy.macisland")! < trash!)
        #expect(all.filter { $0 == "prefs be.roldy.macisland" }.count == 2, "again right before quitting")
    }

    @Test func aCopyThatIsNotAnInstalledAppIsNeverTrashedNorQuit() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let log = Recorder()
        var result: AppReset.Outcome?
        reset(log, bundle: "/tmp/build/MacIsland", defaults: bench.defaults).uninstallCompletely { result = $0 }
        guard case .partial = result else { Issue.record("\(String(describing: result))"); return }
        #expect(!log.all.contains { $0.hasPrefix("trash") } && !log.all.contains("quit"))
    }

    @Test func aFailedTrashKeepsTheAppRunning() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let log = Recorder()
        var result: AppReset.Outcome?
        reset(log, recycled: false, defaults: bench.defaults).uninstallCompletely { result = $0 }
        guard case .partial = result else { Issue.record("\(String(describing: result))"); return }
        #expect(!log.all.contains("quit"))
    }

    @Test func theFoldersAreTheAppsOwnAndNothingElse() {
        let folders = AppReset.folders(bundleID: "be.roldy.macisland", library: URL(fileURLWithPath: "/L"))
        #expect(folders.allSatisfy { $0.path.hasPrefix("/L/") && $0.path.contains("be.roldy.macisland") })
    }
}
