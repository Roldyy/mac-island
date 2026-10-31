import Foundation

/// STUB. `~/.codex/sessions` does not exist on the build machine, so the token-count format is UNKNOWN.
/// Returns no data until a real sample is inspected; never guess a format. It only reports whether the
/// folder exists, so the tab can tell "Codex absent" from "Codex present, nothing read".
struct CodexUsageSource: UsageSource {
    var directory: URL

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)) {
        self.directory = directory
    }

    func load(modifiedSince: Date?) -> UsageLoadResult {
        var isDirectory: ObjCBool = false
        var result = UsageLoadResult()
        result.directoryMissing = !(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue)
        return result
    }
}
