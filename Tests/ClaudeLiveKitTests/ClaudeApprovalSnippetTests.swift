import Foundation
import Testing
@testable import ClaudeLiveKit

@Suite struct ClaudeApprovalSnippetTests {
    @Test func theApprovalBlockHoldsOnlyOnePermissionRequestHookWithATimeout() throws {
        let text = ClaudeHooksSnippet.approvalSettingsJSON(executablePath: "/Applications/Mac Island.app/Contents/MacOS/ClaudeApprove")
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["PermissionRequest"])
        let groups = try #require(hooks["PermissionRequest"] as? [[String: Any]])
        let entry = try #require((groups.first?["hooks"] as? [[String: Any]])?.first)
        #expect(entry["type"] as? String == "command")
        #expect(entry["timeout"] as? Int == 130)
        #expect(entry["command"] as? String == "'/Applications/Mac Island.app/Contents/MacOS/ClaudeApprove'")
    }

    @Test func aPathWithAQuoteStaysOneShellWord() throws {
        let text = ClaudeHooksSnippet.approvalSettingsJSON(executablePath: "/tmp/it's \"x\"/approve")
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let command = try #require(((((root["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first?["hooks"])
            as? [[String: Any]])?.first?["command"] as? String)
        #expect(command == "'/tmp/it'\\''s \"x\"/approve'")
    }

    @Test func theExistingHookBlockIsUntouchedByTheApprovalChannel() {
        // The approval hook is its own block: the five events of the state hook stay exactly as they were.
        #expect(ClaudeHooksSnippet.events == ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"])
    }

    @Test func approvalsAreOffAndSoundIsOnByDefault() throws {
        let suite = "mis-approval-defaults-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ClaudeApprovalSettings.isEnabled(defaults) == false)
        #expect(ClaudeApprovalSettings.soundOn(defaults) == true)
        defaults.set(true, forKey: ClaudeApprovalSettings.enabledKey)
        defaults.set(false, forKey: ClaudeApprovalSettings.soundKey)
        #expect(ClaudeApprovalSettings.isEnabled(defaults) == true)
        #expect(ClaudeApprovalSettings.soundOn(defaults) == false)
    }
}
