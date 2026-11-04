import Darwin
import Foundation

/// The one small file a hook leaves per session. No prompt text, no full path.
public struct ClaudeHookRecord: Codable, Equatable, Sendable {
    public var state: String          // working | waiting | idle
    public var folderName: String
    public var updatedAt: Double      // seconds since 1970

    public init(state: String, folderName: String, updatedAt: Double) {
        self.state = state
        self.folderName = folderName
        self.updatedAt = updatedAt
    }
}

public enum ClaudeHookAction: Equatable, Sendable {
    case write(id: String, record: ClaudeHookRecord)
    case delete(id: String)
    case ignore
}

/// Logic behind the `ClaudeHook` executable. Claude Code reads a hook's stdout, so this never prints:
/// `run` returns the bytes for stdout and they are always empty.
public enum ClaudeHookRunner {
    public static let maxInputBytes = 64 * 1024

    /// `MAC_ISLAND_HOOK_DIR` exists for the executable's own test; any process of this user can already
    /// write to the default folder, so it widens nothing.
    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["MAC_ISLAND_HOOK_DIR"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/be.roldy.macisland/claude-hooks", isDirectory: true)
    }

    /// Notification types that need the user (https://code.claude.com/docs/en/hooks, Notification matchers).
    /// idle_prompt is not one of them: it fires about 60 s after Claude finished, which the Stop hook already shows as idle.
    /// Others (auth_success, elicitation_complete, elicitation_response, agent_completed, quota_auto_resume_*,
    /// plugin_notification, anything new) never create "waiting".
    static let waitingNotificationTypes: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// Strict allow-list: a string of 1...40 ASCII lowercase letters or underscores, else nil.
    static func notificationType(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let bytes = text.utf8
        guard (1...40).contains(bytes.count),
              bytes.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F }) else { return nil }
        return text
    }

    /// Pure: hook JSON in, decision out. Only `hook_event_name`, `session_id`, `cwd` and an allow-listed `notification_type` are read;
    /// the prompt (and every other key) is never looked at.
    public static func decide(input: Data, now: Date) -> ClaudeHookAction {
        guard input.count <= maxInputBytes,
              let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let event = object["hook_event_name"] as? String,
              let id = (object["session_id"] as? String).flatMap(ClaudeText.sanitizedID) else { return .ignore }
        let state: String
        switch event {
        case "SessionEnd": return .delete(id: id)
        case "SessionStart", "Stop": state = "idle"
        case "UserPromptSubmit": state = "working"
        case "Notification":
            // Claude Code sends every notification here; only those that need the user mean "waiting".
            // Missing, malformed or unknown type: leave the state alone (fail safe).
            guard let type = notificationType(object["notification_type"]),
                  waitingNotificationTypes.contains(type) else { return .ignore }
            state = "waiting"
        default: return .ignore
        }
        let folder = (object["cwd"] as? String).map(ClaudeText.folderName(fromCwd:)) ?? ""
        return .write(id: id, record: ClaudeHookRecord(state: state, folderName: folder,
                                                       updatedAt: now.timeIntervalSince1970))
    }

    /// Applies the decision on disk. Every failure is swallowed: a hook must never disturb Claude Code.
    @discardableResult
    public static func run(input: Data, directory: URL, now: Date = Date(), uid: uid_t = getuid()) -> Data {
        switch decide(input: input, now: now) {
        case .ignore: break
        case .delete(let id):
            // A symlinked or foreign folder is somebody else's place: never unlink inside it.
            if SafeFileRead.isTrustedDirectory(atPath: directory.path, uid: uid) {
                _ = unlink(directory.appendingPathComponent(id + ".json").path)
            }
        case .write(let id, let record): write(record, id: id, directory: directory, uid: uid)
        }
        return Data()
    }

    /// Reads stdin up to the cap; a longer input is cut and then fails to parse, which means ignore.
    /// The rest is drained so Claude Code never blocks on a full pipe.
    public static func readStandardInput() -> Data {
        SafeFileRead.readCapped(fd: STDIN_FILENO, limit: maxInputBytes, rejectOverflow: false, drainRest: true) ?? Data()
    }

    private static func write(_ record: ClaudeHookRecord, id: String, directory: URL, uid: uid_t) {
        guard let payload = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        guard SafeFileRead.isTrustedDirectory(atPath: directory.path, uid: uid) else { return }
        let final = directory.appendingPathComponent(id + ".json").path
        // pid alone is guessable; O_EXCL would only make a planted name block us, but keep it unique.
        let suffix = String(UInt64.random(in: 0...UInt64.max), radix: 16)
        let temp = directory.appendingPathComponent(".\(id).\(getpid()).\(suffix).tmp").path
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        var ok = true
        payload.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = Darwin.write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n < 0 { if errno == EINTR { continue }; ok = false; break }
                offset += n
            }
        }
        close(fd)
        if !ok || rename(temp, final) != 0 { _ = unlink(temp) }
    }
}
