import ClaudeApproveCore
import ClaudeHookCore
import Darwin
import Foundation
import Observation

/// One permission request Claude Code is waiting on, as the `ClaudeApprove` hook left it. Display data only:
/// the folder name, the tool and ONE shortened line. The hash is of the full request and is what a decision must quote.
public struct ClaudeApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: String          // the nonce
    public let sessionID: String
    public let folderName: String
    public let tool: String
    /// Everything the request would do, on one line (command, path, old and new text, content), cut at `summaryLimit`.
    public let summary: String
    /// False when the line was cut: what Harold reads is then NOT the whole request, so Autoriser is never offered.
    public let summaryComplete: Bool
    public let tier: ApprovalTier
    public let hash: String
    public let startedAt: Date

    /// Whether the island may offer Autoriser: the hook's tier allows it AND the card shows the whole request.
    /// The hook decides again whatever the island sends.
    public var canAllow: Bool { tier == .allow && summaryComplete }
}

public enum ClaudeApprovalSettings {
    public static let enabledKey = "claudeApprovalsEnabled"
    public static let soundKey = "claudeApprovalSound"

    /// Off until Harold switches it on (and pastes the hook block): two keys, like every approval channel.
    public static func isEnabled(_ store: UserDefaults) -> Bool { store.object(forKey: enabledKey) as? Bool ?? false }
    public static func soundOn(_ store: UserDefaults) -> Bool { store.object(forKey: soundKey) as? Bool ?? true }
}

/// Reads the requests the hook writes, tells the hook the island is there (the `alive` heartbeat) and writes the answer.
/// Nothing is kept on disk by this class. While the switch is off it touches nothing and removes the heartbeat, so the
/// hook never waits.
@MainActor
@Observable
public final class ClaudeApprovalStore {
    public static let shared = ClaudeApprovalStore()
    public static let summaryLimit = 240
    static let heartbeatEvery: Duration = .seconds(2)

    public private(set) var requests: [ClaudeApprovalRequest] = []

    /// Fires once for each request the first time it is seen (the sound).
    @ObservationIgnored public var onNewRequest: ((ClaudeApprovalRequest) -> Void)?
    @ObservationIgnored public var isEnabled: () -> Bool = { false }

    @ObservationIgnored private let channel: ApprovalChannel
    @ObservationIgnored private let watcher: any ClaudeFileWatching
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var holders: Set<String> = []

