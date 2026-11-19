import Foundation

/// The block Harold pastes into `~/.claude/settings.json`. We never write that file ourselves.
public enum ClaudeHooksSnippet {
    /// Exactly the events `ClaudeHookRunner` understands, nothing else.
    public static let events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]

    public static func settingsJSON(executablePath: String) -> String {
        let entry: [String: Any] = ["type": "command", "command": shellQuoted(executablePath)]
        var hooks: [String: Any] = [:]
        for event in events { hooks[event] = [["hooks": [entry]]] }
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: options),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The block of the approval channel: ONE hook, `PermissionRequest`, on the blocking `ClaudeApprove` executable.
    /// 130 s is the hook's own 120 s wait plus a margin; past it Claude Code stops waiting and shows its own dialog.
    /// Separate from `settingsJSON` on purpose: it is optional and Harold pastes it only to use the approvals.
    public static func approvalSettingsJSON(executablePath: String) -> String {
        let entry: [String: Any] = ["type": "command", "command": shellQuoted(executablePath), "timeout": 130]
        let hooks: [String: Any] = ["PermissionRequest": [["hooks": [entry]]]]
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: options),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The command runs through a shell, and an app path often holds a space ("Mac Island.app").
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
