import AppKit
import Foundation

struct ScriptResult: Sendable {
    var text: String?
    var data: Data?
    init(text: String?, data: Data?) { self.text = text; self.data = data }
}

protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async throws -> ScriptResult
}

protocol RunningAppChecking: Sendable {
    func isRunning(bundleID: String) -> Bool
}

/// Asks NSWorkspace, never launches anything.
struct WorkspaceRunningChecker: RunningAppChecking {
    init() {}
    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// One compiled script per source. A handful of sources exist (status, cover, transport); the cap is a safety net.
struct CompiledScriptCache<Script> {
    private var storage: [String: Script] = [:]
    let limit: Int
    init(limit: Int = 16) { self.limit = limit }

    mutating func script(for source: String, make: (String) -> Script?) -> Script? {
        if let script = storage[source] { return script }
        guard let script = make(source) else { return nil }
        if storage.count >= limit { storage.removeAll() }
        storage[source] = script
        return script
    }
}

/// Runs NSAppleScript on a private serial queue, never on the main thread.
/// NSAppleScript is not thread safe, so every call (and the compiled script cache) stays inside the queue.
/// A script is compiled once per source and reused: the status script runs every second while the Home is open,
/// and a fresh `NSAppleScript` meant a parse and a compile each time.
final class AppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "mac-island.nowplaying.applescript", qos: .userInitiated)
    /// Only touched on `queue`.
    private var cache = CompiledScriptCache<NSAppleScript>()

    init() {}

    func run(_ source: String) async throws -> ScriptResult {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                guard let script = cache.script(for: source, make: { NSAppleScript(source: $0) }) else {
                    cont.resume(throwing: NowPlayingError.scriptFailed(code: 0)); return
                }
                var info: NSDictionary?
                let desc = script.executeAndReturnError(&info)
                if let info {
                    let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
                    cont.resume(throwing: NowPlayingError.from(scriptErrorCode: code)); return
                }
                cont.resume(returning: ScriptResult(text: desc.stringValue, data: desc.data))
            }
        }
    }
}
