import AppKit
import Foundation
import SwiftTerm

/// One persistent shell for the whole app. Started lazily on first display, it outlives the island:
/// the host view re-attaches the same `ActivityTerminalView`. If the shell exits, the next display restarts it.
/// Every start wears the active colour profile (the default theme when none is chosen).
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate, TerminalRestarting {
    static let shared = TerminalSession()

    /// Builds a configured, not yet started view wearing the profile (nil: the default theme).
    typealias MakeView = @MainActor (_ profile: TerminalColorProfile?) -> ActivityTerminalView
    /// Starts the shell in the view, in that directory.
    typealias StartShell = @MainActor (_ view: ActivityTerminalView, _ directory: String) -> Void

    private var terminalView: ActivityTerminalView?
    private var exited = false
    private let makeView: MakeView
    private let startShell: StartShell
    private let activeProfile: @MainActor () -> TerminalColorProfile?
    private let foregroundGroup: (Int32) -> pid_t?
    private let terminator: ShellTerminating

    /// Everything has the app's behaviour by default; tests swap each piece.
    init(
        makeView: MakeView? = nil,
        startShell: StartShell? = nil,
        activeProfile: (@MainActor () -> TerminalColorProfile?)? = nil,
        foregroundGroup: ((Int32) -> pid_t?)? = nil,
        terminator: ShellTerminating = TerminalShellTerminator()
    ) {
        self.makeView = makeView ?? Self.defaultView
        self.startShell = startShell ?? Self.defaultStart
        self.activeProfile = activeProfile ?? { TerminalProfileStore.standard().activeProfile }
        self.foregroundGroup = foregroundGroup ?? { TerminalProcessInfo.foregroundGroup(masterFd: $0) }
        self.terminator = terminator
        super.init()
    }

    var hasSession: Bool { terminalView != nil && !exited }
    var lastOutputAt: Date { terminalView?.lastOutputAt ?? .distantPast }
    var shellPid: pid_t { terminalView?.process.shellPid ?? 0 }

    static let defaultView: MakeView = { profile in
        let view = ActivityTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        view.applySavedFontSize()
        view.configureInteraction()
        view.nativeBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        if let profile { view.applyColorProfile(profile) }
        return view
    }

    static let defaultStart: StartShell = { view, directory in
        view.startProcess(
            executable: TerminalSession.loginShell(), args: ["-l"], environment: nil,
            execName: nil, currentDirectory: directory)
    }

    /// Returns the live view, creating or restarting the shell when needed.
    func ensureRunning() -> ActivityTerminalView {
        if let view = terminalView, !exited { return view }
        return start(directory: NSHomeDirectory())
    }

    private func start(directory: String) -> ActivityTerminalView {
        let view = makeView(activeProfile())
        view.processDelegate = self
        terminalView = view
        exited = false
        startShell(view, directory)
        NotificationCenter.default.post(name: ClaudeStatusModel.sessionChanged, object: self)
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
        let group = foregroundGroup(view.process.childfd)
        return TerminalRestartDecision.decide(
            hasSession: true, shellPid: view.process.shellPid, foregroundGroup: group,
            foregroundName: group.flatMap { TerminalProcessInfo.processName($0) })
    }

    /// Ends the running shell and starts the same shell in the same directory, wearing the active profile
    /// (read from the defaults). The caller has already asked the user when a program was running.
    func restartWithActiveProfile() {
        guard let old = terminalView, !exited else { return }  // not running: the next start reads the profile
        replaceShell(old, directory: TerminalProcessInfo.usableDirectory(of: old.process.shellPid))
    }

    /// What a reset must ask first: nothing when only the shell is in front, the program's name otherwise.
    /// A session that already ended (or never started) needs no question.
    func resetDecision() -> TerminalRestartDecision { restartDecision() }

    /// A brand new terminal: the shell and its program end, a fresh login shell starts in the home folder with an
    /// empty screen and scrollback. Works when the shell already exited. Does nothing before the first display.
    func resetToFresh() {
        guard let old = terminalView else { return }
        replaceShell(old, directory: NSHomeDirectory())
    }

    private func replaceShell(_ old: ActivityTerminalView, directory: String) {
        let hadFocus = old.window?.firstResponder === old
        let host = old.superview
        let frame = old.frame
        let mask = old.autoresizingMask
        let onClick = old.onClick

        // Read before ending anything: SwiftTerm's terminate() closes the PTY and forgets its descriptor.
        let wasRunning = !exited
        let pid = old.process.shellPid
        let foreground = wasRunning ? foregroundGroup(old.process.childfd) : nil

        old.processDelegate = nil  // its exit must not mark the NEW session as ended
        if wasRunning {
            // SwiftTerm's terminate() alone leaves the shell and its program running (see TerminalShellTerminator):
            // hang up the foreground program and the shell, close the PTY, then wait and reap off the main thread.
            let target = terminator.hangUp(shellPid: pid, foregroundGroup: foreground)
            old.terminate()
            terminator.reap(target)
        }
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
        MainActor.assumeIsolated {
            guard source === terminalView else { return }
            exited = true
            NotificationCenter.default.post(name: ClaudeStatusModel.sessionChanged, object: self)
        }
    }
}
