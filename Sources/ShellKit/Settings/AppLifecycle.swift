import AppKit
import Foundation

/// The command that starts a fresh copy of the app after this one quits.
public struct RelaunchCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    /// `nil` unless `bundleURL` is an app bundle: a bare `swift run` binary cannot reopen itself.
    ///
    /// It is `open -n <bundle>` run after a one-second wait, so the old copy has let go of the status item
    /// and the shortcuts. The bundle path travels as its own argument, never inside the shell text.
    public static func make(bundleURL: URL) -> RelaunchCommand? {
        guard bundleURL.pathExtension == "app" else { return nil }
        return RelaunchCommand(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 1; exec /usr/bin/open -n \"$1\"", "mac-island-relaunch", bundleURL.path])
    }
}

/// Quit and relaunch, with the side effects injectable.
@MainActor
public enum AppLifecycle {
    public static func quit() { NSApp.terminate(nil) }

    /// Spawns the detached command, then asks the app to quit. Returns false (and does nothing) when the
    /// command cannot be built or started.
    @discardableResult
    public static func relaunch(
        bundleURL: URL = Bundle.main.bundleURL,
        spawn: (RelaunchCommand) -> Bool = AppLifecycle.spawnDetached,
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) -> Bool {
        guard let command = RelaunchCommand.make(bundleURL: bundleURL), spawn(command) else { return false }
        terminate()
        return true
    }

    public static var canRelaunch: Bool { RelaunchCommand.make(bundleURL: Bundle.main.bundleURL) != nil }

    /// The child outlives this process: its output is dropped and nothing waits for it.
    public nonisolated static func spawnDetached(_ command: RelaunchCommand) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
