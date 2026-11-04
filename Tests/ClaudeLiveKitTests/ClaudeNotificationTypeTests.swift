import Foundation
import Testing
@testable import ClaudeLiveKit

/// Claude Code sends every notification through the one `Notification` event; only some mean
/// "the user is needed". Types per https://code.claude.com/docs/en/hooks (Notification matchers).
@Suite struct ClaudeNotificationTypeTests {
    private func decide(_ extra: String) -> ClaudeHookAction {
        let json = "{\"hook_event_name\":\"Notification\",\"session_id\":\"abc-123\",\"cwd\":\"/Users/x/demo\"\(extra)}"
        return ClaudeHookRunner.decide(input: Data(json.utf8), now: Fixture.now)
    }

    private func isWaiting(_ action: ClaudeHookAction) -> Bool {
        if case .write(_, let record) = action { record.state == "waiting" } else { false }
    }

    @Test(arguments: ["permission_prompt", "elicitation_dialog",
                      "elicitation_url_dialog", "agent_needs_input"])
    func needsUserTypesWait(_ type: String) {
        #expect(isWaiting(decide(",\"notification_type\":\"\(type)\"")))
    }

    @Test(arguments: ["auth_success", "elicitation_complete", "elicitation_response", "agent_completed",
                      "quota_auto_resume_fired", "quota_auto_resume_stale", "quota_auto_resume_disabled",
                      "plugin_notification", "idle_prompt", "something_new", "Permission_Prompt"])
    func otherTypesLeaveStateUnchanged(_ type: String) {
        #expect(decide(",\"notification_type\":\"\(type)\"") == .ignore)
    }

    @Test func missingOrWrongTypedFieldIsIgnored() {
        #expect(decide("") == .ignore)
        #expect(decide(",\"notification_type\":null") == .ignore)
        #expect(decide(",\"notification_type\":42") == .ignore)
        #expect(decide(",\"notification_type\":[\"permission_prompt\"]") == .ignore)
        #expect(decide(",\"notification_type\":{\"x\":\"permission_prompt\"}") == .ignore)
        #expect(decide(",\"notification_type\":\"\"") == .ignore)
    }

    @Test func hostileValuesAreIgnored() {
        let long = String(repeating: "a", count: 5000)
        #expect(decide(",\"notification_type\":\"\(long)\"") == .ignore)
        #expect(decide(",\"notification_type\":\"permission_prompt\\n\"") == .ignore)
        #expect(decide(",\"notification_type\":\"permission_prompt\\u0000\"") == .ignore)
        #expect(decide(",\"notification_type\":\"permission_prompt \"") == .ignore)
        #expect(decide(",\"notification_type\":\"\\u001b[31mpermission_prompt\"") == .ignore)
        #expect(decide(",\"notification_type\":\"{\\\"a\\\":{\\\"b\\\":1}}\"") == .ignore)
    }

    @Test func otherEventsIgnoreNotificationType() {
        let json = "{\"hook_event_name\":\"Stop\",\"session_id\":\"abc-123\",\"notification_type\":\"x\"}"
        guard case .write(_, let record) = ClaudeHookRunner.decide(input: Data(json.utf8), now: Fixture.now) else {
            Issue.record("Stop must still write"); return
        }
        #expect(record.state == "idle")
    }

    @Test func runLeavesExistingFileAndStdoutEmptyForNonWaitingType() throws {
        let dir = TempDir()
        let working = Data("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s1\"}".utf8)
        ClaudeHookRunner.run(input: working, directory: dir.url, now: Fixture.now)
        let done = Data("{\"hook_event_name\":\"Notification\",\"session_id\":\"s1\",\"notification_type\":\"auth_success\"}".utf8)
        let out = ClaudeHookRunner.run(input: done, directory: dir.url, now: Fixture.now)
        #expect(out.isEmpty)
        let text = try String(contentsOf: dir.url.appendingPathComponent("s1.json"), encoding: .utf8)
        #expect(text.contains("working"))
    }
}