    public init(channel: ApprovalChannel = ApprovalChannel(root: ApprovalChannel.defaultRoot),
                watcher: any ClaudeFileWatching = DispatchFileWatcher(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.channel = channel
        self.watcher = watcher
        self.now = now
    }

    // MARK: lifecycle

    public func acquire(_ holder: String) {
        holders.insert(holder)
        guard loop == nil else { return }
        tick()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatEvery)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    public func release(_ holder: String) {
        holders.remove(holder)
        guard holders.isEmpty else { return }
        loop?.cancel()
        loop = nil
        watcher.stop()
        withdrawHeartbeat()
        requests = []
        seen = []
    }

    /// Heartbeat + rescan. Public for the tests.
    public func tick() {
        guard isEnabled() else {
            withdrawHeartbeat()
            watcher.stop()
            if !requests.isEmpty { requests = [] }
            seen = []
            return
        }
        guard channel.prepare() else { return }
        PrivateFile.write(Data("1".utf8), to: channel.alive)
        watcher.watch([channel.pending.path]) { [weak self] in
            Task { @MainActor [weak self] in self?.rescan() }
        }
        rescan()
    }

    private func withdrawHeartbeat() { _ = unlink(channel.alive.path) }

    // MARK: reading

    public func rescan() {
        guard isEnabled() else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: channel.pending.path)) ?? []
        var found: [ClaudeApprovalRequest] = []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let path = channel.pending.appendingPathComponent(name).path
            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            let age = now().timeIntervalSince1970 - TimeInterval(st.st_mtimespec.tv_sec)
            guard age <= ApprovalLimits.pendingStale else { continue }      // its hook died: not a live question
            guard let data = SafeFileRead.data(atPath: path, maxBytes: ApprovalLimits.maxRecordBytes),
                  let request = Self.parse(data) else { continue }
            found.append(request)
        }
        found.sort { $0.startedAt < $1.startedAt }
        if found != requests { requests = found }
        for request in found where !seen.contains(request.id) {
            seen.insert(request.id)
            onNewRequest?(request)
        }
        seen.formIntersection(Set(found.map(\.id)))
    }

    /// Pure: one pending file in, one request out. Anything that does not look exactly right is dropped.
    nonisolated public static func parse(_ data: Data) -> ClaudeApprovalRequest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["v"] as? Int) == 1,
              let nonce = object["nonce"] as? String, nonce.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              let sid = (object["sid"] as? String).flatMap(ClaudeText.sanitizedID),
              let tierRaw = object["tier"] as? String, let tier = ApprovalTier(rawValue: tierRaw), tier != .refuse,
              let requestText = object["request"] as? String,
              let requestObject = try? JSONSerialization.jsonObject(with: Data(requestText.utf8)) as? [String: Any],
              let tool = requestObject["tool_name"] as? String, !tool.isEmpty,
              let ts = (object["ts"] as? NSNumber)?.doubleValue else { return nil }
        let folder = ClaudeText.folderName(fromCwd: (object["folderName"] as? String) ?? "")
        let line = summarize(tool: tool, input: requestObject["tool_input"])
        return ClaudeApprovalRequest(
            id: nonce, sessionID: sid, folderName: folder, tool: String(tool.prefix(80)),
            summary: line.text, summaryComplete: line.complete,
            tier: tier, hash: ApprovalHash.sha256Hex(requestText),
            startedAt: Date(timeIntervalSince1970: ts / 1000))
    }

    private static let summaryKeyOrder = ["command", "file_path", "notebook_path", "path", "pattern", "old_string", "new_string", "content"]
    private static let summaryLabels = ["pattern": "motif", "old_string": "avant", "new_string": "après", "content": "contenu"]

    /// One line with EVERYTHING the request would do: the command, the path, the old and new text, the content, the
    /// other arguments. Line breaks show as ↵ and other control characters as ·, so nothing hides in the text.
    /// `complete` is false when the line had to be cut: the card then never offers Autoriser.
    /// (Bash: only `command` runs, `description` and `timeout` are not shown.)
    nonisolated static func summarize(tool: String, input: Any?) -> (text: String, complete: Bool) {
        let object = (input as? [String: Any]) ?? [:]
        let keys = summaryKeyOrder.filter { object[$0] != nil } + object.keys.filter { !summaryKeyOrder.contains($0) }.sorted()
        var parts: [String] = []
        for key in keys {
            if tool == "Bash", key != "command" { continue }
            guard let value = object[key] else { continue }
            let raw: String
            if let text = value as? String { raw = text }
            else if JSONSerialization.isValidJSONObject([value]),
                    let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
                    let json = String(data: data, encoding: .utf8) { raw = json }
            else { raw = "\(value)" }
            var shown = ""
            shown.unicodeScalars.append(contentsOf: raw.unicodeScalars.map { scalar -> Unicode.Scalar in
                switch scalar.value {
                case 0x0A, 0x0D: return "↵"
                case 0x09: return " "
                case 0..<0x20, 0x7F: return "·"
                default: return scalar
                }
            })
            let bare = ["command", "file_path", "notebook_path", "path"].contains(key)
            parts.append(bare ? shown : "\(summaryLabels[key] ?? key) : \(shown)")
        }
        let line = parts.joined(separator: "  ·  ").trimmingCharacters(in: .whitespaces)
        guard line.count > summaryLimit else { return (line, true) }
        return (String(line.prefix(summaryLimit)) + "…", false)
    }

    // MARK: answering

    /// Writes the decision. The request leaves the list at once; the hook removes its own file when it answers.
    @discardableResult
    public func decide(_ request: ClaudeApprovalRequest, _ behavior: ApprovalBehavior) -> Bool {
        guard isEnabled(), request.canAllow || behavior == .deny else { return false }
        let wrote = ApprovalDecisionFile.write(behavior: behavior, nonce: request.id, hash: request.hash,
                                               nowMs: Int64(now().timeIntervalSince1970 * 1000), channel: channel)
        if wrote { requests.removeAll { $0.id == request.id } }
        return wrote
    }
}

/// Which app a click on "Ouvrir" brings forward. A fixed list: the raw `entrypoint` value never becomes a bundle id.
public enum ClaudeHostApp {
    public static func bundleID(forEntrypoint entrypoint: String?) -> String? {
        switch entrypoint {
        case "claude-vscode": "com.microsoft.VSCode"
        default: nil   // `cli` runs in a terminal we cannot name, `claude-desktop` is not verified: open the Agents tab instead
        }
    }
}
