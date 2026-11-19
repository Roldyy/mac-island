import ClaudeLiveKit
import Foundation

/// What the Settings "Claude" section shows and copies. Display only: Mac Island never writes
/// `settings.json`, the user pastes the block himself.
public enum ClaudeHookSetup {
    /// The ClaudeHook executable sits next to the app's own executable in `Contents/MacOS`.
    public static func hookExecutablePath(mainExecutable: URL? = Bundle.main.executableURL) -> String? {
        mainExecutable?.deletingLastPathComponent().appendingPathComponent("ClaudeHook").path
    }

    /// The blocking approval hook sits next to it.
    public static func approveExecutablePath(mainExecutable: URL? = Bundle.main.executableURL) -> String? {
        mainExecutable?.deletingLastPathComponent().appendingPathComponent("ClaudeApprove").path
    }

    public static func approvalSnippet(mainExecutable: URL? = Bundle.main.executableURL) -> String? {
        approveExecutablePath(mainExecutable: mainExecutable).map { ClaudeHooksSnippet.approvalSettingsJSON(executablePath: $0) }
    }

    public static func snippet(mainExecutable: URL? = Bundle.main.executableURL) -> String? {
        hookExecutablePath(mainExecutable: mainExecutable).map { ClaudeHooksSnippet.settingsJSON(executablePath: $0) }
    }
}
