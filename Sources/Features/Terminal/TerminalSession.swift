import AppKit
import Foundation
import SwiftTerm

/// One persistent shell for the whole app. Started lazily on first display, it outlives the island:
/// the host view re-attaches the same `ActivityTerminalView`. If the shell exits, the next display restarts it.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    static let shared = TerminalSession()

    private var terminalView: ActivityTerminalView?
    private var exited = false

    var hasSession: Bool { terminalView != nil && !exited }
    var lastOutputAt: Date { terminalView?.lastOutputAt ?? .distantPast }
    var shellPid: pid_t { terminalView?.process.shellPid ?? 0 }

    /// Returns the live view, creating or restarting the shell when needed.
    func ensureRunning() -> ActivityTerminalView {
        if let view = terminalView, !exited { return view }
        let view = ActivityTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        view.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        view.processDelegate = self
        terminalView = view
        exited = false
        let shell = Self.loginShell()
        view.startProcess(
            executable: shell, args: ["-l"], environment: nil,
            execName: nil, currentDirectory: NSHomeDirectory())
        return view
    }

    static func loginShell() -> String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    // MARK: LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated { exited = true }
    }
}
