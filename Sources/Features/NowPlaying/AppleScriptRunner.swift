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

/// Runs NSAppleScript on a private serial queue, never on the main thread.
/// NSAppleScript is not thread safe, so each call compiles and runs inside the queue.
final class AppleScriptRunner: AppleScriptRunning {
    private let queue = DispatchQueue(label: "mac-island.nowplaying.applescript", qos: .userInitiated)

    init() {}

    func run(_ source: String) async throws -> ScriptResult {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                var info: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(throwing: NowPlayingError.scriptFailed(code: 0)); return
                }
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
