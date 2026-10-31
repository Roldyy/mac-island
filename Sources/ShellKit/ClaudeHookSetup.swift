import ClaudeLiveKit
import Foundation

/// What the Settings "Claude" section shows and copies. Display only: Mac Island never writes
/// `settings.json`, the user pastes the block himself.
public enum ClaudeHookSetup {
    /// The ClaudeHook executable sits next to the app's own executable in `Contents/MacOS`.
    public static func hookExecutablePath(mainExecutable: URL? = Bundle.main.executableURL) -> String? {
        mainExecutable?.deletingLastPathComponent().appendingPathComponent("ClaudeHook").path
    }

    public static func snippet(mainExecutable: URL? = Bundle.main.executableURL) -> String? {
        hookExecutablePath(mainExecutable: mainExecutable).map { ClaudeHooksSnippet.settingsJSON(executablePath: $0) }
    }
}
