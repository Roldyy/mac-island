import AppKit
import Foundation

public struct ScriptResult: Sendable {
    public var text: String?
    public var data: Data?
    public init(text: String?, data: Data?) { self.text = text; self.data = data }
}

public protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async throws -> ScriptResult
}

public protocol RunningAppChecking: Sendable {
    func isRunning(bundleID: String) -> Bool
}

/// Asks NSWorkspace, never launches anything.
public struct WorkspaceRunningChecker: RunningAppChecking {
    public init() {}
    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// Runs NSAppleScript on a private serial queue, never on the main thread.
/// NSAppleScript is not thread safe, so each call compiles and runs inside the queue.
public final class AppleScriptRunner: AppleScriptRunning {
    private let queue = DispatchQueue(label: "mac-island.nowplaying.applescript", qos: .userInitiated)

    public init() {}

    public func run(_ source: String) async throws -> ScriptResult {
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
