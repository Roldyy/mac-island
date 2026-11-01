import AppKit
import Foundation
import IslandKit

/// What "Effacer toutes les autorisations" and "Désinstaller complètement" do. Every system touch goes through
/// `Environment`, so a test checks the plan without running `tccutil` or touching a folder.
@MainActor
public struct AppReset {
    public struct Environment {
        /// Runs a tool; true when it exited 0 within the time allowed.
        public var run: @Sendable (_ tool: String, _ arguments: [String]) -> Bool
        public var removeFolder: @Sendable (URL) -> Void
        public var removePreferences: @Sendable (String) -> Void
        public var recycleApp: @MainActor (URL, @escaping @MainActor (Bool) -> Void) -> Void
        public var terminate: @MainActor () -> Void

        public static let live = Environment(
            run: { tool, arguments in AppReset.runBounded(tool, arguments, seconds: 10) },
            removeFolder: { try? FileManager.default.removeItem(at: $0) },
            removePreferences: { UserDefaults.standard.removePersistentDomain(forName: $0) },
            recycleApp: { url, done in
                NSWorkspace.shared.recycle([url]) { _, error in
                    Task { @MainActor in done(error == nil) }
                }
            },
            terminate: { NSApp.terminate(nil) })
    }

    public enum Outcome: Equatable {
        case done(String)
        case partial(String)
    }

    let bundleID: String
    let bundleURL: URL
    let supportFolders: [URL]
    let login: LoginItemModel
    let environment: Environment

    public init(bundleID: String = AppDefaults.identifier, bundleURL: URL = Bundle.main.bundleURL,
                library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
                login: LoginItemModel, environment: Environment = .live) {
        self.bundleID = bundleID
        self.bundleURL = bundleURL
        self.supportFolders = Self.folders(bundleID: bundleID, library: library)
        self.login = login
        self.environment = environment
    }

    /// The folders this app writes in the user's Library, and nothing else.
    static func folders(bundleID: String, library: URL) -> [URL] {
        [
            "Application Support/\(bundleID)", "Caches/\(bundleID)", "Logs/\(bundleID)", "HTTPStorages/\(bundleID)",
            "Saved Application State/\(bundleID).savedState", "WebKit/\(bundleID)",
        ].map { library.appendingPathComponent($0, isDirectory: true) }
    }

    /// The `tccutil` calls: one `reset All` for this app's own bundle identifier, which cannot touch another app.
    static func tccutilArguments(bundleID: String) -> [String] { ["reset", "All", bundleID] }

    /// Removes every permission macOS granted to this app, and the login item.
    @discardableResult
    public func clearPermissions() -> Outcome {
        let reset = environment.run("/usr/bin/tccutil", Self.tccutilArguments(bundleID: bundleID))
        login.set(false)
        if reset { return .done("Autorisations effacées. macOS les redemandera au moment du besoin.") }
        return .partial("macOS n’a pas accepté de tout effacer. Retirez Mac Island à la main dans Réglages Système, Confidentialité et sécurité.")
    }

    /// Permissions, preferences and support folders, then the app to the Trash, then quit.
    public func uninstallCompletely(finished: @escaping @MainActor (Outcome) -> Void) {
        clearPermissions()
        for folder in supportFolders { environment.removeFolder(folder) }
        environment.removePreferences(bundleID)
        guard bundleURL.pathExtension == "app" else {
            finished(.partial("Réglages et dossiers supprimés. Cette copie n’est pas une app installée : aucun fichier n’a été mis à la corbeille."))
            return
        }
        let terminate = environment.terminate
        let wipe = environment.removePreferences
        let id = bundleID
        environment.recycleApp(bundleURL) { recycled in
            if recycled {
                finished(.done("Mac Island est dans la corbeille. L’app quitte maintenant."))
                wipe(id)  // anything the app wrote while this ran
                terminate()
            } else {
                finished(.partial("Réglages supprimés, mais l’app n’a pas pu être mise à la corbeille : faites-le depuis le Finder."))
            }
        }
    }

    /// `Process` with a deadline: a stuck tool must not hang the window.
    nonisolated static func runBounded(_ tool: String, _ arguments: [String], seconds: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return false }
        if finished.wait(timeout: .now() + seconds) == .timedOut {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }
}
