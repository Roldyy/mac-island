import ClaudeHookCore
import CryptoKit
import Darwin
import Foundation

/// The folder both sides share: the hook writes `pending/`, the island writes `decisions/` and touches `alive`.
/// Every file is owner-only (0600) in a 0700 folder; nothing here holds a path of the chat, only its folder name.
public struct ApprovalChannel: Equatable, Sendable {
    public let root: URL
    public var pending: URL { root.appendingPathComponent("pending", isDirectory: true) }
    public var decisions: URL { root.appendingPathComponent("decisions", isDirectory: true) }
    public var alive: URL { root.appendingPathComponent("alive") }

    public init(root: URL) { self.root = root }

    /// `MAC_ISLAND_APPROVAL_DIR` exists for the executable's own test; any process of this user can already write
    /// to the default folder, so it widens nothing.
    public static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["MAC_ISLAND_APPROVAL_DIR"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/be.roldy.macisland/claude-approvals", isDirectory: true)
    }

    /// Creates the three folders (0700). False when the root is not a real directory of ours.
    @discardableResult
    public func prepare(uid: uid_t = getuid()) -> Bool {
        for dir in [root, pending, decisions] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            guard SafeFileRead.isTrustedDirectory(atPath: dir.path, uid: uid) else { return false }
        }
        return true
    }

    /// True while the island shows it is running: `alive` is a plain file of ours touched less than `seconds` ago.
    public func isAlive(now: Date = Date(), within seconds: TimeInterval = ApprovalLimits.heartbeatFresh, uid: uid_t = getuid()) -> Bool {
        var st = stat()
        guard lstat(alive.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == uid, st.st_nlink == 1 else { return false }
        let age = now.timeIntervalSince1970 - TimeInterval(st.st_mtimespec.tv_sec)
        return age <= seconds && age >= -5
    }
}

public enum ApprovalLimits {
    /// How old the island's heartbeat may be before the hook stops waiting (the island touches it every 2 s).
    public static let heartbeatFresh: TimeInterval = 8
    /// How old a decision may be when the hook reads it.
    public static let decisionMaxAgeMs: Int64 = 15_000
    /// A request bigger than this is never shown (the island reads at most 64 KiB).
    public static let maxRequestBytes = 60_000
    /// The whole pending file (the request is escaped a second time inside it). The hook refuses to write a bigger one
    /// and the island reads exactly this much, so a request the island could not read is never waited for.
    public static let maxRecordBytes = 65_536
    public static let maxInputBytes = 1_048_576
    /// A pending file whose last touch is older than this belongs to a hook that died.
    public static let pendingStale: TimeInterval = 8
}

public enum ApprovalBehavior: String, Sendable, Equatable { case allow, deny }

public enum ApprovalRejection: String, Error, Sendable, Equatable {
    case notOurFile = "decision not a file of ours"
    case badMode = "decision mode is not 600"
    case notJSON = "decision is not json"
    case badNonce = "bad nonce"
    case badHash = "bad hash"
    case badBehavior = "bad behavior"
    case badTimestamp = "bad ts"
    case stale = "stale decision"
    case olderThanRequest = "decision older than the request"
    case allowRefusedByTier = "allow refused by the tier"
}

/// The island's answer to ONE request. Valid only for the nonce and the hash of the request the hook is holding.
public enum ApprovalDecisionFile {
    public static func validate(path: String, nonce: String, hash: String, tier: ApprovalTier, startMs: Int64, nowMs: Int64,
                                uid: uid_t = getuid()) -> Result<ApprovalBehavior, ApprovalRejection> {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == uid, st.st_nlink == 1 else {
            return .failure(.notOurFile)
        }
        guard (st.st_mode & 0o777) == 0o600 else { return .failure(.badMode) }
        guard let data = SafeFileRead.data(atPath: path, maxBytes: 4096, uid: uid),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.notJSON) }
        guard (object["nonce"] as? String) == nonce else { return .failure(.badNonce) }
        guard (object["hash"] as? String) == hash else { return .failure(.badHash) }
        guard let raw = object["behavior"] as? String, let behavior = ApprovalBehavior(rawValue: raw) else { return .failure(.badBehavior) }
        guard let ts = (object["ts"] as? NSNumber)?.int64Value, (object["ts"] as? Bool) == nil else { return .failure(.badTimestamp) }
        let age = nowMs - ts
        guard age <= ApprovalLimits.decisionMaxAgeMs, age >= -5000 else { return .failure(.stale) }
        guard ts >= startMs - 5000 else { return .failure(.olderThanRequest) }
        if behavior == .allow && tier != .allow { return .failure(.allowRefusedByTier) }
        return .success(behavior)
    }

    /// What the island writes: a 0600 file renamed into place. Never overwrites a file it does not own.
    @discardableResult
    public static func write(behavior: ApprovalBehavior, nonce: String, hash: String, nowMs: Int64, channel: ApprovalChannel) -> Bool {
        guard nonce.range(of: #"^[0-9a-f]{32}$"#, options: .regularExpression) != nil,
              let data = try? JSONSerialization.data(withJSONObject: [
                  "nonce": nonce, "hash": hash, "behavior": behavior.rawValue, "ts": nowMs,
              ] as [String: Any], options: [.sortedKeys]) else { return false }
        return PrivateFile.write(data, to: channel.decisions.appendingPathComponent(nonce + ".json"))
    }
}

/// Atomic owner-only write: temp file (O_EXCL, O_NOFOLLOW, 0600) then rename.
public enum PrivateFile {
    @discardableResult
    public static func write(_ data: Data, to final: URL) -> Bool {
        let dir = final.deletingLastPathComponent()
        let suffix = String(UInt64.random(in: 0...UInt64.max), radix: 16)
        let temp = dir.appendingPathComponent(".\(final.lastPathComponent).\(getpid()).\(suffix).tmp").path
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        var ok = true
        data.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = Darwin.write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n < 0 { if errno == EINTR { continue }; ok = false; break }
                offset += n
            }
        }
        close(fd)
        if !ok || rename(temp, final.path) != 0 { _ = unlink(temp); return false }
        return true
    }
}

public enum ApprovalHash {
    public static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
