import AppKit
import CommandBarFeature
import CoreGraphics
import IslandKit
import IslandUI
import KeepAwakeFeature
import PortKit
import ShellKit

/// What the quick-access buttons do. A button is never dead: a missing permission opens the matching
/// System Settings pane and puts a short French line in the closed island.
@MainActor
final class SystemActions {
    private static let noticeID = "shell.quickaccess.notice"
    private let closeIsland: @MainActor () -> Void
    private var center: ActivityCenter { ActivityCenter.shared }
    private var capturing = false

    init(closeIsland: @escaping @MainActor () -> Void) {
        self.closeIsland = closeIsland
    }

    // MARK: - Buttons

    func showCommands() {
        closeIsland()
        // Next turn, so the island has given up the keyboard before the bar asks for it.
        DispatchQueue.main.async { CommandBarFeature.show() }
    }

    func toggleKeepAwake() { KeepAwakeFeature.toggle() }

    func lockScreen() {
        closeIsland()
        let outcome = ScreenLockChain.lock(primary: LoginFrameworkScreenLock(), fallback: DisplaySleepScreenLock())
        if outcome == .failed { notice(QuickActionNotice.lockFailed, symbol: "lock.slash", status: .danger) }
    }

    /// The one cleaning mode: the ported feature (`PortCleaningMode`), which the registry switches on and off.
    func cleaning() {
        if PortCleaningMode.isRunning { PortCleaningMode.stop(); return }
        closeIsland()
        switch PortCleaningMode.start() {
        case .started, .alreadyRunning: break  // the countdown is its own activity
        case .featureOff:
            notice(QuickActionNotice.cleaningOff, symbol: "sparkles", status: .info)
        case .needsAccessibility: missing(.accessibility)
        case .refused:
            UserPermissionRequest.request(FeaturePermission.accessibility)
            notice(QuickActionNotice.cleaningRefused, symbol: "exclamationmark.triangle.fill", status: .warning)
        }
    }

    func capture() {
        guard !capturing else { return }
        // Checked, never requested: a request would prompt, and a capture without the permission shows only the wallpaper.
        guard CGPreflightScreenCaptureAccess() else { missing(.screenRecording); return }
        closeIsland()
        capturing = true
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let file = ScreenshotPlan.destination(in: desktop, date: Date()) { FileManager.default.fileExists(atPath: $0.path) }
        Task { @MainActor in
            // Let the closing animation finish so the island is not in the shot.
            try? await Task.sleep(for: .milliseconds(400))
            let ok = await Self.runScreenCapture(file: file)
            capturing = false
            guard FileManager.default.fileExists(atPath: file.path) else {
                // No file and a clean exit = the user pressed Escape: nothing to say.
                if !ok { notice(QuickActionNotice.captureFailed, symbol: "camera.metering.unknown", status: .danger) }
                return
            }
            if let image = NSImage(contentsOf: file) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
            }
            notice(QuickActionNotice.captureDone, symbol: "camera.viewfinder", status: .success)
        }
    }

    // MARK: - Helpers

    /// Opens the pane and tells the user why, in the closed island.
    private func missing(_ permission: FeaturePermission) {
        closeIsland()
        UserPermissionRequest.request(permission)
        notice(QuickActionNotice.permission(permission), symbol: "exclamationmark.triangle.fill", status: .warning)
    }

    private func open(_ url: URL?) { if let url { NSWorkspace.shared.open(url) } }

    private func notice(_ text: String, symbol: String, status: IslandStatus) {
        center.post(IslandActivity(id: Self.noticeID, source: "shell", priority: .alert,
                                   leading: CompactItem(symbol: symbol, text: text, status: status)),
                    expiresAfter: .seconds(4))
    }

    /// False when the tool could not run or exited with an error; Escape exits 0 without a file.
    private nonisolated static func runScreenCapture(file: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/screencapture")
            process.arguments = ScreenshotPlan.arguments(file: file)
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }
}
