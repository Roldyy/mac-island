import ClaudeHookCore
import Darwin
import Foundation

/// Logic behind the `ClaudeApprove` executable (Claude Code `PermissionRequest` hook).
///
/// 1. write `pending/<session>.<nonce>.json` (0600) with the request, keep its sha256 IN MEMORY
/// 2. wait for `decisions/<nonce>.json`, written by the island when Harold clicks Autoriser or Refuser
/// 3. print the allow/deny answer only if the decision matches OUR hash, is fresh, owned by us, mode 600, not a link,
///    and (for an allow) the hook's own tier says allow. Anything else: print NOTHING, the native dialog decides as usual.
/// Every error path returns empty output. Never prints `updatedInput` or `updatedPermissions`. No island, no wait, no delay.
public enum ApprovalHookRunner {
    public struct Config: Sendable {
        public var waitSeconds: TimeInterval = 120
        public var tick: TimeInterval = 0.5
        public var heartbeatFresh: TimeInterval = ApprovalLimits.heartbeatFresh
        public init() {}
    }

    static let allowOutput = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
    static let denyOutput = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Refusé depuis Mac Island"}}}"#

    public static func readStandardInput() -> Data {
        SafeFileRead.readCapped(fd: STDIN_FILENO, limit: ApprovalLimits.maxInputBytes, rejectOverflow: false, drainRest: true) ?? Data()
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// The request as the island shows it: tool name and input, keys sorted, compact. The hash covers exactly this string.
    static func canonicalRequest(toolName: String, toolInput: Any?) -> String? {
        let object: [String: Any] = ["tool_name": toolName, "tool_input": (toolInput as? [String: Any]) ?? [:]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns the bytes for stdout: an allow/deny answer, or empty.
    @discardableResult
    public static func run(input: Data, channel: ApprovalChannel, home: String = NSHomeDirectory(), config: Config = Config(),
                           uid: uid_t = getuid(), cancelled: () -> Bool = { false }) -> Data {
        guard input.count <= ApprovalLimits.maxInputBytes,
              channel.isAlive(within: config.heartbeatFresh, uid: uid),
              let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              (object["hook_event_name"] as? String) == "PermissionRequest",
              let sid = (object["session_id"] as? String).flatMap(ClaudeText.sanitizedID),
              let tool = object["tool_name"] as? String else { return Data() }

        let context = ApprovalContext.resolve(toolName: tool, toolInput: object["tool_input"], cwd: object["cwd"] as? String, home: home)
        let verdict = ApprovalClassifier.classify(toolName: tool, toolInput: object["tool_input"], context: context)
        guard verdict.tier != .refuse else { return Data() }

        guard let request = canonicalRequest(toolName: tool, toolInput: object["tool_input"]),
              request.utf8.count <= ApprovalLimits.maxRequestBytes,
              channel.prepare(uid: uid) else { return Data() }
        let hash = ApprovalHash.sha256Hex(request)
        var nonceBytes = [UInt8](repeating: 0, count: 16)
        arc4random_buf(&nonceBytes, nonceBytes.count)
        let nonce = nonceBytes.map { String(format: "%02x", $0) }.joined()
        let startMs = nowMs()

        let folder = (object["cwd"] as? String).map(ClaudeText.folderName(fromCwd:)) ?? ""
        let agent = ((object["agent_id"] as? String).map { String($0.prefix(64)) }) ?? "main"
        let pendingURL = channel.pending.appendingPathComponent("\(sid).\(nonce).json")
        let decisionURL = channel.decisions.appendingPathComponent("\(nonce).json")
        defer {
            _ = unlink(pendingURL.path)
            _ = unlink(decisionURL.path)
        }
        let record: [String: Any] = [
            "v": 1, "nonce": nonce, "sid": sid, "folderName": folder, "agent": agent,
            "mode": (object["permission_mode"] as? String).map { String($0.prefix(32)) } ?? "",
            "ts": startMs, "tier": verdict.tier.rawValue, "why": verdict.why, "request": request,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]),
              data.count <= ApprovalLimits.maxRecordBytes,
              PrivateFile.write(data, to: pendingURL) else { return Data() }

        let deadline = Date().addingTimeInterval(config.waitSeconds)
        var lastTouch = Date()
        while Date() < deadline && !cancelled() {
            var st = stat()
            if lstat(decisionURL.path, &st) == 0 {
                switch ApprovalDecisionFile.validate(path: decisionURL.path, nonce: nonce, hash: hash, tier: verdict.tier,
                                                     startMs: startMs, nowMs: nowMs(), uid: uid) {
                case .success(.allow): return Data(allowOutput.utf8)
                case .success(.deny): return Data(denyOutput.utf8)
                case .failure: _ = unlink(decisionURL.path)   // forged or stale: forget it, keep waiting
                }
            }
            if Date().timeIntervalSince(lastTouch) >= 2 {
                lastTouch = Date()
                utimes(pendingURL.path, nil)
                // The island quit: nobody can answer any more, let the native dialog decide at once.
                if !channel.isAlive(within: config.heartbeatFresh, uid: uid) { break }
            }
            Thread.sleep(forTimeInterval: config.tick)
        }
        return Data()
    }
}
