import ClaudeHookCore
import Foundation

// Hook entry point. Prints NOTHING on stdout (Claude Code reads it) and always exits 0.
let stdout = ClaudeHookRunner.run(input: ClaudeHookRunner.readStandardInput(),
                                  directory: ClaudeHookRunner.defaultDirectory)
if !stdout.isEmpty { FileHandle.standardOutput.write(stdout) }
exit(0)
