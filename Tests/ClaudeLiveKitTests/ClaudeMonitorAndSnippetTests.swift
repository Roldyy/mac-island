import Foundation
import IslandKit
import Testing
@testable import ClaudeLiveKit

@MainActor
final class RecordingSink: ClaudeActivitySink {
    var live: [String: IslandActivity] = [:]
    var withdrawn: [String] = []
    func post(_ activity: IslandActivity) { live[activity.id] = activity }
    func withdraw(id: String) { live[id] = nil; withdrawn.append(id) }
}

final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [ClaudeSession]
    init(_ v: [ClaudeSession]) { value = v }
    func get() -> [ClaudeSession] { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: [ClaudeSession]) { lock.lock(); value = v; lock.unlock() }
}

@Suite @MainActor struct ClaudeMonitorTests {
    private func session(_ id: String, _ state: ClaudeSession.State, folder: String = "demo") -> ClaudeSession {
        ClaudeSession(id: id, pid: 1, state: state, folderName: folder)
    }

    @Test func mapsStatesToPrioritiesAndFrench() {
        let w = ClaudeActivityMapper.activity(for: session("a", .waiting))
        let b = ClaudeActivityMapper.activity(for: session("a", .working))
        #expect(w?.priority == .claudeWaiting)
        #expect(b?.priority == .claudeWorking)
        #expect(w?.trailing?.text == "demo")
        #expect(w?.leading?.text == nil)
        #expect(w?.source == "claude")
        #expect(ClaudeActivityMapper.label(for: .working) == "Claude travaille")
        #expect(ClaudeActivityMapper.label(for: .waiting) == "Claude attend")
        #expect(ClaudeActivityMapper.label(for: .idle) == nil)
    }

    @Test func idleAndUnknownPostNothing() {
        #expect(ClaudeActivityMapper.activity(for: session("a", .idle)) == nil)
        #expect(ClaudeActivityMapper.activity(for: session("a", .unknown)) == nil)
    }

    @Test func emptyFolderOmitsTrailing() {
        #expect(ClaudeActivityMapper.activity(for: session("a", .working, folder: ""))?.trailing == nil)
    }

    @Test func postsThenWithdrawsWhenSessionGoesIdleOrDisappears() {
        let box = Box([session("a", .working), session("b", .waiting)])
        let sink = RecordingSink()
        let monitor = ClaudeLiveMonitor(snapshot: { box.get() }, sink: sink)
        monitor.refresh()
        #expect(monitor.sessions.count == 2)
        #expect(Set(sink.live.keys) == ["claude.a", "claude.b"])

        box.set([session("a", .idle)])
        monitor.refresh()
        #expect(sink.live.isEmpty)
        #expect(Set(sink.withdrawn) == ["claude.a", "claude.b"])
    }

    @Test func stopWithdrawsEverything() {
        let sink = RecordingSink()
        let monitor = ClaudeLiveMonitor(snapshot: { [ClaudeSession(id: "a", pid: 1, state: .working, folderName: "d")] },
                                        sink: sink)
        monitor.refresh()
        #expect(sink.live.count == 1)
        monitor.stop()
        #expect(sink.live.isEmpty)
        #expect(monitor.sessions.isEmpty)
    }

    @Test func pollingLoopPicksUpChanges() async throws {
        let box = Box([])
        let sink = RecordingSink()
        let monitor = ClaudeLiveMonitor(snapshot: { box.get() }, sink: sink, interval: .milliseconds(20))
        monitor.start()
        box.set([session("a", .working)])
        for _ in 0..<100 where sink.live.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(sink.live.keys.contains("claude.a"))
        monitor.stop()
    }
}

@Suite struct ClaudeHooksSnippetTests {
    @Test func isValidJSONWithOnlyTheEventsWeUse() throws {
        let text = ClaudeHooksSnippet.settingsJSON(executablePath: "/Applications/Mac Island.app/Contents/MacOS/ClaudeHook")
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(Set(root.keys) == ["hooks"])
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(ClaudeHooksSnippet.events))
        #expect(Set(hooks.keys) == ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"])
        for (_, value) in hooks {
            let groups = try #require(value as? [[String: Any]])
            let inner = try #require(groups.first?["hooks"] as? [[String: Any]])
            #expect(inner.first?["type"] as? String == "command")
            #expect(inner.first?["command"] as? String
                == "'/Applications/Mac Island.app/Contents/MacOS/ClaudeHook'")
        }
    }

    @Test func quotesAHostilePath() throws {
        let text = ClaudeHooksSnippet.settingsJSON(executablePath: "/tmp/it's \"x\"/hook")
        let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(root["hooks"] != nil)
        #expect(ClaudeHooksSnippet.shellQuoted("/a/it's") == "'/a/it'\\''s'")
    }
}
