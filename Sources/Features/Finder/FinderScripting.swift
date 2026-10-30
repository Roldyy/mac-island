import AppKit
import Foundation

enum FinderScriptError: Error, Equatable {
    case notPermitted
    case finderUnavailable
    case failed
    case badResult
}

/// What the controller needs from Finder. Faked in tests.
protocol FinderScripting: Sendable {
    func selection() async throws -> [URL]
    func targetFolder() async throws -> URL
}

/// NSAppleScript on a private serial queue (it is not thread safe, so compile + run happen inside).
/// Only ever called while Finder is frontmost; the first call triggers the Automation prompt, so the
/// app asks first through `AutomationPermission.request()` from a visible button.
final class AppleScriptFinder: FinderScripting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "mac-island.finder.applescript", qos: .userInitiated)

    func selection() async throws -> [URL] {
        FinderPathParser.parseSelection(try await run(FinderScripts.selection))
    }

    func targetFolder() async throws -> URL {
        guard let url = FinderPathParser.parseFolder(try await run(FinderScripts.targetFolder)) else {
            throw FinderScriptError.badResult
        }
        return url
    }

    private func run(_ source: String) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard !NSRunningApplication.runningApplications(withBundleIdentifier: FinderScripts.finderBundleID).isEmpty else {
                    cont.resume(throwing: FinderScriptError.finderUnavailable); return
                }
                var info: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(throwing: FinderScriptError.failed); return
                }
                let desc = script.executeAndReturnError(&info)
                if let info {
                    let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
                    cont.resume(throwing: Self.map(code)); return
                }
                cont.resume(returning: desc.stringValue)
            }
        }
    }

    static func map(_ code: Int) -> FinderScriptError {
        switch code {
        case -1743, -1744: .notPermitted
        case -600, -609: .finderUnavailable
        default: .failed
        }
    }
}
