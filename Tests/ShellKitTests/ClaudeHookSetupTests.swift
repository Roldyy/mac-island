import Foundation
import Testing
@testable import ShellKit

@Suite struct ClaudeHookSetupTests {
    let app = URL(fileURLWithPath: "/Applications/Mac Island.app/Contents/MacOS/MacIsland")

    @Test func hookExecutableSitsNextToTheMainExecutable() {
        #expect(ClaudeHookSetup.hookExecutablePath(mainExecutable: app)
                == "/Applications/Mac Island.app/Contents/MacOS/ClaudeHook")
        #expect(ClaudeHookSetup.hookExecutablePath(mainExecutable: nil) == nil)
    }

    @Test func snippetQuotesThePathAndNamesTheHookEvents() throws {
        let text = try #require(ClaudeHookSetup.snippet(mainExecutable: app))
        #expect(text.contains("'/Applications/Mac Island.app/Contents/MacOS/ClaudeHook'"))
        #expect(text.contains("SessionStart") && text.contains("Stop"))
        #expect(ClaudeHookSetup.snippet(mainExecutable: nil) == nil)
    }

    @Test func pendingRelaunchBadgeIsWorded() {
        #expect(FeatureBadge.pendingRelaunch.text == "Prend effet au prochain lancement")
        #expect(FeatureBadge.pendingRelaunch.status == .warning)
    }
}
