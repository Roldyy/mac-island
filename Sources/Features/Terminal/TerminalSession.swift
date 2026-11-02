import AppKit
import Foundation
import SwiftTerm

/// One persistent shell for the whole app. Started lazily on first display, it outlives the island:
/// the host view re-attaches the same `ActivityTerminalView`. If the shell exits, the next display restarts it.
/// Every start wears the active colour profile (the default theme when none is chosen).
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate, TerminalRestarting {
    static let shared = TerminalSession()

    private var terminalView: ActivityTerminalView?
    private var exited = false
    private var shell = TerminalSession.loginShell()

    var hasSession: Bool { terminalView != nil && !exited }
    var lastOutputAt: Date { terminalView?.lastOutputAt ?? .distantPast }
    var shellPid: pid_t { terminalView?.process.shellPid ?? 0 }

    /// Returns the live view, creating or restarting the shell when needed.
    func ensureRunning() -> ActivityTerminalView {
        if let view = terminalView, !exited { return view }
        shell = Self.loginShell()
        return start(directory: NSHomeDirectory())
    }

    private func start(directory: String) -> ActivityTerminalView {
        let view = ActivityTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        view.applySavedFontSize()
        view.configureInteraction()
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        if let profile = TerminalProfileStore.standard().activeProfile { view.applyColorProfile(profile) }
        view.processDelegate = self
        terminalView = view
        exited = false
        view.startProcess(
            executable: shell, args: ["-l"], environment: nil,
            execName: nil, currentDirectory: directory)
        return view
    }

    /// Wipe the scrollback, then send Ctrl+L so the shell clears the screen and redraws its prompt.
    /// Same effect as pressing Ctrl+L: a foreground program receives the keystroke too.
    func clear() {
        guard let view = terminalView, !exited else { return }
        view.clearScreen()
    }

    // MARK: Restart with a colour profile

    func restartDecision() -> TerminalRestartDecision {
        guard let view = terminalView, !exited else {
            return .colorsOnNextStart
        }
        let group = TerminalProcessInfo.foregroundGroup(masterFd: view.process.childfd)
        return TerminalRestartDecision.decide(
            hasSession: true, shellPid: view.process.shellPid, foregroundGroup: group,
            foregroundName: group.flatMap { TerminalProcessInfo.processName($0) })
    }

    /// Ends the running shell and starts the same shell in the same directory, wearing the active profile
    /// (read from the defaults). The caller has already asked the user when a program was running.
    func restartWithActiveProfile() {
        guard let old = terminalView, !exited else { return }  // not running: the next start reads the profile
        let directory = TerminalProcessInfo.usableDirectory(of: old.process.shellPid)
        let hadFocus = old.window?.firstResponder === old
        let host = old.superview
        let frame = old.frame
        let mask = old.autoresizingMask
        let onClick = old.onClick

        old.processDelegate = nil  // its exit must not mark the NEW session as ended
        old.terminate()
        old.removeFromSuperview()

        let view = start(directory: directory)
        view.onClick = onClick
        if let host {
            view.frame = frame
            view.autoresizingMask = mask
            host.addSubview(view)
            if hadFocus { host.window?.makeFirstResponder(view) }
        }
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
        MainActor.assumeIsolated { if source === terminalView { exited = true } }
    }
}
