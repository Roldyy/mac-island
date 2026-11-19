import ClaudeApproveCore
import Darwin
import Foundation

// PermissionRequest hook entry point. Prints an allow/deny answer ONLY when the island decided it; otherwise nothing,
// and Claude Code shows its own dialog. Always exits 0. A SIGTERM (the native dialog was answered first) stops the wait
// within one tick, and the pending request file is removed on the way out.
nonisolated(unsafe) var stopRequested: sig_atomic_t = 0
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig) { _ in stopRequested = 1 }
}

let stdout = ApprovalHookRunner.run(input: ApprovalHookRunner.readStandardInput(),
                                    channel: ApprovalChannel(root: ApprovalChannel.defaultRoot),
                                    cancelled: { stopRequested != 0 })
if !stdout.isEmpty { FileHandle.standardOutput.write(stdout) }
exit(0)
