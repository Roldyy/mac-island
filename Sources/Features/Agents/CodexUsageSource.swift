import Foundation

/// STUB. `~/.codex/sessions` does not exist on the build machine, so the token-count format is UNKNOWN.
/// Returns no data until a real sample is inspected; never guess a format.
struct CodexUsageSource: UsageSource {
    func load(modifiedSince: Date?) -> UsageLoadResult { UsageLoadResult() }
}
